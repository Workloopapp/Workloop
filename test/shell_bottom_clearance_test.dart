import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('shell counts the home indicator once at text scale $scale', (
      tester,
    ) async {
      double? clearance;
      double? navHeight;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              padding: const EdgeInsets.only(bottom: 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
              textScaler: TextScaler.linear(scale),
            ),
            child: Builder(
              builder: (context) {
                navHeight = AppSpacing.bottomNavHeightFor(context);
                return Scaffold(
                  extendBody: true,
                  bottomNavigationBar: SizedBox(height: navHeight! + 34),
                  body: Builder(
                    builder: (context) {
                      clearance = AppSpacing.shellBottomClearance(context);
                      return const SizedBox.expand();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(clearance, navHeight! + 34 + AppSpacing.bottomNavBreathingRoom);
    });
  }
}
