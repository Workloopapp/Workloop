import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/providers/appointments_provider.dart';
import '../../../shared/providers/workspace_settings_provider.dart';
import '../../../shared/repositories/slate_repositories.dart';

// Preserve the settings API while sharing the exact same cache and invalidation
// boundary used by booking pickers and dashboard totals.
final settingsServicesProvider = servicesProvider;

final settingsBusinessProfileProvider = FutureProvider<BusinessProfile?>((
  ref,
) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return null;
  return ref.watch(profileRepositoryProvider).getWorkspaceProfile(workspaceId);
});

final settingsWorkspaceSettingsProvider = workspaceSettingsProvider;
