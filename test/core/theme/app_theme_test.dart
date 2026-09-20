import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';

void main() {
  test('Quiet + Warm accent remains readable in both appearances', () {
    for (final (colors, expected) in [
      (AppColors.light, 0xFF91B4C8),
      (AppColors.dark, 0xFFA3C5D7),
    ]) {
      expect(colors.brandAccent.toARGB32(), expected);
      expect(
        _contrastRatio(colors.onBrandAccent, colors.brandAccent),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(WorkloopThemeTokens.light.accent.toARGB32(), 0xFF91B4C8);
    expect(WorkloopThemeTokens.dark.accent.toARGB32(), 0xFFA3C5D7);
    expect(WorkloopThemeTokens.dark.accentStrong.toARGB32(), 0xFFB9D4E2);
  });

  test('dark slate layers stay distinct', () {
    const tokens = WorkloopThemeTokens.dark;

    expect(tokens.background.toARGB32(), 0xFF171D22);
    expect(tokens.surface.toARGB32(), 0xFF212A31);
    expect(tokens.surfaceRaised.toARGB32(), 0xFF2B363F);
    expect(tokens.surfaceSubtle.toARGB32(), 0xFF33404A);
    expect(
      tokens.background.computeLuminance(),
      lessThan(tokens.surface.computeLuminance()),
    );
    expect(
      tokens.surface.computeLuminance(),
      lessThan(tokens.surfaceRaised.computeLuminance()),
    );
    expect(
      tokens.surfaceRaised.computeLuminance(),
      lessThan(tokens.surfaceSubtle.computeLuminance()),
    );
  });

  test('light layers are crisp, low-glare, and quietly distinct', () {
    const tokens = WorkloopThemeTokens.light;

    expect(tokens.background.computeLuminance(), lessThan(0.95));
    expect(tokens.background, isNot(tokens.surface));
    expect(tokens.surface, isNot(tokens.surfaceRaised));
    expect(tokens.surfaceRaised, isNot(tokens.surfaceSubtle));
    expect(
      _contrastRatio(tokens.surface, tokens.background),
      greaterThanOrEqualTo(1.05),
    );
    expect(
      _contrastRatio(tokens.surfaceRaised, tokens.background),
      greaterThanOrEqualTo(1.04),
    );
    expect(_contrastRatio(tokens.divider, tokens.surface), greaterThan(1.25));
    expect(
      _contrastRatio(tokens.dividerStrong, tokens.surface),
      greaterThanOrEqualTo(1.5),
    );
  });

  test('light semantic colours remain identical during dark refinement', () {
    const tokens = WorkloopThemeTokens.light;
    final expected = <String, (Color, int)>{
      'background': (tokens.background, 0xFFF5EDD9),
      'surface': (tokens.surface, 0xFFFBF7ED),
      'surfaceRaised': (tokens.surfaceRaised, 0xFFEFE5CF),
      'surfaceSubtle': (tokens.surfaceSubtle, 0xFFE9DFCA),
      'divider': (tokens.divider, 0xFFB5A997),
      'dividerStrong': (tokens.dividerStrong, 0xFF80715E),
      'textPrimary': (tokens.textPrimary, 0xFF443C32),
      'textSecondary': (tokens.textSecondary, 0xFF665949),
      'textTertiary': (tokens.textTertiary, 0xFF706658),
      'textDisabled': (tokens.textDisabled, 0xFF928674),
      'accent': (tokens.accent, 0xFF91B4C8),
      'accentStrong': (tokens.accentStrong, 0xFF88ADC2),
      'accentInk': (tokens.accentInk, 0xFF286280),
      'accentBorder': (tokens.accentBorder, 0xFF88ADC2),
      'onAccent': (tokens.onAccent, 0xFF443C32),
      'primaryAction': (tokens.primaryAction, 0xFF91B4C8),
      'onPrimaryAction': (tokens.onPrimaryAction, 0xFF443C32),
      'inkSurface': (tokens.inkSurface, 0xFFC3D7E4),
      'onInk': (tokens.onInk, 0xFF443C32),
      'onInkMuted': (tokens.onInkMuted, 0xFF665949),
      'success': (tokens.success, 0xFF356246),
      'successContainer': (tokens.successContainer, 0xFFE5EAD6),
      'warning': (tokens.warning, 0xFF745322),
      'warningContainer': (tokens.warningContainer, 0xFFF0D18B),
      'error': (tokens.error, 0xFFA7442D),
      'errorContainer': (tokens.errorContainer, 0xFFF3DAD0),
      'info': (tokens.info, 0xFF286280),
      'infoContainer': (tokens.infoContainer, 0xFFDCE8EB),
      'scrim': (tokens.scrim, 0x52000000),
      'skeletonBase': (tokens.skeletonBase, 0xFFDFD5C1),
      'skeletonHighlight': (tokens.skeletonHighlight, 0xFFFBF7ED),
      'paperBlue': (tokens.paperBlue, 0xFFC3D7E4),
      'paperYellow': (tokens.paperYellow, 0xFFF0D18B),
      'onPaperStrip': (tokens.onPaperStrip, 0xFF443C32),
      'illustrationAccent': (tokens.illustrationAccent, 0xFFD57958),
      'headerField': (tokens.headerField, 0xFFC3D7E4),
      'frame': (tokens.frame, 0xFF80715E),
      'providerAttributionInk': (tokens.providerAttributionInk, 0xFF5E5E5E),
      'heroSurface': (tokens.heroSurface, 0xFFC3D7E4),
      'heroControlSurface': (tokens.heroControlSurface, 0xFF91B4C8),
    };
    for (final role in expected.entries) {
      expect(role.value.$1.toARGB32(), role.value.$2, reason: role.key);
    }
  });

  test('dark text stays readable on its content and control surfaces', () {
    const tokens = WorkloopThemeTokens.dark;
    final surfaces = {
      'canvas': tokens.background,
      'card': tokens.surface,
      'raised': tokens.surfaceRaised,
      'input': tokens.surfaceSubtle,
      'blue paper': tokens.paperBlue,
      'warm paper': tokens.paperYellow,
    };
    final text = {
      'primary': tokens.textPrimary,
      'secondary': tokens.textSecondary,
      'tertiary': tokens.textTertiary,
      'accent': tokens.accentInk,
    };
    for (final surface in surfaces.entries) {
      for (final ink in text.entries) {
        expect(
          _contrastRatio(ink.value, surface.value),
          greaterThanOrEqualTo(4.5),
          reason: '${ink.key} on ${surface.key}',
        );
      }
      // Inactive content is quieter, while still legible in this palette.
      expect(
        _contrastRatio(tokens.textDisabled, surface.value),
        greaterThanOrEqualTo(3),
        reason: 'disabled on ${surface.key}',
      );
    }
    for (final (role, foreground, background) in [
      ('success', tokens.success, tokens.successContainer),
      ('warning', tokens.warning, tokens.warningContainer),
      ('error', tokens.error, tokens.errorContainer),
      ('info', tokens.info, tokens.infoContainer),
      ('selected check', tokens.onAccent, tokens.accentStrong),
      ('primary action', tokens.onPrimaryAction, tokens.primaryAction),
    ]) {
      expect(
        _contrastRatio(foreground, background),
        greaterThanOrEqualTo(4.5),
        reason: role,
      );
    }
  });

  test('dark input frames and focus cues contrast with their actual fill', () {
    final theme = AppTheme.dark;
    const tokens = WorkloopThemeTokens.dark;
    final input = theme.inputDecorationTheme;
    final fill = input.fillColor!;
    expect(fill, tokens.surface);
    for (final (name, border) in [
      ('enabled', input.enabledBorder),
      ('disabled', input.disabledBorder),
      ('focused', input.focusedBorder),
    ]) {
      expect(
        _contrastRatio(border!.borderSide.color, fill),
        greaterThanOrEqualTo(3),
        reason: '$name input frame',
      );
    }
    expect(
      _contrastRatio(theme.checkboxTheme.side!.color, tokens.surface),
      greaterThanOrEqualTo(3),
    );
    expect(
      _contrastRatio(tokens.primaryAction, tokens.surface),
      greaterThanOrEqualTo(3),
    );
    expect(
      _contrastRatio(input.hintStyle!.color!, fill),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(input.labelStyle!.color!, fill),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('immutable colour aliases retain every approved appearance value', () {
    // Light values are fixed; dark values reflect the reviewed slate palette.
    final roles = <String, (Color, Color, int, int)>{
      'bg': (AppColors.light.bg, AppColors.dark.bg, 0xFFF5EDD9, 0xFF171D22),
      'bgCard': (
        AppColors.light.bgCard,
        AppColors.dark.bgCard,
        0xFFFBF7ED,
        0xFF212A31,
      ),
      'bgRaised': (
        AppColors.light.bgRaised,
        AppColors.dark.bgRaised,
        0xFFEFE5CF,
        0xFF2B363F,
      ),
      'bgInteract': (
        AppColors.light.bgInteract,
        AppColors.dark.bgInteract,
        0xFFE9DFCA,
        0xFF33404A,
      ),
      'border': (
        AppColors.light.border,
        AppColors.dark.border,
        0xFFB5A997,
        0xFF455660,
      ),
      'borderStrong': (
        AppColors.light.borderStrong,
        AppColors.dark.borderStrong,
        0xFF80715E,
        0xFF667984,
      ),
      't1': (AppColors.light.t1, AppColors.dark.t1, 0xFF443C32, 0xFFF4F0E7),
      't2': (AppColors.light.t2, AppColors.dark.t2, 0xFF665949, 0xFFCDD1CE),
      't3': (AppColors.light.t3, AppColors.dark.t3, 0xFF706658, 0xFFA8B5B9),
      't4': (AppColors.light.t4, AppColors.dark.t4, 0xFF928674, 0xFF87979F),
      'brandAccent': (
        AppColors.light.brandAccent,
        AppColors.dark.brandAccent,
        0xFF91B4C8,
        0xFFA3C5D7,
      ),
      'onBrandAccent': (
        AppColors.light.onBrandAccent,
        AppColors.dark.onBrandAccent,
        0xFF443C32,
        0xFF18232B,
      ),
      'accentInk': (
        AppColors.light.accentInk,
        AppColors.dark.accentInk,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'accentBorder': (
        AppColors.light.accentBorder,
        AppColors.dark.accentBorder,
        0xFF88ADC2,
        0xFFB9D4E2,
      ),
      'slate': (
        AppColors.light.slate,
        AppColors.dark.slate,
        0xFF91B4C8,
        0xFFA3C5D7,
      ),
      'slateLight': (
        AppColors.light.slateLight,
        AppColors.dark.slateLight,
        0xFF91B4C8,
        0xFFA3C5D7,
      ),
      'slateDim': (
        AppColors.light.slateDim,
        AppColors.dark.slateDim,
        0xFFC3D7E4,
        0xFF304653,
      ),
      'slateGlow': (
        AppColors.light.slateGlow,
        AppColors.dark.slateGlow,
        0x3391B4C8,
        0x30A3C5D7,
      ),
      'accentPrimary': (
        AppColors.light.accentPrimary,
        AppColors.dark.accentPrimary,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'accentPrimaryStrong': (
        AppColors.light.accentPrimaryStrong,
        AppColors.dark.accentPrimaryStrong,
        0xFF91B4C8,
        0xFFA3C5D7,
      ),
      'green': (
        AppColors.light.green,
        AppColors.dark.green,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'greenLight': (
        AppColors.light.greenLight,
        AppColors.dark.greenLight,
        0xFFC3D7E4,
        0xFF304653,
      ),
      'greenDim': (
        AppColors.light.greenDim,
        AppColors.dark.greenDim,
        0xFFC3D7E4,
        0xFF304653,
      ),
      'greenGlow': (
        AppColors.light.greenGlow,
        AppColors.dark.greenGlow,
        0x3391B4C8,
        0x30A3C5D7,
      ),
      'violet': (
        AppColors.light.violet,
        AppColors.dark.violet,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'violetDim': (
        AppColors.light.violetDim,
        AppColors.dark.violetDim,
        0xFFDFE8E8,
        0xFF304653,
      ),
      'violetGlow': (
        AppColors.light.violetGlow,
        AppColors.dark.violetGlow,
        0x33286280,
        0x30B6D7EA,
      ),
      'statusSuccess': (
        AppColors.light.statusSuccess,
        AppColors.dark.statusSuccess,
        0xFF356246,
        0xFFA4CEB3,
      ),
      'statusSuccessDim': (
        AppColors.light.statusSuccessDim,
        AppColors.dark.statusSuccessDim,
        0xFFE5EAD6,
        0xFF283F35,
      ),
      'success': (
        AppColors.light.success,
        AppColors.dark.success,
        0xFF356246,
        0xFFA4CEB3,
      ),
      'successDim': (
        AppColors.light.successDim,
        AppColors.dark.successDim,
        0xFFE5EAD6,
        0xFF283F35,
      ),
      'warning': (
        AppColors.light.warning,
        AppColors.dark.warning,
        0xFF745322,
        0xFFE5C488,
      ),
      'warningDim': (
        AppColors.light.warningDim,
        AppColors.dark.warningDim,
        0xFFF0D18B,
        0xFF494035,
      ),
      'error': (
        AppColors.light.error,
        AppColors.dark.error,
        0xFFA7442D,
        0xFFEAA492,
      ),
      'errorDim': (
        AppColors.light.errorDim,
        AppColors.dark.errorDim,
        0xFFF3DAD0,
        0xFF4B3332,
      ),
      'modHome': (
        AppColors.light.modHome,
        AppColors.dark.modHome,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'modClients': (
        AppColors.light.modClients,
        AppColors.dark.modClients,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'modCalendar': (
        AppColors.light.modCalendar,
        AppColors.dark.modCalendar,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'modFinance': (
        AppColors.light.modFinance,
        AppColors.dark.modFinance,
        0xFF745322,
        0xFFE5C488,
      ),
      'modTasks': (
        AppColors.light.modTasks,
        AppColors.dark.modTasks,
        0xFFA7442D,
        0xFFEAA492,
      ),
      'modNotes': (
        AppColors.light.modNotes,
        AppColors.dark.modNotes,
        0xFF286280,
        0xFFB6D7EA,
      ),
      'modBg': (
        AppColors.light.modBg,
        AppColors.dark.modBg,
        0xFFEFE5CF,
        0xFF2B363F,
      ),
      'panelSoft': (
        AppColors.light.panelSoft,
        AppColors.dark.panelSoft,
        0xFFC3D7E4,
        0xFF304653,
      ),
      'panelSoftRaised': (
        AppColors.light.panelSoftRaised,
        AppColors.dark.panelSoftRaised,
        0xFFE5EAD6,
        0xFF283F35,
      ),
      'panelInk': (
        AppColors.light.panelInk,
        AppColors.dark.panelInk,
        0xFF443C32,
        0xFF18232B,
      ),
      'panelMuted': (
        AppColors.light.panelMuted,
        AppColors.dark.panelMuted,
        0xFF665949,
        0xFFCDD1CE,
      ),
      'panelFaint': (
        AppColors.light.panelFaint,
        AppColors.dark.panelFaint,
        0x3391B4C8,
        0x30A3C5D7,
      ),
    };
    for (final role in roles.entries) {
      expect(
        role.value.$1.toARGB32(),
        role.value.$3,
        reason: '${role.key} light',
      );
      expect(
        role.value.$2.toARGB32(),
        role.value.$4,
        reason: '${role.key} dark',
      );
    }
  });

  test('appearance palettes agree with the semantic theme roles', () {
    for (final (colors, tokens) in [
      (AppColors.light, WorkloopThemeTokens.light),
      (AppColors.dark, WorkloopThemeTokens.dark),
    ]) {
      expect(colors.bg, tokens.background);
      expect(colors.bgCard, tokens.surface);
      expect(colors.modBg, tokens.surfaceRaised);
      expect(colors.t1, tokens.textPrimary);
      expect(colors.t2, tokens.textSecondary);
      expect(colors.accentInk, tokens.accentInk);
      expect(colors.accentBorder, tokens.accentBorder);
      expect(colors.panelInk, colors.onBrandAccent);
    }
  });

  test('stored colours stay immutable when the other appearance is used', () {
    final lightCard = BoxDecoration(color: AppColors.light.bgCard);
    final lightInk = TextStyle(color: AppColors.light.t1);
    final darkCard = BoxDecoration(color: AppColors.dark.bgCard);
    final darkInk = TextStyle(color: AppColors.dark.t1);

    expect(lightCard, isNot(darkCard));
    expect(lightInk, isNot(darkInk));
    expect(lightCard.color?.toARGB32(), 0xFFFBF7ED);
    expect(lightInk.color?.toARGB32(), 0xFF443C32);
    expect(darkCard.color?.toARGB32(), 0xFF212A31);
    expect(darkInk.color?.toARGB32(), 0xFFF4F0E7);
  });

  test('semantic text roles meet contrast targets in both appearances', () {
    for (final tokens in [
      WorkloopThemeTokens.light,
      WorkloopThemeTokens.dark,
    ]) {
      for (final color in [
        tokens.textPrimary,
        tokens.textSecondary,
        tokens.accentInk,
      ]) {
        expect(
          _contrastRatio(color, tokens.background),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        _contrastRatio(tokens.textTertiary, tokens.background),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrastRatio(tokens.textDisabled, tokens.background),
        greaterThan(2),
      );
      expect(
        _contrastRatio(tokens.onAccent, tokens.accentStrong),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('feature surfaces stay readable in both appearances', () {
    for (final tokens in [
      WorkloopThemeTokens.light,
      WorkloopThemeTokens.dark,
    ]) {
      expect(
        _contrastRatio(tokens.onInk, tokens.inkSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.onInkMuted, tokens.inkSurface),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('focus indicators remain visible against paper surfaces', () {
    for (final entry in [
      (AppTheme.light, WorkloopThemeTokens.light),
      (AppTheme.dark, WorkloopThemeTokens.dark),
    ]) {
      final border =
          entry.$1.inputDecorationTheme.focusedBorder as OutlineInputBorder;
      expect(border.borderSide.color, entry.$2.accentInk);
      expect(
        _contrastRatio(border.borderSide.color, entry.$2.surface),
        greaterThanOrEqualTo(3),
      );
    }
  });

  test('primary actions use one readable ink-or-brand treatment', () {
    for (final entry in [
      (AppTheme.light, WorkloopThemeTokens.light),
      (AppTheme.dark, WorkloopThemeTokens.dark),
    ]) {
      expect(
        _contrastRatio(entry.$2.onPrimaryAction, entry.$2.primaryAction),
        greaterThanOrEqualTo(4.5),
      );
      final elevatedSide = entry.$1.elevatedButtonTheme.style?.side?.resolve(
        {},
      );
      final filledSide = entry.$1.filledButtonTheme.style?.side?.resolve({});
      expect(elevatedSide?.color, entry.$2.frame);
      expect(elevatedSide?.width, 1);
      expect(filledSide?.color, entry.$2.frame);
      expect(filledSide?.width, 1);
    }
  });

  test('module and semantic foregrounds stay legible in both appearances', () {
    for (final entry in [
      (AppColors.light, WorkloopThemeTokens.light),
      (AppColors.dark, WorkloopThemeTokens.dark),
    ]) {
      for (final color in [
        entry.$1.modHome,
        entry.$1.modClients,
        entry.$1.modCalendar,
        entry.$1.modFinance,
        entry.$1.modTasks,
        entry.$1.modNotes,
      ]) {
        expect(
          _contrastRatio(color, entry.$2.surface),
          greaterThanOrEqualTo(3),
        );
      }
      for (final color in [
        entry.$1.statusSuccess,
        entry.$1.warning,
        entry.$1.error,
      ]) {
        expect(
          _contrastRatio(color, entry.$2.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('legacy hero roles remain readable on flat paper', () {
    for (final tokens in [
      WorkloopThemeTokens.light,
      WorkloopThemeTokens.dark,
    ]) {
      for (final background in [
        tokens.heroGradientStart,
        tokens.heroGradientEnd,
      ]) {
        for (final foreground in [
          tokens.onHeroPrimary,
          tokens.onHeroSecondary,
          tokens.onHeroMuted,
        ]) {
          expect(
            _contrastRatio(
              Color.alphaBlend(foreground, background),
              background,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(
        _contrastRatio(tokens.heroActionForeground, tokens.heroControlSurface),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets(
    'shell clearance includes navigation, safe area, and breathing room',
    (tester) async {
      late double clearance;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 34),
              viewPadding: EdgeInsets.only(bottom: 34),
            ),
            child: Builder(
              builder: (context) {
                clearance = AppSpacing.shellBottomClearance(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(clearance, 52 + 34 + 18);
    },
  );

  test('interactive controls keep the Workloop typeface', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final styles = [
        theme.elevatedButtonTheme.style,
        theme.filledButtonTheme.style,
        theme.textButtonTheme.style,
        theme.outlinedButtonTheme.style,
      ];
      for (final style in styles) {
        expect(style?.textStyle?.resolve({})?.fontFamily, 'Manrope');
      }
    }
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
