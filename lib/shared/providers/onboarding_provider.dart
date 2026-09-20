import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/supabase_client_provider.dart';

const legacyOnboardingDraftKey = 'workloop.onboarding.draft.v1';

String onboardingDraftKeyForUser(String userId) {
  return '$legacyOnboardingDraftKey.user.$userId';
}

class OnboardingState {
  final String logoUrl;
  final String firstName;
  final String businessName;
  final String industry;
  final String handle;
  final List<Map<String, dynamic>> services;
  final bool servicesReviewed;
  final Map<String, dynamic> workingHours;
  final double revenueTarget;
  final Map<String, dynamic>?
  firstBooking; // {clientName, serviceName, date, hour, minute}
  final bool importAfterSetup;
  final Map<String, bool> notificationPreferences;
  final int currentStep;

  const OnboardingState({
    this.logoUrl = '',
    this.firstName = '',
    this.businessName = '',
    this.industry = '',
    this.handle = '',
    this.services = const [],
    this.servicesReviewed = false,
    this.workingHours = const {},
    this.revenueTarget = 0,
    this.firstBooking,
    this.importAfterSetup = false,
    this.notificationPreferences = const {
      'all_notifications': true,
      'new_booking': true,
      'booking_request': true,
      'payment_received': true,
      'invoice_overdue': true,
      'task_due_morning': true,
    },
    this.currentStep = 0,
  });

  OnboardingState copyWith({
    String? logoUrl,
    String? firstName,
    String? businessName,
    String? industry,
    String? handle,
    List<Map<String, dynamic>>? services,
    bool? servicesReviewed,
    Map<String, dynamic>? workingHours,
    double? revenueTarget,
    Map<String, dynamic>? firstBooking,
    bool clearFirstBooking = false,
    bool? importAfterSetup,
    Map<String, bool>? notificationPreferences,
    int? currentStep,
  }) {
    return OnboardingState(
      logoUrl: logoUrl ?? this.logoUrl,
      firstName: firstName ?? this.firstName,
      businessName: businessName ?? this.businessName,
      industry: industry ?? this.industry,
      handle: handle ?? this.handle,
      services: services ?? this.services,
      servicesReviewed: servicesReviewed ?? this.servicesReviewed,
      workingHours: workingHours ?? this.workingHours,
      revenueTarget: revenueTarget ?? this.revenueTarget,
      firstBooking: clearFirstBooking
          ? null
          : firstBooking ?? this.firstBooking,
      importAfterSetup: importAfterSetup ?? this.importAfterSetup,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
      currentStep: currentStep ?? this.currentStep,
    );
  }

  Map<String, dynamic> toJson() => {
    'logoUrl': logoUrl,
    'firstName': firstName,
    'businessName': businessName,
    'industry': industry,
    'handle': handle,
    'services': services,
    'servicesReviewed': servicesReviewed,
    'workingHours': workingHours,
    'revenueTarget': revenueTarget,
    'firstBooking': firstBooking,
    'importAfterSetup': importAfterSetup,
    'notificationPreferences': notificationPreferences,
    'currentStep': currentStep,
  };

  factory OnboardingState.fromJson(Map<String, dynamic> json) {
    return OnboardingState(
      logoUrl: json['logoUrl'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      businessName: json['businessName'] as String? ?? '',
      industry: json['industry'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      services: (json['services'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      servicesReviewed:
          json['servicesReviewed'] as bool? ??
          ((json['services'] as List?)?.isNotEmpty == true ||
              ((json['currentStep'] as num?)?.toInt() ?? 0) > 3),
      workingHours: Map<String, dynamic>.from(
        json['workingHours'] as Map? ?? const {},
      ),
      revenueTarget: (json['revenueTarget'] as num?)?.toDouble() ?? 0,
      firstBooking: json['firstBooking'] is Map
          ? Map<String, dynamic>.from(json['firstBooking'] as Map)
          : null,
      importAfterSetup: json['importAfterSetup'] as bool? ?? false,
      notificationPreferences:
          (json['notificationPreferences'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value == true),
          ) ??
          const {
            'all_notifications': true,
            'new_booking': true,
            'booking_request': true,
            'payment_received': true,
            'invoice_overdue': true,
            'task_due_morning': true,
          },
      currentStep: (json['currentStep'] as num?)?.toInt() ?? 0,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  Future<void> _pendingDraftWrite = Future<void>.value();
  String? _restoredForUserId;

  @override
  OnboardingState build() => const OnboardingState();

  String? get _currentUserId =>
      ref.read(supabaseClientProvider).auth.currentUser?.id;

  Future<void> restore() async {
    final userId = _currentUserId;
    if (userId == null || _restoredForUserId == userId) return;
    await _pendingDraftWrite;
    if (!ref.mounted || _currentUserId != userId) return;
    _restoredForUserId = userId;
    state = const OnboardingState();

    // The legacy key was shared by every account on the device and may contain
    // private client/business details. Never migrate it between users.
    try {
      await _preferences.remove(legacyOnboardingDraftKey);
      final value = await _preferences.getString(
        onboardingDraftKeyForUser(userId),
      );
      if (!ref.mounted || _currentUserId != userId) return;
      if (value == null || value.isEmpty) return;
      state = OnboardingState.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      // Device storage must not leave a new account stuck on a loading screen.
      // A future edit can save a new draft; never apply another user's draft.
      try {
        await _preferences.remove(onboardingDraftKeyForUser(userId));
      } catch (_) {}
    }
  }

  void _set(OnboardingState next) {
    state = next;
    final userId = _currentUserId;
    if (userId == null) return;
    final draftKey = onboardingDraftKeyForUser(userId);
    final encodedDraft = jsonEncode(next.toJson());
    _pendingDraftWrite = _pendingDraftWrite.then((_) async {
      try {
        await _preferences.setString(draftKey, encodedDraft);
      } catch (_) {
        // A later state change may retry persistence. The in-memory onboarding
        // flow remains usable when device storage is temporarily unavailable.
      }
    });
    unawaited(_pendingDraftWrite);
  }

  void setLogoUrl(String url) => _set(state.copyWith(logoUrl: url));

  void setName(String firstName, String businessName) {
    _set(state.copyWith(firstName: firstName, businessName: businessName));
  }

  void setIndustry(String industry) {
    _set(state.copyWith(industry: industry));
  }

  void setHandle(String handle) {
    _set(state.copyWith(handle: handle));
  }

  void setServices(List<Map<String, dynamic>> services) {
    final bookingService = state.firstBooking?['serviceName'];
    _set(
      state.copyWith(
        services: services,
        servicesReviewed: true,
        clearFirstBooking:
            bookingService != null &&
            !services.any((service) => service['name'] == bookingService),
      ),
    );
  }

  void setWorkingHours(Map<String, dynamic> hours) {
    _set(state.copyWith(workingHours: hours));
  }

  void setRevenueTarget(double target) {
    _set(state.copyWith(revenueTarget: target));
  }

  void setFirstBooking(Map<String, dynamic> booking) {
    _set(state.copyWith(firstBooking: booking));
  }

  void clearFirstBooking() => _set(state.copyWith(clearFirstBooking: true));

  void setImportAfterSetup(bool enabled) {
    _set(state.copyWith(importAfterSetup: enabled));
  }

  void setNotificationPreference(String key, bool enabled) {
    _set(
      state.copyWith(
        notificationPreferences: {
          ...state.notificationPreferences,
          key: enabled,
        },
      ),
    );
  }

  void setStep(int step) => _set(state.copyWith(currentStep: step));

  Future<void> clearDraft() async {
    state = const OnboardingState();
    final userId = _currentUserId;
    if (userId != null) {
      await _pendingDraftWrite;
      try {
        await _preferences.remove(onboardingDraftKeyForUser(userId));
      } catch (_) {
        // Workspace creation has already succeeded; a local cleanup failure
        // must not prevent entering the saved business.
      }
    }
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
      OnboardingNotifier.new,
    );
