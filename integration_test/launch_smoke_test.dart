import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:workloop/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-out launch and auth navigation stay usable', (
    tester,
  ) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('Sign in to your workspace.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Forgot password?'), findsOneWidget);

    final firstRunCta = find.byKey(const ValueKey('auth-first-run-cta'));
    expect(firstRunCta, findsOneWidget);
    await tester.tap(firstRunCta);
    await tester.pumpAndSettle();
    expect(find.text('Create your account.'), findsOneWidget);
    expect(
      find.text('Start running your business from one app.'),
      findsOneWidget,
    );

    // Signup has its own return control; the first-run CTA belongs to login.
    final returnToSignIn = find.byKey(
      const ValueKey('auth-return-mode-toggle'),
    );
    expect(returnToSignIn, findsOneWidget);
    await tester.ensureVisible(returnToSignIn);
    await tester.pumpAndSettle();
    expect(returnToSignIn.hitTestable(), findsOneWidget);
    await tester.tap(returnToSignIn);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('Create your account.'), findsNothing);

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password.'), findsOneWidget);
    expect(find.text('Send reset email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
