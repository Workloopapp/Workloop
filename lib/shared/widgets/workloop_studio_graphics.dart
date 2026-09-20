import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'workloop_quiet_warm.dart';

const workloopAppIconAsset =
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';

/// The canonical app artwork, shared with the installed Workloop app.
///
/// This intentionally reads the existing iOS source artwork so Flutter and the
/// platform icon cannot silently drift into two different brand marks.
class WorkloopStudioAppIcon extends StatefulWidget {
  final double size;
  final double radius;

  const WorkloopStudioAppIcon({
    super.key,
    this.size = 72,
    this.radius = AppRadius.lg,
  });

  @override
  State<WorkloopStudioAppIcon> createState() => _WorkloopStudioAppIconState();
}

class _WorkloopStudioAppIconState extends State<WorkloopStudioAppIcon> {
  Future<void>? _ready;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ready ??= precacheImage(const AssetImage(workloopAppIconAsset), context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<WorkloopThemeTokens>() ??
        (theme.brightness == Brightness.dark
            ? WorkloopThemeTokens.dark
            : WorkloopThemeTokens.light);
    return Semantics(
      image: true,
      label: 'Workloop',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: SizedBox.square(
            dimension: widget.size,
            child: FutureBuilder<void>(
              future: _ready,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return ColoredBox(
                    color: tokens.paperBlue,
                    child: Center(
                      child: Text(
                        'W',
                        style: TextStyle(
                          color: tokens.onAccent,
                          fontSize: widget.size * 0.52,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          height: 1,
                        ),
                      ),
                    ),
                  );
                }
                return Image.asset(
                  workloopAppIconAsset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Compatibility wrapper for the original workflow illustration API.
/// A paper folder replaces the retired abstract Studio loop artwork.
class WorkloopStudioLoopMark extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? secondaryColor;
  final bool animate;
  const WorkloopStudioLoopMark({
    super.key,
    this.size = 112,
    this.color,
    this.secondaryColor,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) => WorkloopIllustration(
    kind: WorkloopIllustrationKind.folder,
    size: size,
    color: color,
    semanticLabel: 'Your business in one place',
  );
}

class WorkloopStudioProgressArc extends StatelessWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final Color color;
  final Widget? child;

  const WorkloopStudioProgressArc({
    super.key,
    required this.progress,
    required this.color,
    this.size = 84,
    this.strokeWidth = 8,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<WorkloopThemeTokens>() ??
        (theme.brightness == Brightness.dark
            ? WorkloopThemeTokens.dark
            : WorkloopThemeTokens.light);
    final value = progress.clamp(0.0, 1.0);
    return Semantics(
      label: '${(value * 100).round()} percent complete',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: AppMotion.responsive(context, AppMotion.deliberate),
              curve: AppMotion.curve,
              builder: (context, animatedValue, _) => CustomPaint(
                size: Size.square(size),
                painter: _ProgressArcPainter(
                  progress: animatedValue,
                  track: tokens.divider,
                  color: color,
                  strokeWidth: strokeWidth,
                ),
              ),
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}

class WorkloopStudioModuleIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const WorkloopStudioModuleIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final kind = WorkloopIllustration.forIcon(icon);
    if (kind != null) return WorkloopIllustration(kind: kind, size: size);
    final tokens =
        Theme.of(context).extension<WorkloopThemeTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? WorkloopThemeTokens.dark
            : WorkloopThemeTokens.light);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.frame),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: tokens.textPrimary, size: size * 0.46),
    );
  }
}

class WorkloopStudioBarDatum {
  final String label;
  final double value;
  final String? valueLabel;

  const WorkloopStudioBarDatum({
    required this.label,
    required this.value,
    this.valueLabel,
  });
}

/// A compact, native Flutter data strip for small sets of comparable values.
/// It intentionally avoids axes and chart furniture so the data remains useful
/// without making Workloop feel like an analytics dashboard.
class WorkloopStudioBarChart extends StatelessWidget {
  final List<WorkloopStudioBarDatum> data;
  final Color color;
  final String semanticsLabel;
  final double height;
  final bool showValues;

  const WorkloopStudioBarChart({
    super.key,
    required this.data,
    required this.color,
    required this.semanticsLabel,
    this.height = 92,
    this.showValues = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<WorkloopThemeTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? WorkloopThemeTokens.dark
            : WorkloopThemeTokens.light);
    final maxValue = data.fold<double>(
      0,
      (largest, item) => math.max(largest, item.value),
    );

    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final item in data)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (showValues)
                                Text(
                                  item.valueLabel ??
                                      item.value.toStringAsFixed(0),
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(
                                      begin: 0,
                                      end: maxValue <= 0
                                          ? 0
                                          : item.value / maxValue,
                                    ),
                                    duration: AppMotion.responsive(
                                      context,
                                      AppMotion.deliberate,
                                    ),
                                    curve: AppMotion.emphasized,
                                    builder: (context, progress, _) =>
                                        FractionallySizedBox(
                                          heightFactor: math.max(
                                            0.07,
                                            progress,
                                          ),
                                          child: Container(
                                            width: 22,
                                            decoration: BoxDecoration(
                                              color: item.value <= 0
                                                  ? tokens.divider
                                                  : color.withValues(
                                                      alpha: 0.9,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadius.xs,
                                                  ),
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final item in data)
                    Expanded(
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          color: tokens.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressArcPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color color;
  final double strokeWidth;

  const _ProgressArcPainter({
    required this.progress,
    required this.track,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = strokeWidth / 2;
    final arc = rect.deflate(inset);
    const start = math.pi * 0.72;
    const sweep = math.pi * 1.56;
    canvas.drawArc(
      arc,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = track,
    );
    canvas.drawArc(
      arc,
      start,
      sweep * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
