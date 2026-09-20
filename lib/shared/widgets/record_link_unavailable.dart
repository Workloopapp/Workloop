import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import 'slate_ui.dart';

/// An exact record link must not silently turn into a search through a list.
class WorkloopRecordLinkUnavailable extends StatelessWidget {
  final String recordName;
  final VoidCallback onRetry;

  const WorkloopRecordLinkUnavailable({
    super.key,
    required this.recordName,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
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
                child: WorkloopRouteHeader(title: recordName),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: WorkloopEmptyState(
                      icon: LucideIcons.fileQuestion,
                      title:
                          'This ${recordName.toLowerCase()} is no longer available',
                      subtitle:
                          'It may have been removed or belong to a different business. You can go back or check again.',
                      action: WorkloopTextButton(
                        label: 'Check again',
                        onPressed: onRetry,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
