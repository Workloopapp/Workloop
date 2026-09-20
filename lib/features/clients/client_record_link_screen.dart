import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/widgets/record_link_unavailable.dart';
import '../../shared/widgets/slate_ui.dart';
import 'client_detail_screen.dart';

/// Resolve an incoming ID once, then let the existing detail screen own edits.
/// Background collection refreshes must not replace an open editing draft.
class ClientRecordLinkScreen extends ConsumerStatefulWidget {
  final String clientId;
  const ClientRecordLinkScreen({super.key, required this.clientId});
  @override
  ConsumerState<ClientRecordLinkScreen> createState() =>
      _ClientRecordLinkScreenState();
}

class _ClientRecordLinkScreenState
    extends ConsumerState<ClientRecordLinkScreen> {
  String? _workspaceId;
  Client? _client;

  @override
  void didUpdateWidget(covariant ClientRecordLinkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clientId != oldWidget.clientId) {
      _workspaceId = null;
      _client = null;
    }
  }

  void _retry() {
    ref.invalidate(clientsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceIdProvider);
    final clients = ref.watch(clientsProvider);
    final workspaceId = workspace.value;
    if (_workspaceId != workspaceId) {
      _workspaceId = workspaceId;
      _client = null;
    }
    if (workspace.isLoading || workspace.hasError || workspaceId == null) {
      final status = _status(
        hasError: workspace.hasError,
        unavailable: !workspace.isLoading && !workspace.hasError,
        onRetry: () => ref.invalidate(workspaceIdProvider),
      );
      // A refresh of the same workspace must block stale interactions without
      // unmounting the owner's editor. A changed workspace clears it above.
      return _client == null ? status : _clientView(blocker: status);
    }
    if (_client == null &&
        !clients.isLoading &&
        !clients.hasError &&
        clients.hasValue) {
      for (final client in clients.value!) {
        if (client.id == widget.clientId && client.workspaceId == workspaceId) {
          _client = client;
          break;
        }
      }
      if (_client == null) {
        return WorkloopRecordLinkUnavailable(
          recordName: 'Client',
          onRetry: _retry,
        );
      }
    }
    if (_client != null) {
      return _clientView();
    }
    return _status(hasError: clients.hasError, onRetry: _retry);
  }

  Widget _clientView({Widget? blocker}) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: blocker != null,
        child: ExcludeFocus(
          excluding: blocker != null,
          child: ClientDetailScreen(
            key: ValueKey('$_workspaceId:${widget.clientId}'),
            client: _client!.toMap(),
          ),
        ),
      ),
      if (blocker != null) Positioned.fill(child: blocker),
    ],
  );

  Widget _status({
    required bool hasError,
    required VoidCallback onRetry,
    bool unavailable = false,
  }) {
    if (unavailable) {
      return WorkloopRecordLinkUnavailable(
        recordName: 'Client',
        onRetry: onRetry,
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    AppSpacing.screenTop,
                    AppSpacing.pageX,
                    AppSpacing.sm,
                  ),
                  child: WorkloopRouteHeader(
                    title: 'Client',
                    onBack: () async {
                      final handled = await Navigator.maybePop(context);
                      if (!handled && mounted) {
                        workloopGoBack(context, fallbackLocation: '/clients');
                      }
                    },
                  ),
                ),
                Expanded(
                  child: Center(
                    child: hasError
                        ? SlateErrorState(
                            message:
                                'Could not load this client. Check your connection.',
                            onRetry: onRetry,
                          )
                        : const CircularProgressIndicator(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
