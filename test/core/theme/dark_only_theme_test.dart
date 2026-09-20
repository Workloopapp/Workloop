import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/settings_screen.dart';
import 'package:workloop/shared/providers/theme_mode_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';

class _MemoryThemeModeStore implements ThemeModeStore {
  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {
    this.value = value;
  }
}

void main() {
  test('Workloop ships coordinated light and dark theme contracts', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(WorkloopThemeTokens.light.background.toARGB32(), 0xFFF5EDD9);
    expect(WorkloopThemeTokens.dark.background.toARGB32(), 0xFF171D22);
    expect(WorkloopThemeTokens.light.accent.toARGB32(), 0xFF91B4C8);
    expect(WorkloopThemeTokens.dark.accent.toARGB32(), 0xFFA3C5D7);
  });

  test('native startup windows allow the operating-system appearance', () {
    final androidStyles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();
    final androidNightStyles = File(
      'android/app/src/main/res/values-night/styles.xml',
    ).readAsStringSync();
    final androidColors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    final androidNightColors = File(
      'android/app/src/main/res/values-night/colors.xml',
    ).readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();

    expect(androidStyles, contains('Theme.Light.NoTitleBar'));
    expect(androidNightStyles, contains('Theme.Black.NoTitleBar'));
    expect(androidColors, contains('#F5EDD9'));
    expect(androidColors, contains('#C3D7E4'));
    expect(androidNightColors, contains('#171D22'));
    expect(androidNightColors, contains('#C3D7E4'));
    expect(
      File(
        'android/app/src/main/res/drawable/launch_background.xml',
      ).readAsStringSync(),
      contains('@drawable/launch_image'),
    );
    expect(
      File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync(),
      contains('image="LaunchImage"'),
    );
    expect(
      File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      ).lengthSync(),
      greaterThan(1000),
    );
    for (final path in [
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png',
      'android/app/src/main/res/drawable-mdpi/launch_image.png',
    ]) {
      final bytes = File(path).readAsBytesSync();
      expect(
        bytes[25],
        anyOf(4, 6),
        reason: '$path must use PNG alpha over one native splash background',
      );
    }
    final launchAsset =
        jsonDecode(
              File(
                'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final colours = (launchAsset['colors'] as List)
        .cast<Map<String, dynamic>>();
    final light = colours.singleWhere((entry) => entry['appearances'] == null);
    final dark = colours.singleWhere(
      (entry) => (entry['appearances'] as List? ?? const []).any(
        (appearance) =>
            appearance['appearance'] == 'luminosity' &&
            appearance['value'] == 'dark',
      ),
    );
    expect(_launchAssetColor(light).toARGB32(), 0xFFF5EDD9);
    expect(_launchAssetColor(dark).toARGB32(), 0xFF171D22);
    expect(iosInfo, isNot(contains('<key>UIUserInterfaceStyle</key>')));
  });

  testWidgets('Settings exposes persisted System, Light, and Dark choices', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final store = _MemoryThemeModeStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(AuthRepository(client)),
          themeModeStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.light,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('App appearance'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('App appearance'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('App appearance'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('appearance-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('appearance-light')), findsOneWidget);
    expect(find.byKey(const ValueKey('appearance-dark')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('appearance-light')));
    await tester.pumpAndSettle();

    expect(store.value, WorkloopAppearance.light.name);
  });

  testWidgets(
    'Settings avatar and row ink change appearance in the first frame',
    (tester) async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final store = _MemoryThemeModeStore();
      var themeMode = ThemeMode.light;
      late StateSetter setThemeMode;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(AuthRepository(client)),
            themeModeStoreProvider.overrideWithValue(store),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              setThemeMode = setState;
              return MaterialApp(
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                themeAnimationDuration: Duration.zero,
                home: const SettingsScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      Color iconSurface(String key) {
        final container = tester.widget<Container>(find.byKey(ValueKey(key)));
        return (container.decoration! as BoxDecoration).color!;
      }

      final alertsIconKey = 'settings-row-icon-${LucideIcons.bell.codePoint}';
      Color rowIconInk() => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(ValueKey(alertsIconKey)),
              matching: find.byIcon(LucideIcons.bell),
            ),
          )
          .color!;
      expect(rowIconInk(), WorkloopThemeTokens.light.accentInk);
      expect(
        iconSurface('settings-account-avatar'),
        WorkloopThemeTokens.light.surfaceRaised,
      );

      setThemeMode(() => themeMode = ThemeMode.dark);
      await tester.pump();

      expect(rowIconInk(), WorkloopThemeTokens.dark.accentInk);
      expect(
        iconSurface('settings-account-avatar'),
        WorkloopThemeTokens.dark.surfaceRaised,
      );
    },
  );
}

Color _launchAssetColor(Map<String, dynamic> entry) {
  final components = (entry['color'] as Map)['components'] as Map;
  return Color.from(
    alpha: double.parse(components['alpha'] as String),
    red: double.parse(components['red'] as String),
    green: double.parse(components['green'] as String),
    blue: double.parse(components['blue'] as String),
  );
}
