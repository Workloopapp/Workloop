import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/account_deletion_confirmation_screen.dart';
import 'package:workloop/shared/repositories/privacy_repository.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'manual Apple unlink confirmation fits 320px and 2x text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const AccountDeletionConfirmationScreen(
                result: AccountDeletionResult(
                  appleRevocation: AppleAccountRevocation.manualActionRequired,
                ),
              ),
            ),
            GoRoute(
              path: '/auth',
              builder: (_, _) => const Scaffold(body: Text('Sign in')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: dark ? AppTheme.dark : AppTheme.light,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your request is recorded'), findsOneWidget);
        expect(
          find.textContaining('Provider issues may delay'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Stop Using Sign in with Apple'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Open Apple Account'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Back to sign in'));
        await tester.tap(find.text('Back to sign in'));
        await tester.pumpAndSettle();
        expect(find.text('Sign in'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
