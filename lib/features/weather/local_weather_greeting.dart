import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import 'local_weather_provider.dart';
import 'weather_illustration.dart';
import 'weather_settings_sheet.dart';

/// A greeting with independently loaded weather. It never holds up Today data.
class WorkloopWeatherGreeting extends ConsumerStatefulWidget {
  final String greeting;
  const WorkloopWeatherGreeting({super.key, required this.greeting});
  @override
  ConsumerState<WorkloopWeatherGreeting> createState() =>
      _WorkloopWeatherGreetingState();
}

class _WorkloopWeatherGreetingState
    extends ConsumerState<WorkloopWeatherGreeting>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
  }

  void _refresh() {
    if (!mounted || !_foreground || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    final userId = ref.read(weatherUserIdProvider).asData?.value;
    if (userId != null) {
      unawaited(ref.read(localWeatherProvider(userId).notifier).refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(weatherUserIdProvider).asData?.value;
    final value = userId == null
        ? null
        : ref.watch(localWeatherProvider(userId)).asData?.value;
    final reading = value?.reading;
    final current = reading != null && reading.isCurrent(DateTime.now())
        ? reading
        : null;
    final label = current == null
        ? (value?.busy == true
              ? 'Checking weather…'
              : value?.selection.enabled == true
              ? 'Weather unavailable'
              : 'Local weather')
        : '${current.temperature.round()}° · ${current.description} · ${value!.selection.label}';
    final VoidCallback? openWeather = userId == null
        ? null
        : () {
            showWorkloopBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => LocalWeatherSettings(userId: userId),
            );
          };
    return Semantics(
      button: userId != null,
      label: '${widget.greeting}. $label. Weather settings',
      excludeSemantics: true,
      onTap: openWeather,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: openWeather,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              WeatherIllustration(reading: current),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.greeting,
                      style: TextStyle(
                        color: SlateTheme.of(context).textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: SlateTheme.of(context).textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
