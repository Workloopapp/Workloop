import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/workspace_settings_repository.dart';
import 'workspace_provider.dart';
import 'workspace_settings_provider.dart';

// Keep successful writes and their cache update together. A route may close
// while a write is in flight; its WidgetRef must not own the invalidation.
final updateWorkspaceSettingsProvider =
    Provider<Future<void> Function(String, Map<String, dynamic>)>((ref) {
      final repository = ref.watch(workspaceSettingsRepositoryProvider);
      return (workspaceId, values) async {
        await repository.update(workspaceId, values);
        if (ref.mounted && ref.read(workspaceIdProvider).value == workspaceId) {
          ref.invalidate(workspaceSettingsProvider);
        }
      };
    });
