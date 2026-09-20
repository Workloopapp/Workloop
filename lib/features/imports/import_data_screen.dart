import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import 'calendar_import_screen.dart';
import 'contacts_import_screen.dart';
import 'csv_import_screen.dart';
import 'text_import_screen.dart';

class ImportDataScreen extends StatelessWidget {
  const ImportDataScreen({super.key});

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WorkloopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkloopRouteHeader(
            title: 'Import data',
            backSemanticLabel: 'Back to settings',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Bring existing work into one place. You review everything before Workloop creates it.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const WorkloopSectionHeader(label: 'People and bookings'),
          _ImportRow(
            icon: LucideIcons.contact,
            title: 'Device contacts',
            subtitle: 'Choose specific people and check likely duplicates',
            onTap: () => _open(context, const ContactsImportScreen()),
          ),
          _ImportRow(
            icon: LucideIcons.calendarDays,
            title: 'Calendar events',
            subtitle: 'Review a one-time snapshot before creating bookings',
            onTap: () => _open(context, const CalendarImportScreen()),
          ),
          _ImportRow(
            icon: LucideIcons.fileSpreadsheet,
            title: 'Client files',
            subtitle: 'Apple / Google Contacts vCards and spreadsheet CSVs',
            showDivider: false,
            onTap: () => _open(context, const CsvImportScreen()),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const WorkloopSectionHeader(label: 'Files'),
          _ImportRow(
            icon: LucideIcons.listTodo,
            title: 'Task list',
            subtitle: 'Turn each line of a text file into an open task',
            onTap: () => _open(
              context,
              const TextImportScreen(type: TextImportType.tasks),
            ),
          ),
          _ImportRow(
            icon: LucideIcons.fileText,
            title: 'Notes files',
            subtitle: 'Import selected plain-text or Markdown files',
            showDivider: false,
            onTap: () => _open(
              context,
              const TextImportScreen(type: TextImportType.notes),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          WorkloopSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.shieldCheck,
                  color: AppColors.of(context).t2,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Private by design',
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Permissions are requested only when you choose a source. Workloop reads the minimum data needed and imports only your selections into your workspace.',
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
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

class _ImportRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _ImportRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopListRow(
      onTap: onTap,
      showDivider: showDivider,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.of(context).modBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.of(context).t2, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 12,
          height: 1.35,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: AppColors.of(context).t4,
        size: 18,
      ),
    );
  }
}
