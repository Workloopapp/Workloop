import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';

WorkloopThemeTokens _paperTokens(BuildContext context) =>
    Theme.of(context).extension<WorkloopThemeTokens>() ??
    (Theme.of(context).brightness == Brightness.dark
        ? WorkloopThemeTokens.dark
        : WorkloopThemeTokens.light);

/// Small original drawings for orientation. Clocks can display a supplied time.
enum WorkloopIllustrationKind {
  calendar,
  clock,
  folder,
  receipt,
  tools,
  storefront,
  clients,
  sun,
  note,
}

enum WorkloopPaperTone { blue, warm, plain }

class WorkloopWordmark extends StatelessWidget {
  final double size;
  const WorkloopWordmark({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) => Text(
    'workloop',
    semanticsLabel: 'Workloop',
    style: TextStyle(
      fontFamily: 'Manrope',
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.7,
      color: _paperTokens(context).textPrimary,
    ),
  );
}

class WorkloopCaption extends StatelessWidget {
  final String text;
  final Color? color;
  const WorkloopCaption(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontFamily: 'WorkloopMono',
      fontFamilyFallback: const ['Manrope'],
      fontSize: 11,
      height: 1.4,
      letterSpacing: 0.7,
      fontWeight: FontWeight.w500,
      color: color ?? _paperTokens(context).textPrimary,
    ),
  );
}

/// A single paper frame with an optional narrow coloured title strip.
/// Content can contain ruled rows directly by passing EdgeInsets.zero.
class WorkloopPaperPanel extends StatelessWidget {
  final String? title;
  final WorkloopPaperTone tone;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const WorkloopPaperPanel({
    super.key,
    this.title,
    this.tone = WorkloopPaperTone.blue,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = _paperTokens(context);
    final fill = switch (tone) {
      WorkloopPaperTone.blue => tokens.paperBlue,
      WorkloopPaperTone.warm => tokens.paperYellow,
      WorkloopPaperTone.plain => tokens.surface,
    };
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: tokens.frame, width: AppStroke.frame),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: fill,
                border: Border(
                  bottom: BorderSide(
                    color: tokens.frame,
                    width: AppStroke.frame,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: WorkloopCaption(title!, color: tokens.onPaperStrip),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

class WorkloopIllustration extends StatelessWidget {
  final WorkloopIllustrationKind kind;
  final double size;
  final Color? color;
  final String? semanticLabel;

  /// Booking time in the same time zone as its adjacent text. Other clocks
  /// remain decorative; no wall-clock timer or extra network read is needed.
  final TimeOfDay? clockTime;

  const WorkloopIllustration({
    super.key,
    required this.kind,
    this.size = 48,
    this.color,
    this.semanticLabel,
    this.clockTime,
  }) : assert(clockTime == null || kind == WorkloopIllustrationKind.clock);

  /// Bridge existing functional IconData APIs into the illustrated language.
  static WorkloopIllustrationKind? forIcon(IconData icon) {
    if ([
      LucideIcons.calendar,
      LucideIcons.calendarDays,
      LucideIcons.calendarCheck,
      LucideIcons.calendarClock,
    ].contains(icon)) {
      return WorkloopIllustrationKind.calendar;
    }
    if ([
      LucideIcons.users,
      LucideIcons.user,
      LucideIcons.contact,
    ].contains(icon)) {
      return WorkloopIllustrationKind.clients;
    }
    if ([
      LucideIcons.wallet,
      LucideIcons.receipt,
      LucideIcons.banknote,
      LucideIcons.poundSterling,
      LucideIcons.creditCard,
    ].contains(icon)) {
      return WorkloopIllustrationKind.receipt;
    }
    if ([
      LucideIcons.briefcase,
      LucideIcons.wrench,
      LucideIcons.hammer,
      LucideIcons.checkSquare,
    ].contains(icon)) {
      return WorkloopIllustrationKind.tools;
    }
    if ([LucideIcons.store, LucideIcons.building2].contains(icon)) {
      return WorkloopIllustrationKind.storefront;
    }
    if ([LucideIcons.folder, LucideIcons.folderOpen].contains(icon)) {
      return WorkloopIllustrationKind.folder;
    }
    if ([LucideIcons.clock, LucideIcons.timer].contains(icon)) {
      return WorkloopIllustrationKind.clock;
    }
    if ([
      LucideIcons.fileText,
      LucideIcons.notebookPen,
      LucideIcons.stickyNote,
    ].contains(icon)) {
      return WorkloopIllustrationKind.note;
    }
    if (icon == LucideIcons.sun) return WorkloopIllustrationKind.sun;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _paperTokens(context);
    final drawing = CustomPaint(
      size: Size.square(size),
      painter: _PaperIllustrationPainter(
        kind: kind,
        ink: color ?? tokens.textPrimary,
        paper: tokens.surface,
        blue: tokens.paperBlue,
        yellow: tokens.paperYellow,
        coral: tokens.illustrationAccent,
        clockTime: clockTime,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: drawing);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: drawing),
    );
  }
}

class _PaperIllustrationPainter extends CustomPainter {
  final WorkloopIllustrationKind kind;
  final Color ink, paper, blue, yellow, coral;
  final TimeOfDay? clockTime;
  const _PaperIllustrationPainter({
    required this.kind,
    required this.ink,
    required this.paper,
    required this.blue,
    required this.yellow,
    required this.coral,
    this.clockTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double x2, double y2, {Color? color}) =>
        canvas.drawLine(
          Offset(x, y),
          Offset(x2, y2),
          Paint()
            ..color = color ?? ink
            ..strokeWidth = 1.1
            ..strokeCap = StrokeCap.round,
        );
    void shape(Path path, Color fill) {
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(path, pen);
    }

    void box(
      double x,
      double y,
      double w,
      double h,
      Color fill, [
      double r = 2,
    ]) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(r),
      );
      canvas.drawRRect(rect, Paint()..color = fill);
      canvas.drawRRect(rect, pen);
    }

    void circle(double x, double y, double r, Color fill) {
      canvas.drawCircle(Offset(x, y), r, Paint()..color = fill);
      canvas.drawCircle(Offset(x, y), r, pen);
    }

    switch (kind) {
      case WorkloopIllustrationKind.calendar:
        box(8, 9, 32, 33, paper);
        box(8, 9, 32, 9, blue);
        for (final x in [15.0, 33.0]) {
          box(x - 1, 5, 2, 9, paper, 1);
        }
        for (var y = 23.0; y <= 35; y += 6) {
          for (var x = 14.0; x <= 32; x += 9) {
            if (x == 23 && y == 29) {
              box(x - 1, y - 1, 4, 4, yellow, 0.5);
            } else {
              line(x, y, x + 2, y);
              line(x, y, x, y + 2);
            }
          }
        }
      case WorkloopIllustrationKind.clock:
        circle(24, 24, 20, blue);
        circle(24, 24, 17, paper);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          line(
            24 + math.sin(a) * 14,
            24 - math.cos(a) * 14,
            24 + math.sin(a) * 15.5,
            24 - math.cos(a) * 15.5,
          );
        }
        if (clockTime case final time?) {
          final hourAngle = (time.hour % 12 + time.minute / 60) * math.pi / 6;
          final minuteAngle = time.minute * math.pi / 30;
          line(
            24,
            24,
            24 + math.sin(hourAngle) * 9.5,
            24 - math.cos(hourAngle) * 9.5,
          );
          line(
            24,
            24,
            24 + math.sin(minuteAngle) * 12.5,
            24 - math.cos(minuteAngle) * 12.5,
          );
        } else {
          line(24, 24, 15, 18);
          line(24, 24, 24, 35);
        }
        circle(24, 24, 1.5, coral);
      case WorkloopIllustrationKind.folder:
        shape(
          Path()
            ..moveTo(5, 14)
            ..lineTo(5, 8)
            ..lineTo(19, 8)
            ..lineTo(23, 13)
            ..lineTo(41, 13)
            ..lineTo(41, 39)
            ..lineTo(5, 39)
            ..close(),
          yellow,
        );
        box(10, 15, 32, 24, paper, 1);
        shape(
          Path()
            ..moveTo(6, 20)
            ..lineTo(43, 20)
            ..lineTo(39, 41)
            ..lineTo(6, 41)
            ..close(),
          yellow,
        );
        line(10, 24, 16, 24, color: paper);
      case WorkloopIllustrationKind.receipt:
        shape(
          Path()
            ..moveTo(13, 5)
            ..lineTo(36, 5)
            ..lineTo(36, 42)
            ..lineTo(32, 39)
            ..lineTo(28, 42)
            ..lineTo(24, 39)
            ..lineTo(20, 42)
            ..lineTo(16, 39)
            ..lineTo(12, 42)
            ..lineTo(12, 8)
            ..quadraticBezierTo(12, 5, 13, 5)
            ..close(),
          paper,
        );
        shape(
          Path()
            ..moveTo(36, 5)
            ..quadraticBezierTo(40, 5, 40, 11)
            ..lineTo(36, 11)
            ..close(),
          coral,
        );
        final text = TextPainter(
          text: TextSpan(
            text: '£',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              height: 1,
              color: coral,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, const Offset(17, 10));
        line(17, 27, 30, 27);
        line(17, 31, 30, 31);
        line(17, 35, 24, 35);
      case WorkloopIllustrationKind.tools:
        canvas.save();
        canvas.translate(24, 24);
        canvas.rotate(-math.pi / 4);
        shape(
          Path()
            ..moveTo(-3, 18)
            ..lineTo(-3, -6)
            ..cubicTo(-12, -9, -9, -19, -5, -19)
            ..lineTo(-5, -13)
            ..lineTo(5, -13)
            ..lineTo(5, -19)
            ..cubicTo(9, -18, 12, -9, 3, -6)
            ..lineTo(3, 18)
            ..close(),
          paper,
        );
        circle(0, 14, 1.3, blue);
        canvas.restore();
        canvas.save();
        canvas.translate(24, 24);
        canvas.rotate(math.pi / 4);
        shape(
          Path()
            ..moveTo(-2, -19)
            ..lineTo(2, -19)
            ..lineTo(3, -12)
            ..lineTo(1, -9)
            ..lineTo(1, 3)
            ..lineTo(-1, 3)
            ..lineTo(-1, -9)
            ..lineTo(-3, -12)
            ..close(),
          paper,
        );
        box(-4, 3, 8, 16, blue, 2);
        line(0, 6, 0, 16);
        canvas.restore();
      case WorkloopIllustrationKind.storefront:
        box(8, 20, 32, 22, paper, 1);
        shape(
          Path()
            ..moveTo(9, 7)
            ..lineTo(39, 7)
            ..lineTo(44, 20)
            ..lineTo(4, 20)
            ..close(),
          paper,
        );
        for (var i = 0; i < 4; i++) {
          final x = 4 + i * 10.0;
          shape(
            Path()
              ..moveTo(x, 20)
              ..lineTo(x + 10, 20)
              ..lineTo(x + 10, 23)
              ..quadraticBezierTo(x + 5, 29, x, 23)
              ..close(),
            i.isEven ? blue : paper,
          );
          if (i > 0) line(9 + i * 7.5, 7, x, 20);
        }
        box(21, 29, 10, 13, paper, 1);
        line(28, 35, 28, 37);
        box(11, 29, 7, 7, yellow, 0.5);
      case WorkloopIllustrationKind.clients:
        circle(19, 14, 7, paper);
        circle(33, 16, 5.5, paper);
        shape(
          Path()
            ..moveTo(28, 26)
            ..quadraticBezierTo(39, 24, 42, 36)
            ..lineTo(42, 39)
            ..lineTo(29, 39)
            ..close(),
          blue,
        );
        shape(
          Path()
            ..moveTo(5, 40)
            ..lineTo(5, 35)
            ..cubicTo(5, 22, 32, 22, 32, 35)
            ..lineTo(32, 40)
            ..close(),
          paper,
        );
        line(12, 34, 12, 40);
        line(26, 34, 26, 40);
      case WorkloopIllustrationKind.sun:
        circle(24, 24, 10, yellow);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(
            24 + math.sin(a) * 14,
            24 + math.cos(a) * 14,
            24 + math.sin(a) * 19,
            24 + math.cos(a) * 19,
          );
        }
        circle(21, 23, 0.4, ink);
        circle(27, 23, 0.4, ink);
        canvas.drawArc(
          const Rect.fromLTWH(20, 23, 8, 6),
          0.25,
          math.pi - 0.5,
          false,
          pen,
        );
      case WorkloopIllustrationKind.note:
        shape(
          Path()
            ..moveTo(10, 6)
            ..lineTo(31, 6)
            ..lineTo(39, 14)
            ..lineTo(39, 42)
            ..lineTo(10, 42)
            ..close(),
          paper,
        );
        shape(
          Path()
            ..moveTo(31, 6)
            ..lineTo(31, 14)
            ..lineTo(39, 14)
            ..close(),
          blue,
        );
        for (final y in [22.0, 27.0, 32.0]) {
          line(16, y, 32, y);
        }
        line(16, 37, 25, 37);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PaperIllustrationPainter old) =>
      kind != old.kind ||
      clockTime != old.clockTime ||
      ink != old.ink ||
      paper != old.paper ||
      blue != old.blue ||
      yellow != old.yellow ||
      coral != old.coral;
}
