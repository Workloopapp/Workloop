import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/repositories/profile_repository.dart';
import '../../../shared/utils/public_booking_url.dart';
import '../../../shared/utils/public_profile_routes.dart';
import '../../../shared/widgets/workloop_form_field.dart';

final _handlePattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$');

enum _HandleAvailability { idle, checking, available, taken, reserved, error }

class ObHandle extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const ObHandle({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<ObHandle> createState() => _ObHandleState();
}

class _ObHandleState extends ConsumerState<ObHandle> {
  final _handleController = TextEditingController();
  Timer? _availabilityDebounce;
  int _availabilityRequest = 0;
  String _error = '';
  _HandleAvailability _availability = _HandleAvailability.idle;

  @override
  void initState() {
    super.initState();
    // Pre-fill from business name
    final state = ref.read(onboardingProvider);
    final suggested = state.handle.isNotEmpty
        ? state.handle
        : state.businessName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    _handleController.text = suggested;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _validate(suggested);
    });
  }

  @override
  void dispose() {
    _availabilityDebounce?.cancel();
    _handleController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _handlePattern.hasMatch(_handleController.text.trim().toLowerCase()) &&
      _error.isEmpty &&
      _availability == _HandleAvailability.available;

  void _validate(String value) {
    _availabilityDebounce?.cancel();
    final request = ++_availabilityRequest;
    final clean = value.toLowerCase().trim();
    if (clean.length < 3) {
      setState(() {
        _error = 'Must be at least 3 characters';
        _availability = _HandleAvailability.idle;
      });
    } else if (clean.length > 40) {
      setState(() {
        _error = 'Must be 40 characters or fewer';
        _availability = _HandleAvailability.idle;
      });
    } else if (!_handlePattern.hasMatch(clean)) {
      setState(() {
        _error =
            'Use letters, numbers, and hyphens. Start and end with a letter or number.';
        _availability = _HandleAvailability.idle;
      });
    } else if (isReservedPublicHandle(clean)) {
      setState(() {
        _error = '';
        _availability = _HandleAvailability.reserved;
      });
    } else {
      setState(() {
        _error = '';
        _availability = _HandleAvailability.checking;
      });
      _availabilityDebounce = Timer(
        const Duration(milliseconds: 400),
        () => _checkAvailability(clean, request),
      );
    }
  }

  Future<void> _checkAvailability(String handle, int request) async {
    try {
      final available = await ref
          .read(profileRepositoryProvider)
          .isHandleAvailable(handle);
      if (!mounted ||
          request != _availabilityRequest ||
          _handleController.text.trim().toLowerCase() != handle) {
        return;
      }
      setState(() {
        _availability = available
            ? _HandleAvailability.available
            : _HandleAvailability.taken;
      });
    } catch (_) {
      if (!mounted || request != _availabilityRequest) return;
      setState(() => _availability = _HandleAvailability.error);
    }
  }

  void _retryAvailability() {
    final handle = _handleController.text.trim().toLowerCase();
    if (!_handlePattern.hasMatch(handle) || isReservedPublicHandle(handle)) {
      _validate(handle);
      return;
    }

    _availabilityDebounce?.cancel();
    final request = ++_availabilityRequest;
    setState(() {
      _error = '';
      _availability = _HandleAvailability.checking;
    });
    unawaited(_checkAvailability(handle, request));
  }

  void _continue() {
    if (!_canContinue) return;
    ref
        .read(onboardingProvider.notifier)
        .setHandle(_handleController.text.trim().toLowerCase());
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handleController.text.trim().toLowerCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.pageX),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Your booking page.',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).t1,
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Clients can find you and request a booking at this link. You can share it anywhere.',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.of(context).t3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // URL preview card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.of(context).bgCard,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.of(context).green.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your booking link',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(context).t3,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    children: [
                      TextSpan(
                        text: '$publicBookingPageHost/',
                        style: TextStyle(color: AppColors.of(context).t3),
                      ),
                      TextSpan(
                        text: handle.isEmpty ? 'yourname' : handle,
                        style: TextStyle(
                          color: handle.isEmpty
                              ? AppColors.of(context).t3
                              : AppColors.of(context).green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Handle input
          WorkloopFieldLabel(
            'Choose your handle',
            isRequired: true,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.of(context).t2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _handleController,
            maxLength: 40,
            onChanged: (v) {
              _validate(v);
              setState(() {});
            },
            style: TextStyle(color: AppColors.of(context).t1, fontSize: 15),
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              hintText: 'yourname',
              counterText: '',
              hintStyle: TextStyle(color: AppColors.of(context).t3),
              prefixText: '$publicBookingPageHost/',
              prefixStyle: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 15,
              ),
              filled: true,
              fillColor: AppColors.of(context).bgCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: AppColors.of(context).border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: AppColors.of(context).border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(
                  color: AppColors.of(context).green,
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(
                  color: AppColors.of(context).error,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _error,
                style: TextStyle(
                  color: AppColors.of(context).error,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          if (_error.isEmpty && handle.length >= 3) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    switch (_availability) {
                      _HandleAvailability.available =>
                        Icons.check_circle_rounded,
                      _HandleAvailability.taken ||
                      _HandleAvailability.reserved => Icons.cancel_rounded,
                      _HandleAvailability.error => Icons.error_outline_rounded,
                      _ => Icons.hourglass_top_rounded,
                    },
                    color: switch (_availability) {
                      _HandleAvailability.available => AppColors.of(
                        context,
                      ).success,
                      _HandleAvailability.taken ||
                      _HandleAvailability.reserved ||
                      _HandleAvailability.error => AppColors.of(context).error,
                      _ => AppColors.of(context).t3,
                    },
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      switch (_availability) {
                        _HandleAvailability.available => 'Available',
                        _HandleAvailability.taken =>
                          'That booking link is already taken',
                        _HandleAvailability.reserved =>
                          'That link is reserved by Workloop',
                        _HandleAvailability.error =>
                          'We couldn’t check that booking link. Check your connection and try again.',
                        _ => 'Checking availability…',
                      },
                      style: TextStyle(
                        color: _availability == _HandleAvailability.available
                            ? AppColors.of(context).success
                            : _availability == _HandleAvailability.checking
                            ? AppColors.of(context).t3
                            : AppColors.of(context).error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error.isEmpty && _availability == _HandleAvailability.error) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('onboarding-handle-retry'),
                onPressed: _retryAvailability,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: AppColors.of(context).accentPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Try again',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Letters, numbers and hyphens only. At least 3 characters. Start and end with a letter or number.',
            style: TextStyle(fontSize: 12, color: AppColors.of(context).t3),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _canContinue ? _continue : null,
              child: const Text(
                'Looks good',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
