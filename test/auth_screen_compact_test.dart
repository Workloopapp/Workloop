import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/settings/legal_document_screen.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  testWidgets('standard iPhone sign-in fits before the keyboard opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            devicePixelRatio: 1,
            padding: EdgeInsets.only(top: 47, bottom: 34),
            disableAnimations: true,
          ),
          child: AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final authScroll = find.byKey(const ValueKey('auth-scroll'));
    final scrollable = find.descendant(
      of: authScroll,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.maxScrollExtent, 0);
    expect(
      tester.getRect(find.widgetWithText(TextField, 'Email address')).top,
      lessThanOrEqualTo(280),
    );
    expect(find.byKey(const ValueKey('auth-apple')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-brand-icon')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-brand-panel'))).height,
      lessThanOrEqualTo(128),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('auth-google'))).bottom,
      lessThanOrEqualTo(844),
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('small phone starts the sign-in form near the top', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(375, 667),
            padding: EdgeInsets.only(top: 20, bottom: 0),
            disableAnimations: true,
          ),
          child: AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.widgetWithText(TextField, 'Email address')).top,
      lessThanOrEqualTo(240),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-in remains scrollable when the keyboard reduces height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            devicePixelRatio: 1,
            viewInsets: EdgeInsets.only(bottom: 320),
            disableAnimations: true,
          ),
          child: AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth-scroll')), findsOneWidget);
    await tester.ensureVisible(find.text('Forgot password?'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-in remains scrollable at large accessibility text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            devicePixelRatio: 1,
            padding: EdgeInsets.only(top: 47, bottom: 34),
            textScaler: TextScaler.linear(1.8),
            disableAnimations: true,
          ),
          child: AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('auth-scroll')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.ensureVisible(find.byKey(const ValueKey('auth-google')));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  _testNativeAuth('large iPhone distributes the form and legal footer', (
    tester,
  ) async {
    await _pumpNativeAuth(
      tester,
      size: const Size(430, 932),
      safeArea: const EdgeInsets.only(top: 59, bottom: 34),
    );

    expect(_authPosition(tester).maxScrollExtent, 0);
    final brand = tester.getRect(
      find.byKey(const ValueKey('auth-brand-panel')),
    );
    final title = tester.getRect(find.text('Welcome back.'));
    final email = tester.getRect(
      find.widgetWithText(TextField, 'Email address'),
    );
    expect(brand.top, greaterThanOrEqualTo(59));
    expect(title.top - brand.bottom, greaterThanOrEqualTo(16));
    expect(email.top, greaterThan(title.bottom));
    expect(email.left, 18);
    expect(email.right, 430 - 18);

    final controls = [
      find.byKey(const ValueKey('auth-primary-action')),
      find.byKey(const ValueKey('auth-mode-toggle')),
      find.byKey(const ValueKey('auth-apple')),
      find.byKey(const ValueKey('auth-google')),
      find.byKey(const ValueKey('auth-terms-link')),
    ];
    for (var index = 0; index < controls.length; index++) {
      expect(controls[index].hitTestable(), findsOneWidget);
      expect(tester.getSize(controls[index]).height, greaterThanOrEqualTo(44));
      if (index > 0) {
        expect(
          tester.getRect(controls[index]).top,
          greaterThanOrEqualTo(tester.getRect(controls[index - 1]).bottom),
        );
      }
    }
    final footer = tester.getRect(controls.last);
    // The legal links should use the lower safe area rather than leave a
    // screen-sized blank region beneath a compressed form.
    expect(footer.bottom, inInclusiveRange(932 - 34 - 48, 932 - 34));
    expect(
      find.byKey(const ValueKey('auth-privacy-link')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  _testNativeAuth(
    'small iPhone at double text keeps all access choices reachable',
    (tester) async {
      await _pumpNativeAuth(
        tester,
        size: const Size(320, 568),
        safeArea: const EdgeInsets.only(top: 20),
        textScale: 2,
      );

      expect(_authPosition(tester).maxScrollExtent, greaterThan(0));
      for (final target in [
        find.widgetWithText(TextField, 'Email address'),
        find.widgetWithText(TextField, 'Password'),
        find.byKey(const ValueKey('auth-more-methods')),
        find.widgetWithText(TextButton, 'Forgot password?'),
        find.byKey(const ValueKey('auth-primary-action')),
        find.byKey(const ValueKey('auth-apple')),
        find.byKey(const ValueKey('auth-google')),
        find.byKey(const ValueKey('auth-terms-link')),
        find.byKey(const ValueKey('auth-privacy-link')),
      ]) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
      }

      final createAccount = find.byKey(const ValueKey('auth-mode-toggle'));
      await tester.ensureVisible(createAccount);
      await tester.tap(createAccount);
      await tester.pumpAndSettle();
      expect(find.text('Create your account.'), findsOneWidget);
      expect(_authPosition(tester).pixels, 0);
      for (final key in [
        'auth-primary-action',
        'auth-terms-link',
        'auth-privacy-link',
      ]) {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  _testNativeAuth(
    'small iPhone keyboard can reach reset and return to sign-in',
    (tester) async {
      await _pumpNativeAuth(
        tester,
        size: const Size(320, 568),
        safeArea: const EdgeInsets.only(top: 20),
      );
      final email = find.widgetWithText(TextField, 'Email address');
      await tester.enterText(email, 'owner@example.com');
      tester.view.viewInsets = const FakeViewPadding(bottom: 216);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(_authPosition(tester).maxScrollExtent, greaterThan(0));
      final password = find.widgetWithText(TextField, 'Password');
      await tester.ensureVisible(password);
      await tester.enterText(password, 'Local-only-fixture-123!');
      await tester.pumpAndSettle();
      expect(tester.getRect(password).bottom, lessThanOrEqualTo(568 - 216));
      final forgot = find.widgetWithText(TextButton, 'Forgot password?');
      await tester.ensureVisible(forgot);
      await tester.tap(forgot);
      await tester.pumpAndSettle();
      expect(find.text('Reset password.'), findsOneWidget);
      expect(
        tester.widget<TextField>(email).controller!.text,
        'owner@example.com',
      );
      expect(find.widgetWithText(TextField, 'Password'), findsNothing);

      final primary = find.byKey(const ValueKey('auth-primary-action'));
      await tester.ensureVisible(primary);
      expect(primary.hitTestable(), findsOneWidget);
      expect(find.text('Send reset email'), findsOneWidget);
      final back = find.byKey(const ValueKey('auth-return-mode-toggle'));
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('Welcome back.'), findsOneWidget);
      expect(
        tester.widget<TextField>(email).controller!.text,
        'owner@example.com',
      );
      expect(tester.widget<TextField>(password).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  _testNativeAuth(
    'registration retains entered details after both legal pages',
    (tester) async {
      await _pumpNativeAuth(tester);
      await tester.tap(find.byKey(const ValueKey('auth-mode-toggle')));
      await tester.pumpAndSettle();
      final email = find.widgetWithText(TextField, 'Email address');
      final password = find.widgetWithText(TextField, 'Password');
      await tester.enterText(email, 'owner@example.com');
      await tester.enterText(password, 'Local-only-fixture-123!');

      for (final key in ['auth-terms-link', 'auth-privacy-link']) {
        final link = find.byKey(ValueKey(key));
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        final back = find.byWidgetPredicate(
          (widget) =>
              widget is WorkloopIconButton &&
              widget.semanticLabel == 'Back to account access',
        );
        await tester.ensureVisible(back);
        expect(back.hitTestable(), findsOneWidget);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsNothing);
        expect(find.text('Create your account.'), findsOneWidget);
        expect(
          tester.widget<TextField>(email).controller!.text,
          'owner@example.com',
        );
        expect(
          tester.widget<TextField>(password).controller!.text,
          'Local-only-fixture-123!',
        );
        expect(tester.widget<TextField>(password).obscureText, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

void _testNativeAuth(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      // Flutter checks debug globals before addTearDown callbacks run.
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

ScrollPosition _authPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('auth-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _pumpNativeAuth(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  EdgeInsets safeArea = const EdgeInsets.only(top: 47, bottom: 34),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            padding: safeArea.copyWith(
              bottom: media.viewInsets.bottom > 0 ? 0 : safeArea.bottom,
            ),
            viewPadding: safeArea,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        );
      },
      home: const AuthScreen(),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}
