import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/subscription/store_purchase_service.dart';
import 'package:workloop/features/subscription/subscription_access.dart';
import 'package:workloop/features/subscription/subscription_screen.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';

import '../support/subscription_fakes.dart';
import '../support/store_trial_fakes.dart';

void main() {
  setUpAll(() async {
    for (final entry in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      'packages/lucide_flutter/LucideIcons':
          'packages/lucide_flutter/assets/lucide.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  for (final fixture in [
    (name: 'plans-light', dark: false, state: 'expired', small: false),
    (name: 'plans-dark', dark: true, state: 'expired', small: false),
    (name: 'trial-light', dark: false, state: 'store_trial', small: false),
    (name: 'cancelled-dark', dark: true, state: 'store_trial', small: false),
    (name: 'lifetime-light', dark: false, state: 'beta_lifetime', small: false),
    (name: 'error-small-dark', dark: true, state: 'error', small: true),
  ]) {
    testWidgets(
      'subscription ${fixture.name}',
      (tester) async {
        final backend = SubscriptionBackend();
        await tester.runAsync(backend.account);
        final store = FakeSubscriptionStore()..products = [appleTrialProduct()];
        final service = StorePurchaseService(
          backend.client,
          subscriptionUser,
          onVerified: () {},
          store: store,
          introductoryOfferEligibility: (_) async => true,
        );
        addTearDown(() async {
          service.dispose();
          await store.events.close();
          await backend.client.dispose();
        });
        final theme = fixture.dark ? AppTheme.dark : AppTheme.light;
        tester.view.physicalSize = fixture.small
            ? const Size(320, 568)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supabaseClientProvider.overrideWithValue(backend.client),
              storePurchaseServiceProvider(
                subscriptionUser,
              ).overrideWithValue(service),
              subscriptionAccessProvider(subscriptionUser).overrideWith((ref) {
                if (fixture.state == 'error') throw StateError('offline');
                return SubscriptionAccess(
                  state: fixture.state,
                  hasAccess: fixture.state != 'expired',
                  serverNow: DateTime.utc(2026, 9, 7),
                  appleSalesEnabled: true,
                  productId: fixture.state == 'store_trial'
                      ? WorkloopPlans.monthlyId
                      : null,
                  platform: fixture.state == 'store_trial' ? 'apple' : null,
                  trialEndsAt: fixture.state == 'store_trial'
                      ? DateTime.utc(2026, 10, 7)
                      : null,
                  paidUntil: fixture.state == 'store_trial'
                      ? DateTime.utc(2026, 10, 7)
                      : null,
                  renewsAt: fixture.state == 'store_trial'
                      ? DateTime.utc(2026, 10, 7)
                      : null,
                  autoRenews: fixture.name == 'cancelled-dark' ? false : true,
                  billingRemindersEnabled: true,
                );
              }),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => RepaintBoundary(
                key: const ValueKey('subscription-golden'),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 34),
                    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
                    textScaler: TextScaler.linear(fixture.small ? 2 : 1),
                  ),
                  child: child!,
                ),
              ),
              home: const SubscriptionScreen(canClose: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = find.byKey(const ValueKey('subscription-golden'));
        final name = 'subscription-${fixture.name}.png';
        if (const bool.fromEnvironment('WORKLOOP_SUBSCRIPTION_REVIEW')) {
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(boundary)
                .toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('/tmp/workloop-subscription-visual-review');
              await dir.create(recursive: true);
              await File(
                '${dir.path}/$name',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await expectLater(boundary, matchesGoldenFile('files/$name'));
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
}
