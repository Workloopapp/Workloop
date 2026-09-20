import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/slate_models.dart';
import '../repositories/slate_repositories.dart';
import 'workspace_provider.dart';

final bookingRequestsProvider = FutureProvider<List<BookingRequest>>((
  ref,
) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return [];
  return ref.watch(profileRepositoryProvider).bookingRequests(workspaceId);
});
