import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/repositories/address_search_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import 'local_weather_provider.dart';
import 'local_weather_repository.dart';

class LocalWeatherSettings extends ConsumerStatefulWidget {
  final String userId;
  const LocalWeatherSettings({super.key, required this.userId});
  @override
  ConsumerState<LocalWeatherSettings> createState() => _WeatherSettingsState();
}

class _WeatherSettingsState extends ConsumerState<LocalWeatherSettings> {
  final _area = TextEditingController();
  String _sessionToken = _newSessionToken();
  static String _newSessionToken() =>
      '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 31)}';
  List<AddressPrediction> _results = [];
  String? _message;
  bool _searching = false;
  int _searchVersion = 0;
  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_area.text.trim().length < 3 ||
        _searching ||
        (ref.read(localWeatherProvider(widget.userId)).asData?.value.busy ??
            true)) {
      return;
    }
    final version = ++_searchVersion;
    setState(() {
      _searching = true;
      _message = null;
      _results = [];
    });
    try {
      final results = await ref
          .read(addressSearchRepositoryProvider)
          .autocomplete(input: _area.text, sessionToken: _sessionToken)
          .timeout(const Duration(seconds: 8));
      if (mounted && version == _searchVersion) {
        setState(() {
          _results = results.take(4).toList();
          _message = results.isEmpty
              ? 'No matching area. Try a nearby UK address or postcode.'
              : null;
        });
      }
    } catch (_) {
      if (mounted && version == _searchVersion) {
        setState(() {
          _message =
              'Area search is unavailable. Try again or use your location.';
        });
      }
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  Future<void> _selectMode(WeatherSelection selection) async {
    // An old address lookup must not undo a newer device/off choice.
    setState(() {
      ++_searchVersion;
      _searching = false;
      _results = [];
      _message = null;
    });
    await ref
        .read(localWeatherProvider(widget.userId).notifier)
        .select(selection);
  }

  Future<void> _choose(AddressPrediction prediction) async {
    final version = ++_searchVersion;
    final sessionToken = _sessionToken;
    // A Places Details request ends its autocomplete billing session.
    _sessionToken = _newSessionToken();
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final area = await ref
          .read(addressSearchRepositoryProvider)
          .resolve(placeId: prediction.placeId, sessionToken: sessionToken)
          .timeout(const Duration(seconds: 8));
      if (area.latitude == null || area.longitude == null) {
        throw const FormatException('No area coordinates');
      }
      if (!mounted || version != _searchVersion) return;
      await ref
          .read(localWeatherProvider(widget.userId).notifier)
          .select(
            WeatherSelection.manual(
              WeatherArea(area.latitude!, area.longitude!, _area.text.trim()),
            ),
          );
      if (mounted && version == _searchVersion) {
        setState(() {
          _results = [];
          _area.clear();
        });
      }
    } catch (_) {
      if (mounted && version == _searchVersion) {
        setState(() {
          _message = 'Could not use this area. Choose another nearby address.';
        });
      }
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value =
        ref.watch(localWeatherProvider(widget.userId)).asData?.value ??
        const LocalWeatherState(busy: true);
    final reading = value.reading;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: SingleChildScrollView(
          child: SlateSheetFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Local weather',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (reading != null && reading.isCurrent(DateTime.now())) ...[
                  Text(
                    '${reading.temperature.round()}° · ${reading.description}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('${value.selection.label} · Forecast for this hour'),
                  Text(
                    'Forecast updated ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(reading.updatedAt.toLocal()))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                const Text(
                  'Use your approximate location while Workloop is open, or choose an area. Weather never changes your bookings.',
                ),
                if (value.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(value.message!),
                  ),
                const SizedBox(height: AppSpacing.md),
                WorkloopPrimaryButton(
                  label: value.busy ? 'Checking weather…' : 'Use my location',
                  onPressed: value.busy
                      ? null
                      : () => _selectMode(const WeatherSelection.device()),
                  icon: LucideIcons.mapPin,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _area,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Or choose a UK area',
                    hintText: 'Address or postcode',
                    suffixIcon: IconButton(
                      tooltip: 'Search area',
                      onPressed: _searching || value.busy ? null : _search,
                      icon: const Icon(LucideIcons.search),
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {
                      ++_searchVersion;
                      _results = [];
                      _searching = false;
                      _message = null;
                    });
                  },
                  onSubmitted: (_) => _search(),
                ),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text('Finding area…'),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(_message!),
                  ),
                for (final result in _results)
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(result.primaryText),
                      subtitle: Text(result.secondaryText),
                      onTap: _searching || value.busy
                          ? null
                          : () => _choose(result),
                    ),
                  ),
                if (_results.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Google Maps',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                        color: SlateTheme.of(context).providerAttributionInk,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    WorkloopTextButton(
                      label: 'Weather: MET Norway',
                      onPressed: () => launchUrl(
                        Uri.parse('https://api.met.no/'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    WorkloopTextButton(
                      label: 'CC BY 4.0',
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'https://creativecommons.org/licenses/by/4.0/',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Forecast data is shown as rounded temperature and illustrated conditions.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (value.selection.enabled)
                  WorkloopTextButton(
                    label: 'Turn weather off',
                    onPressed: () => _selectMode(const WeatherSelection.off()),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: WorkloopTextButton(
                    label: 'Done',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
