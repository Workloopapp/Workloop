import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/auth/password_recovery_screen.dart';
import 'package:workloop/features/calendar_sync/calendar_sync_screen.dart';
import 'package:workloop/features/finance/add_payment_screen.dart';
import 'package:workloop/features/finance/expense_editor_screen.dart';
import 'package:workloop/features/imports/import_data_screen.dart';
import 'package:workloop/features/notifications/notifications_screen.dart';
import 'package:workloop/features/onboarding/screens/ob_welcome.dart';
import 'package:workloop/features/settings/legal_document_screen.dart';
import 'package:workloop/features/settings/support_screen.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';

void main() {
  testWidgets(
    'secondary routes remain coherent on a compact large-text phone',
    (tester) async {
      final authRepository = AuthRepository(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      final overrides = <Override>[
        authRepositoryProvider.overrideWithValue(authRepository),
        clientsProvider.overrideWith((ref) async => const []),
        appointmentsProvider.overrideWith((ref) async => const []),
        notificationsProvider.overrideWith((ref) async => const []),
      ];
      final surfaces = <(String, Widget Function())>[
        ('password recovery', () => const PasswordRecoveryScreen()),
        ('calendar sync', () => const CalendarSyncScreen()),
        ('import data', () => const ImportDataScreen()),
        ('notifications', () => const NotificationsScreen()),
        ('add income', () => const AddPaymentScreen()),
        ('add expense', () => const ExpenseEditorScreen()),
        (
          'privacy policy',
          () => const LegalDocumentScreen(
            document: WorkloopLegalDocument.privacy,
          ),
        ),
        ('help and support', () => const SupportScreen()),
        ('onboarding welcome', () => ObWelcome(onNext: () {})),
      ];
      final appearances = [AppTheme.light, AppTheme.dark];

      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in appearances) {
        for (final surface in surfaces) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: overrides,
              child: MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 700),
                    devicePixelRatio: 1,
                    textScaler: TextScaler.linear(2),
                    disableAnimations: true,
                    padding: EdgeInsets.only(top: 44, bottom: 24),
                  ),
                  child: surface.$2(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason:
                '${surface.$1} failed in ${theme.brightness.name} appearance',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
