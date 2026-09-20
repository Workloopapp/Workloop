import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import 'local_weather_repository.dart';

class WeatherIllustration extends StatelessWidget {
  final LocalWeatherReading? reading;
  const WeatherIllustration({super.key, this.reading});
  @override
  Widget build(BuildContext context) {
    if (reading == null || reading!.condition == WeatherCondition.unknown) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          LucideIcons.mapPin,
          color: SlateTheme.of(context).textSecondary,
          size: 30,
        ),
      );
    }
    if (reading!.condition == WeatherCondition.clear && !reading!.night) {
      return const WorkloopIllustration(
        kind: WorkloopIllustrationKind.sun,
        size: 44,
      );
    }
    return CustomPaint(
      size: const Size(44, 44),
      painter: _WeatherPainter(reading!, SlateTheme.of(context)),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  final LocalWeatherReading reading;
  final WorkloopThemeTokens tokens;
  _WeatherPainter(this.reading, this.tokens);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 44, size.height / 44);
    final stroke = Paint()
      ..color = tokens.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = tokens.paperBlue;
    final condition = reading.condition;
    if (condition == WeatherCondition.clear ||
        condition == WeatherCondition.partlyCloudy) {
      if (reading.night) {
        final moon = Path()
          ..moveTo(29, 4)
          ..cubicTo(13, 1, 10, 24, 28, 25)
          ..cubicTo(20, 19, 20, 10, 29, 4)
          ..close();
        canvas.drawPath(moon, Paint()..color = tokens.paperYellow);
        canvas.drawPath(moon, stroke);
      } else {
        canvas.drawCircle(
          const Offset(28, 13),
          8,
          Paint()..color = tokens.paperYellow,
        );
        canvas.drawCircle(const Offset(28, 13), 8, stroke);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          canvas.drawLine(
            Offset(28 + 10 * math.cos(angle), 13 + 10 * math.sin(angle)),
            Offset(28 + 12 * math.cos(angle), 13 + 12 * math.sin(angle)),
            stroke,
          );
        }
      }
      if (condition == WeatherCondition.clear) return;
    }
    final cloud = Path()
      ..moveTo(9, 30)
      ..cubicTo(0, 30, 1, 17, 11, 18)
      ..cubicTo(13, 7, 29, 8, 31, 19)
      ..cubicTo(42, 17, 45, 30, 34, 30)
      ..close();
    canvas.drawPath(cloud, fill);
    canvas.drawPath(cloud, stroke);
    if (condition == WeatherCondition.rain) {
      for (final x in [12.0, 23.0, 34.0]) {
        canvas.drawLine(Offset(x, 34), Offset(x - 2, 39), stroke);
      }
    } else if (condition == WeatherCondition.snow) {
      for (final x in [12.0, 30.0]) {
        canvas.drawLine(Offset(x - 3, 37), Offset(x + 3, 37), stroke);
        canvas.drawLine(Offset(x, 34), Offset(x, 40), stroke);
      }
    } else if (condition == WeatherCondition.thunder) {
      final bolt = Path()
        ..moveTo(24, 26)
        ..lineTo(17, 35)
        ..lineTo(23, 35)
        ..lineTo(20, 42)
        ..lineTo(31, 31)
        ..lineTo(25, 31)
        ..close();
      canvas.drawPath(bolt, Paint()..color = tokens.paperYellow);
      canvas.drawPath(bolt, stroke);
    } else if (condition == WeatherCondition.fog) {
      canvas.drawLine(const Offset(7, 35), const Offset(36, 35), stroke);
      canvas.drawLine(const Offset(12, 40), const Offset(31, 40), stroke);
    }
  }

  @override
  bool shouldRepaint(_WeatherPainter oldDelegate) =>
      oldDelegate.reading.symbol != reading.symbol ||
      oldDelegate.tokens != tokens;
}
