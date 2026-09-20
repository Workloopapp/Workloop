import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import 'widgets/email_settings_section.dart';

class CustomerRemindersScreen extends StatelessWidget {
  const CustomerRemindersScreen({super.key});

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
                  AppSpacing.md,
                ),
                child: WorkloopRouteHeader(
                  title: 'Booking reminders',
                  backSemanticLabel: 'Go back',
                  onBack: () => Navigator.pop(context),
                ),
              ),
              const Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    0,
                    AppSpacing.pageX,
                    AppSpacing.xxl,
                  ),
                  child: EmailSettingsSection(showAccountEmails: false),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
