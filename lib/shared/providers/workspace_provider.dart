import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/slate_repositories.dart';

final sessionIntegrityProvider = FutureProvider<bool>((ref) async {
  return ref.watch(authRepositoryProvider).validateCurrentSession();
});

final workspaceProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final workspace = await ref
      .watch(workspaceRepositoryProvider)
      .currentWorkspace();
  return workspace?.toMap();
});

final workspaceIdProvider = FutureProvider<String?>((ref) async {
  final workspace = await ref.watch(workspaceProvider.future);
  return workspace?['id'] as String?;
});
