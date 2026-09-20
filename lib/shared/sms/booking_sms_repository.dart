import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/workspace_provider.dart';
import '../repositories/supabase_client_provider.dart';

enum BookingSmsAvailability { ready, notReady, couldNotCheck }

class BookingSmsCapabilities {
  final BookingSmsAvailability availability;
  final Set<int> allowedMinutes;

  const BookingSmsCapabilities({
    required this.availability,
    this.allowedMinutes = const {},
  });

  bool get available => availability == BookingSmsAvailability.ready;

  factory BookingSmsCapabilities.fromJson(Object? value) {
    if (value is! Map || value['available'] is! bool) {
      return const BookingSmsCapabilities(
        availability: BookingSmsAvailability.couldNotCheck,
      );
    }
    final rawMinutes = value['allowed_minutes'];
    final minutes = rawMinutes is List
        ? rawMinutes.whereType<int>().where((n) => n == 1440 || n == 60).toSet()
        : <int>{};
    return BookingSmsCapabilities(
      availability:
          value['available'] == true &&
              value['customer_permission_required'] == true &&
              minutes.isNotEmpty
          ? BookingSmsAvailability.ready
          : BookingSmsAvailability.notReady,
      allowedMinutes: minutes,
    );
  }

  String get unavailableMessage =>
      availability == BookingSmsAvailability.couldNotCheck
      ? 'Could not check text reminder availability. Please try again.'
      : 'Text reminders are not available yet. Your email reminders are unaffected.';
}

// Match the server's supported UK mobile format. Permission is never inferred
// from a phone number; this only checks the number the owner is viewing.
String? bookingSmsPhone(String value) {
  final number = value.replaceAll(RegExp(r'[ ()-]'), '');
  return RegExp(r'^\+44(7[1-57-9][0-9]{8}|7624[0-9]{6})$').hasMatch(number)
      ? number
      : null;
}

class BookingSmsConsent {
  final String? phone;
  final bool consented;
  final bool providerStopped;

  const BookingSmsConsent({
    required this.phone,
    required this.consented,
    required this.providerStopped,
  });

  factory BookingSmsConsent.fromJson(Object? value) {
    if (value is! Map ||
        value['consented'] is! bool ||
        value['provider_stopped'] is! bool) {
      throw const FormatException('Invalid reminder permission');
    }
    return BookingSmsConsent(
      phone: value['phone'] is String
          ? bookingSmsPhone(value['phone'] as String)
          : null,
      consented: value['consented'] == true,
      providerStopped: value['provider_stopped'] == true,
    );
  }
}

final bookingSmsRepositoryProvider = Provider(
  (ref) => BookingSmsRepository(ref.watch(supabaseClientProvider)),
);

final bookingSmsCapabilitiesProvider =
    FutureProvider.autoDispose<BookingSmsCapabilities>((ref) async {
      final workspaceId = await ref.watch(workspaceIdProvider.future);
      if (workspaceId == null) {
        return const BookingSmsCapabilities(
          availability: BookingSmsAvailability.notReady,
        );
      }
      return ref.watch(bookingSmsRepositoryProvider).capabilities();
    });

// Including the displayed number prevents a phone edit retaining the previous
// number's permission while the fresh, server-authoritative result loads.
typedef BookingSmsContact = ({String contactId, String phone});

final bookingSmsConsentProvider = FutureProvider.autoDispose
    .family<BookingSmsConsent, BookingSmsContact>((ref, contact) async {
      final workspaceId = await ref.watch(workspaceIdProvider.future);
      if (workspaceId == null) throw StateError('No workspace');
      return ref
          .watch(bookingSmsRepositoryProvider)
          .getConsent(contact.contactId);
    });

class BookingSmsRepository {
  final SupabaseClient _client;
  const BookingSmsRepository(this._client);

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<BookingSmsCapabilities> capabilities() async {
    try {
      final response = await _client.functions
          .invoke('sms-booking-reminders', body: {'action': 'capabilities'})
          .timeout(const Duration(seconds: 12));
      return BookingSmsCapabilities.fromJson(response.data);
    } on FunctionException catch (error) {
      // An older deployment can lack the function entirely. Show an ordinary
      // unavailable feature rather than exposing a transport/RPC error.
      return BookingSmsCapabilities(
        availability: error.status == 404
            ? BookingSmsAvailability.notReady
            : BookingSmsAvailability.couldNotCheck,
      );
    } catch (_) {
      return const BookingSmsCapabilities(
        availability: BookingSmsAvailability.couldNotCheck,
      );
    }
  }

  Future<BookingSmsConsent> getConsent(String contactId) async =>
      BookingSmsConsent.fromJson(
        await _client.rpc(
          'get_booking_sms_consent',
          params: {'p_contact_id': contactId},
        ),
      );

  Future<BookingSmsConsent> setConsent({
    required String contactId,
    required bool enabled,
    required String expectedPhone,
  }) async => BookingSmsConsent.fromJson(
    await _client.rpc(
      'set_booking_sms_consent',
      params: {
        'p_contact_id': contactId,
        'p_enabled': enabled,
        'p_expected_phone': expectedPhone,
      },
    ),
  );
}
