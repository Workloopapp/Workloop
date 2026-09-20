import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Compatibility names for older screens, resolved from their local theme.
/// Each getter returns an immutable Color so Flutter can compare old and new
/// decorations correctly. New UI should prefer semantic WorkloopThemeTokens.
@immutable
class AppColors {
  final Brightness _brightness;
  const AppColors._(this._brightness);

  static const light = AppColors._(Brightness.light);
  static const dark = AppColors._(Brightness.dark);

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color _resolve(Color light, Color dark) =>
      _brightness == Brightness.dark ? dark : light;

  Color get bg => _resolve(const Color(0xFFF5EDD9), const Color(0xFF171D22));
  Color get bgCard =>
      _resolve(const Color(0xFFFBF7ED), const Color(0xFF212A31));
  Color get bgRaised =>
      _resolve(const Color(0xFFEFE5CF), const Color(0xFF2B363F));
  Color get bgInteract =>
      _resolve(const Color(0xFFE9DFCA), const Color(0xFF33404A));
  Color get border =>
      _resolve(const Color(0xFFB5A997), const Color(0xFF455660));
  Color get borderStrong =>
      _resolve(const Color(0xFF80715E), const Color(0xFF667984));
  Color get t1 => _resolve(const Color(0xFF443C32), const Color(0xFFF4F0E7));
  Color get t2 => _resolve(const Color(0xFF665949), const Color(0xFFCDD1CE));
  Color get t3 => _resolve(const Color(0xFF706658), const Color(0xFFA8B5B9));
  Color get t4 => _resolve(const Color(0xFF928674), const Color(0xFF87979F));
  Color get brandAccent =>
      _resolve(const Color(0xFF91B4C8), const Color(0xFFA3C5D7));
  Color get onBrandAccent =>
      _resolve(const Color(0xFF443C32), const Color(0xFF18232B));
  Color get accentInk =>
      _resolve(const Color(0xFF286280), const Color(0xFFB6D7EA));
  Color get accentBorder =>
      _resolve(const Color(0xFF88ADC2), const Color(0xFFB9D4E2));
  Color get slate => brandAccent;
  Color get slateLight => brandAccent;
  Color get slateDim =>
      _resolve(const Color(0xFFC3D7E4), const Color(0xFF304653));
  Color get slateGlow =>
      _resolve(const Color(0x3391B4C8), const Color(0x30A3C5D7));
  Color get accentPrimary => accentInk;
  Color get accentPrimaryStrong => brandAccent;
  Color get green => accentInk;
  Color get greenLight => slateDim;
  Color get greenDim => slateDim;
  Color get greenGlow => slateGlow;
  Color get violet =>
      _resolve(const Color(0xFF286280), const Color(0xFFB6D7EA));
  Color get violetDim =>
      _resolve(const Color(0xFFDFE8E8), const Color(0xFF304653));
  Color get violetGlow =>
      _resolve(const Color(0x33286280), const Color(0x30B6D7EA));
  Color get statusSuccess =>
      _resolve(const Color(0xFF356246), const Color(0xFFA4CEB3));
  Color get statusSuccessDim =>
      _resolve(const Color(0xFFE5EAD6), const Color(0xFF283F35));
  Color get success => statusSuccess;
  Color get successDim => statusSuccessDim;
  Color get warning =>
      _resolve(const Color(0xFF745322), const Color(0xFFE5C488));
  Color get warningDim =>
      _resolve(const Color(0xFFF0D18B), const Color(0xFF494035));
  Color get error => _resolve(const Color(0xFFA7442D), const Color(0xFFEAA492));
  Color get errorDim =>
      _resolve(const Color(0xFFF3DAD0), const Color(0xFF4B3332));
  Color get modHome => accentInk;
  Color get modClients =>
      _resolve(const Color(0xFF286280), const Color(0xFFB6D7EA));
  Color get modCalendar => violet;
  Color get modFinance =>
      _resolve(const Color(0xFF745322), const Color(0xFFE5C488));
  Color get modTasks =>
      _resolve(const Color(0xFFA7442D), const Color(0xFFEAA492));
  Color get modNotes =>
      _resolve(const Color(0xFF286280), const Color(0xFFB6D7EA));
  Color get modBg => _resolve(const Color(0xFFEFE5CF), const Color(0xFF2B363F));
  Color get panelSoft =>
      _resolve(const Color(0xFFC3D7E4), const Color(0xFF304653));
  Color get panelSoftRaised =>
      _resolve(const Color(0xFFE5EAD6), const Color(0xFF283F35));
  Color get panelInk => onBrandAccent;
  Color get panelMuted =>
      _resolve(const Color(0xFF665949), const Color(0xFFCDD1CE));
  Color get panelFaint =>
      _resolve(const Color(0x3391B4C8), const Color(0x30A3C5D7));
}

@immutable
class WorkloopThemeTokens extends ThemeExtension<WorkloopThemeTokens> {
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSubtle;
  final Color divider;
  final Color dividerStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color accent;
  final Color accentStrong;
  final Color accentInk;
  final Color accentBorder;
  final Color onAccent;
  final Color primaryAction;
  final Color onPrimaryAction;
  final Color inkSurface;
  final Color onInk;
  final Color onInkMuted;
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color error;
  final Color errorContainer;
  final Color info;
  final Color infoContainer;
  final Color scrim;
  final Color skeletonBase;
  final Color skeletonHighlight;

  // Compatibility hero roles now describe a flat paper panel, never a gradient.
  bool get _isDarkContract => background.computeLuminance() < 0.1;
  Color get paperBlue =>
      _isDarkContract ? const Color(0xFF304653) : const Color(0xFFC3D7E4);
  Color get paperYellow =>
      _isDarkContract ? const Color(0xFF494035) : const Color(0xFFF0D18B);
  Color get onPaperStrip => textPrimary;
  Color get illustrationAccent =>
      _isDarkContract ? const Color(0xFFEAA492) : const Color(0xFFD57958);
  Color get headerField =>
      _isDarkContract ? const Color(0xFF273842) : const Color(0xFFC3D7E4);
  Color get frame => dividerStrong;
  // Required neutral ink for third-party map attribution.
  Color get providerAttributionInk =>
      surface.computeLuminance() < .5 ? Colors.white : const Color(0xFF5E5E5E);
  Color get heroGradientStart => surface;
  Color get heroGradientEnd => surface;
  Color get onHeroPrimary => textPrimary;
  Color get heroActionForeground => onPrimaryAction;
  Color get onHeroSecondary => textSecondary;
  Color get onHeroMuted => textSecondary;
  Color get heroBorder => frame;
  Color get heroSurface => paperBlue;
  Color get heroControlSurface => primaryAction;

  const WorkloopThemeTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSubtle,
    required this.divider,
    required this.dividerStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentStrong,
    required this.accentInk,
    required this.accentBorder,
    required this.onAccent,
    required this.primaryAction,
    required this.onPrimaryAction,
    required this.inkSurface,
    required this.onInk,
    required this.onInkMuted,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.error,
    required this.errorContainer,
    required this.info,
    required this.infoContainer,
    required this.scrim,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  static const light = WorkloopThemeTokens(
    background: Color(0xFFF5EDD9),
    surface: Color(0xFFFBF7ED),
    surfaceRaised: Color(0xFFEFE5CF),
    surfaceSubtle: Color(0xFFE9DFCA),
    divider: Color(0xFFB5A997),
    dividerStrong: Color(0xFF80715E),
    textPrimary: Color(0xFF443C32),
    textSecondary: Color(0xFF665949),
    textTertiary: Color(0xFF706658),
    textDisabled: Color(0xFF928674),
    accent: Color(0xFF91B4C8),
    accentStrong: Color(0xFF88ADC2),
    accentInk: Color(0xFF286280),
    accentBorder: Color(0xFF88ADC2),
    onAccent: Color(0xFF443C32),
    primaryAction: Color(0xFF91B4C8),
    onPrimaryAction: Color(0xFF443C32),
    inkSurface: Color(0xFFC3D7E4),
    onInk: Color(0xFF443C32),
    onInkMuted: Color(0xFF665949),
    success: Color(0xFF356246),
    successContainer: Color(0xFFE5EAD6),
    warning: Color(0xFF745322),
    warningContainer: Color(0xFFF0D18B),
    error: Color(0xFFA7442D),
    errorContainer: Color(0xFFF3DAD0),
    info: Color(0xFF286280),
    infoContainer: Color(0xFFDCE8EB),
    scrim: Color(0x52000000),
    skeletonBase: Color(0xFFDFD5C1),
    skeletonHighlight: Color(0xFFFBF7ED),
  );

  static const dark = WorkloopThemeTokens(
    background: Color(0xFF171D22),
    surface: Color(0xFF212A31),
    surfaceRaised: Color(0xFF2B363F),
    surfaceSubtle: Color(0xFF33404A),
    divider: Color(0xFF455660),
    dividerStrong: Color(0xFF667984),
    textPrimary: Color(0xFFF4F0E7),
    textSecondary: Color(0xFFCDD1CE),
    textTertiary: Color(0xFFA8B5B9),
    textDisabled: Color(0xFF87979F),
    accent: Color(0xFFA3C5D7),
    accentStrong: Color(0xFFB9D4E2),
    accentInk: Color(0xFFB6D7EA),
    accentBorder: Color(0xFFB9D4E2),
    onAccent: Color(0xFF18232B),
    primaryAction: Color(0xFFA3C5D7),
    onPrimaryAction: Color(0xFF18232B),
    inkSurface: Color(0xFF304653),
    onInk: Color(0xFFF4F0E7),
    onInkMuted: Color(0xFFCDD1CE),
    success: Color(0xFFA4CEB3),
    successContainer: Color(0xFF283F35),
    warning: Color(0xFFE5C488),
    warningContainer: Color(0xFF494035),
    error: Color(0xFFEAA492),
    errorContainer: Color(0xFF4B3332),
    info: Color(0xFFB6D7EA),
    infoContainer: Color(0xFF304653),
    scrim: Color(0xA6000000),
    skeletonBase: Color(0xFF33404A),
    skeletonHighlight: Color(0xFF45535E),
  );

  @override
  WorkloopThemeTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSubtle,
    Color? divider,
    Color? dividerStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? accent,
    Color? accentStrong,
    Color? accentInk,
    Color? accentBorder,
    Color? onAccent,
    Color? primaryAction,
    Color? onPrimaryAction,
    Color? inkSurface,
    Color? onInk,
    Color? onInkMuted,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? error,
    Color? errorContainer,
    Color? info,
    Color? infoContainer,
    Color? scrim,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return WorkloopThemeTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      divider: divider ?? this.divider,
      dividerStrong: dividerStrong ?? this.dividerStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentInk: accentInk ?? this.accentInk,
      accentBorder: accentBorder ?? this.accentBorder,
      onAccent: onAccent ?? this.onAccent,
      primaryAction: primaryAction ?? this.primaryAction,
      onPrimaryAction: onPrimaryAction ?? this.onPrimaryAction,
      inkSurface: inkSurface ?? this.inkSurface,
      onInk: onInk ?? this.onInk,
      onInkMuted: onInkMuted ?? this.onInkMuted,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      scrim: scrim ?? this.scrim,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  WorkloopThemeTokens lerp(
    ThemeExtension<WorkloopThemeTokens>? other,
    double t,
  ) {
    if (other is! WorkloopThemeTokens) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return WorkloopThemeTokens(
      background: blend(background, other.background),
      surface: blend(surface, other.surface),
      surfaceRaised: blend(surfaceRaised, other.surfaceRaised),
      surfaceSubtle: blend(surfaceSubtle, other.surfaceSubtle),
      divider: blend(divider, other.divider),
      dividerStrong: blend(dividerStrong, other.dividerStrong),
      textPrimary: blend(textPrimary, other.textPrimary),
      textSecondary: blend(textSecondary, other.textSecondary),
      textTertiary: blend(textTertiary, other.textTertiary),
      textDisabled: blend(textDisabled, other.textDisabled),
      accent: blend(accent, other.accent),
      accentStrong: blend(accentStrong, other.accentStrong),
      accentInk: blend(accentInk, other.accentInk),
      accentBorder: blend(accentBorder, other.accentBorder),
      onAccent: blend(onAccent, other.onAccent),
      primaryAction: blend(primaryAction, other.primaryAction),
      onPrimaryAction: blend(onPrimaryAction, other.onPrimaryAction),
      inkSurface: blend(inkSurface, other.inkSurface),
      onInk: blend(onInk, other.onInk),
      onInkMuted: blend(onInkMuted, other.onInkMuted),
      success: blend(success, other.success),
      successContainer: blend(successContainer, other.successContainer),
      warning: blend(warning, other.warning),
      warningContainer: blend(warningContainer, other.warningContainer),
      error: blend(error, other.error),
      errorContainer: blend(errorContainer, other.errorContainer),
      info: blend(info, other.info),
      infoContainer: blend(infoContainer, other.infoContainer),
      scrim: blend(scrim, other.scrim),
      skeletonBase: blend(skeletonBase, other.skeletonBase),
      skeletonHighlight: blend(skeletonHighlight, other.skeletonHighlight),
    );
  }
}

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double pageX = 18;
  static const double section = 24;

  /// Canonical content inset below the platform safe area.
  static const double screenTop = 8;
  static const double minTouch = 44;

  /// Shared full-width navigation geometry. Shell screens calculate their final
  /// content inset from these values and the real device safe area.
  static const double bottomNavHeight = 52;
  static const double bottomNavOffset = 0;
  static const double bottomNavBreathingRoom = 18;

  static double bottomNavHeightFor(BuildContext context) =>
      bottomNavHeight +
      (MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3).scale(11) -
                  11)
              .clamp(0.0, 33.0) *
          2.3;

  static double shellBottomClearance(BuildContext context) {
    // An extending Scaffold injects the whole bar into padding.bottom and
    // removes its occupied viewPadding. Outside it, viewPadding is the physical
    // inset. Take the greater occupied area rather than counting the bar twice.
    return math.max(
          bottomNavHeightFor(context) +
              bottomNavOffset +
              MediaQuery.viewPaddingOf(context).bottom,
          MediaQuery.paddingOf(context).bottom,
        ) +
        bottomNavBreathingRoom;
  }
}

class AppRadius {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 10;
  static const double sheet = 12;

  /// Reserved for circular progress and avatar geometry, never navigation.
  static const double capsule = 999;
}

class AppMotion {
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const deliberate = Duration(milliseconds: 360);
  static const celebration = Duration(milliseconds: 440);
  static const navigation = Duration(milliseconds: 220);
  static const double navigationOffset = 0.04;
  static const double destinationOffset = 14;
  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutCubic;
  static const double pressedScale = 0.98;

  static Duration responsive(BuildContext context, Duration duration) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : duration;
  }
}

class AppShadows {
  // Paper panels and navigation have no ambient elevation. Tactile offset
  // shadows are reserved for explicit primary controls.
  static List<BoxShadow> get soft => const [];
  static List<BoxShadow> get glass => const [];
  static List<BoxShadow> get dock => const [];
  static List<BoxShadow> tactile(Color ink) => [
    BoxShadow(color: ink.withValues(alpha: 0.6), offset: const Offset(1, 2)),
  ];
}

class AppTheme {
  static ThemeData get light =>
      _build(tokens: WorkloopThemeTokens.light, brightness: Brightness.light);

  static ThemeData get dark =>
      _build(tokens: WorkloopThemeTokens.dark, brightness: Brightness.dark);

  static ThemeData _build({
    required WorkloopThemeTokens tokens,
    required Brightness brightness,
  }) {
    final colorScheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: tokens.accentInk,
            onPrimary: tokens.surface,
            secondary: tokens.accent,
            onSecondary: tokens.onAccent,
            surface: tokens.surface,
            onSurface: tokens.textPrimary,
            error: tokens.error,
          )
        : ColorScheme.light(
            primary: tokens.accentInk,
            onPrimary: tokens.surface,
            secondary: tokens.accentInk,
            onSecondary: tokens.surface,
            surface: tokens.surface,
            onSurface: tokens.textPrimary,
            error: tokens.error,
          );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      brightness: brightness,
      extensions: [tokens],
      // Pages must cover outgoing routes, including keyboard/native transitions.
      // Local paper backdrops add the shared header tint on this opaque base.
      scaffoldBackgroundColor: tokens.background,
      canvasColor: tokens.background,
      cardColor: tokens.surface,
      focusColor: tokens.accent.withValues(alpha: 0.24),
      highlightColor: tokens.accent.withValues(alpha: 0.12),
      splashColor: tokens.accent.withValues(alpha: 0.14),
      disabledColor: tokens.textDisabled,
      iconTheme: IconThemeData(color: tokens.textSecondary, size: 20),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SlatePageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.accentInk,
        selectionColor: tokens.accent.withValues(alpha: 0.42),
        selectionHandleColor: tokens.accentInk,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 40 / 34,
          color: tokens.textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.65,
          height: 34 / 30,
          color: tokens.textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.45,
          height: 32 / 26,
          color: tokens.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          height: 24 / 19,
          color: tokens.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 21 / 16,
          color: tokens.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 18 / 14,
          color: tokens.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 22 / 15,
          color: tokens.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 19 / 13,
          color: tokens.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 18 / 14,
          color: tokens.textPrimary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 14 / 11,
          color: tokens.textTertiary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface,
        hintStyle: TextStyle(color: tokens.textTertiary),
        labelStyle: TextStyle(color: tokens.textSecondary),
        floatingLabelStyle: TextStyle(
          color: tokens.accentInk,
          fontWeight: FontWeight.w600,
        ),
        errorStyle: TextStyle(color: tokens.error),
        prefixIconColor: tokens.textSecondary,
        suffixIconColor: tokens.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.frame),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.frame),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.accentInk, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.frame),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primaryAction,
          foregroundColor: tokens.onPrimaryAction,
          minimumSize: const Size(44, 52),
          elevation: 0,
          shadowColor: tokens.accent.withValues(alpha: 0.2),
          side: BorderSide(color: tokens.frame, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primaryAction,
          foregroundColor: tokens.onPrimaryAction,
          minimumSize: const Size(44, 52),
          side: BorderSide(color: tokens.frame, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          minimumSize: const Size(44, 50),
          side: BorderSide(color: tokens.dividerStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.primaryAction,
        foregroundColor: tokens.onPrimaryAction,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: tokens.frame, width: 1),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accentStrong
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(tokens.onAccent),
        side: BorderSide(color: tokens.dividerStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs / 2),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accentInk
              : tokens.textTertiary,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accentInk,
        linearTrackColor: tokens.surfaceSubtle,
        circularTrackColor: tokens.surfaceSubtle,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        modalBackgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: tokens.dividerStrong,
        dragHandleSize: const Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          side: BorderSide(color: tokens.frame, width: AppStroke.frame),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: tokens.divider),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.textPrimary,
        contentTextStyle: TextStyle(
          color: tokens.background,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.onAccent
              : tokens.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.dividerStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerColor: tokens.divider,
      dividerTheme: DividerThemeData(
        color: tokens.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

class _SlatePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SlatePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: Curves.easeInCubic,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.curve,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.015, 0),
      ).animate(outgoing),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(AppMotion.navigationOffset, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Consistent visible frame weight, including rounded corners and title strips.
abstract final class AppStroke {
  static const double frame = 1.5;
}
