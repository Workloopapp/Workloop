import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import '../settings/widgets/settings_business_tab.dart';
import 'working_hours_editor.dart';

class ProfileEditorScreen extends StatefulWidget {
  final SettingsBusinessSection section;

  const ProfileEditorScreen({super.key, required this.section});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  final _businessController = SettingsBusinessController();

  String get _title => switch (section) {
    SettingsBusinessSection.business => 'Business details',
    SettingsBusinessSection.workingHours => 'Working hours',
    SettingsBusinessSection.publicProfile => 'Booking page',
    SettingsBusinessSection.services => 'Services',
  };

  SettingsBusinessSection get section => widget.section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    AppSpacing.screenTop,
                    AppSpacing.pageX,
                    AppSpacing.xl,
                  ),
                  child: WorkloopRouteHeader(
                    title: _title,
                    backSemanticLabel:
                        section == SettingsBusinessSection.publicProfile
                        ? 'Back to Booking page'
                        : 'Back to Business profile',
                    trailing: section == SettingsBusinessSection.services
                        ? WorkloopTopAction(
                            label: 'Add service',
                            onTap: _businessController.showAddService,
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: section == SettingsBusinessSection.workingHours
                      ? const WorkingHoursEditor()
                      : SettingsBusinessTab(
                          initialSection: section,
                          showOnlySelected: true,
                          controller: _businessController,
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
