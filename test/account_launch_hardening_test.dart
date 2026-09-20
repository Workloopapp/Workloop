import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/workloop_app_info.dart';
import 'package:workloop/features/auth/password_recovery_screen.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/onboarding_repository.dart';
import 'package:workloop/shared/repositories/privacy_repository.dart';
import 'package:workloop/shared/utils/public_profile_routes.dart';

void main() {
  test('support version label follows installed artifact metadata', () {
    final originalVersion = WorkloopAppInfo.version;
    final originalBuild = WorkloopAppInfo.buildNumber;
    addTearDown(() {
      WorkloopAppInfo.version = originalVersion;
      WorkloopAppInfo.buildNumber = originalBuild;
    });

    WorkloopAppInfo.version = '2.4.0';
    WorkloopAppInfo.buildNumber = '314';

    expect(WorkloopAppInfo.versionLabel, '2.4.0 (314)');
  });

  test('password recovery uses the registered application scheme', () {
    expect(workloopPasswordRecoveryRedirect, 'workloop://reset-password');
    expect(workloopOAuthRedirect, 'workloop://auth-callback');
    expect(validateRecoveryPassword('short', 'short'), isNotNull);
    expect(
      validateRecoveryPassword('safe-password', 'different-password'),
      isNotNull,
    );
    expect(
      validateRecoveryPassword('Safer-password2!', 'Safer-password2!'),
      isNull,
    );
    expect(
      validateRecoveryPassword(' Long password 2! ', ' Long password 2! '),
      isNull,
      reason: 'Leading and trailing password characters are significant.',
    );
  });

  test('onboarding draft keys are isolated by auth user', () {
    expect(
      onboardingDraftKeyForUser('user-one'),
      isNot(onboardingDraftKeyForUser('user-two')),
    );
    expect(
      onboardingDraftKeyForUser('user-one'),
      startsWith('$legacyOnboardingDraftKey.user.'),
    );
  });

  test('expired access-token rejection refreshes before local sign-out', () {
    expect(
      isRefreshableExpiredAccessTokenFailure(
        statusCode: '403',
        code: 'bad_jwt',
        message: 'token has invalid claims: token is expired',
      ),
      isTrue,
    );
    expect(isTerminalSessionFailure(statusCode: '403'), isFalse);
    expect(isTerminalSessionFailure(code: 'bad_jwt'), isFalse);
    expect(isTerminalSessionFailure(code: 'session_not_found'), isTrue);
    expect(isTerminalSessionFailure(code: 'user_not_found'), isTrue);
    expect(isTerminalSessionFailure(code: 'refresh_token_not_found'), isTrue);
    expect(isTerminalSessionFailure(statusCode: '503'), isFalse);
  });

  test('authenticated routes reuse the restored account bootstrap', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains(
        'final currentUserId = Supabase.instance.client.auth.currentSession?.user.id;',
      ),
    );
    expect(source, contains('_lastUserId = currentUserId;'));
    expect(source, contains('_providersReadyForUserId = currentUserId;'));
  });

  test('onboarding RPC payload uses server contract field names', () {
    final params = buildOnboardingRpcParams(
      businessName: ' Workloop Studio ',
      industry: 'Wellness',
      handle: 'Workloop-Studio',
      services: const [
        {'name': 'Session', 'duration': 45, 'price': 65},
      ],
      workingHours: const {
        'Mon': {'enabled': false},
      },
      revenueTarget: 5000,
      firstBooking: const {
        'clientName': 'Alex',
        'serviceName': 'Session',
        'date': '2026-07-25',
        'hour': 10,
        'minute': 30,
      },
    );

    expect(params['business_name'], 'Workloop Studio');
    expect(params['profile_handle'], 'workloop-studio');
    expect(
      (params['service_rows'] as List).single,
      containsPair('duration_mins', 45),
    );
    expect(
      params['first_booking_value'],
      allOf(
        containsPair('client_name', 'Alex'),
        containsPair('service_name', 'Session'),
      ),
    );
  });

  test('reserved application routes cannot become public handles', () {
    expect(isReservedPublicHandle('clients'), isTrue);
    expect(isReservedPublicHandle('Privacy'), isTrue);
    expect(isReservedPublicHandle('settings'), isTrue);
    expect(isReservedPublicHandle('api'), isTrue);
    expect(isReservedPublicHandle('alex-studio'), isFalse);
  });

  test('privacy export manifest contains every workspace data table', () {
    expect(privacyExportPageSize, 1000);
    expect(
      workspacePrivacyExportTables,
      containsAll(const {
        'workspaces',
        'workspace_members',
        'workspace_settings',
        'business_profiles',
        'expenses',
        'notes',
        'task_checklist_items',
        'invoice_line_items',
        'notification_preferences',
        'account_deletion_requests',
      }),
    );
  });
}
