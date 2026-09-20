import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/business_document_defaults.dart';
import 'workspace_provider.dart';
import 'workspace_settings_provider.dart';

final businessDocumentDefaultsProvider =
    FutureProvider<BusinessDocumentDefaults>((ref) async {
      final workspace = await ref.watch(workspaceProvider.future);
      final settings = await ref.watch(workspaceSettingsProvider.future);
      return BusinessDocumentDefaults.fromMaps(workspace, settings);
    });
