import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../models/business_feed_item.dart';
import 'slate_ui.dart';

class BusinessFeedList extends StatelessWidget {
  final List<BusinessFeedItem> items;
  final bool compact;
  final int? limit;
  final ValueChanged<BusinessFeedItem>? onItemTap;
  final VoidCallback? onViewAll;
  final String? emptyMessage;

  const BusinessFeedList({
    super.key,
    required this.items,
    this.compact = false,
    this.limit,
    this.onItemTap,
    this.onViewAll,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = limit == null ? items : items.take(limit!).toList();
    if (visibleItems.isEmpty) {
      return _BusinessFeedEmptyState(message: emptyMessage);
    }

    final sections = _groupItems(visibleItems);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...[
          if (!compact || sections.length > 1) ...[
            _FeedSectionLabel(label: section.label),
            const SizedBox(height: AppSpacing.xs),
          ],
          _FeedSection(
            items: section.items,
            compact: compact,
            onItemTap: onItemTap,
          ),
          if (section != sections.last) const SizedBox(height: AppSpacing.sm),
        ],
        if (onViewAll != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                SlateHaptics.tap();
                onViewAll!();
              },
              icon: const Icon(LucideIcons.arrowRight, size: 16),
              label: const Text('View all'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).modHome,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FeedSection extends StatelessWidget {
  final List<BusinessFeedItem> items;
  final bool compact;
  final ValueChanged<BusinessFeedItem>? onItemTap;

  const _FeedSection({
    required this.items,
    required this.compact,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items) ...[
          _BusinessFeedRow(
            item: item,
            compact: compact,
            onTap: onItemTap == null ? null : () => onItemTap!(item),
          ),
        ],
      ],
    );
  }
}

class _BusinessFeedRow extends StatelessWidget {
  final BusinessFeedItem item;
  final bool compact;
  final VoidCallback? onTap;

  const _BusinessFeedRow({
    required this.item,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _moduleColor(context, item.moduleKey);
    final icon = _iconFor(item.icon);
    final priorityLabel = _priorityLabel(item.priority);

    return WorkloopListRow(
      onTap: onTap,
      padding: EdgeInsets.symmetric(
        vertical: compact ? AppSpacing.sm : AppSpacing.md,
      ),
      leading: Container(
        width: compact ? 32 : 38,
        height: compact ? 32 : 38,
        decoration: BoxDecoration(
          color: item.priority == BusinessFeedPriority.attention
              ? AppColors.of(context).warning.withValues(alpha: 0.09)
              : color.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: compact ? 15 : 17),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              item.title,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (priorityLabel != null) ...[
            const SizedBox(width: AppSpacing.xs),
            _FeedPill(label: priorityLabel, priority: item.priority),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.subtitle,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text(
                  _timeAgo(item.timestamp),
                  style: TextStyle(
                    color: AppColors.of(context).t4,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.actionLabel != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    item.actionLabel!,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
      trailing: onTap == null
          ? null
          : Icon(
              LucideIcons.chevronRight,
              color: AppColors.of(context).t3,
              size: 16,
            ),
    );
  }
}

class _FeedPill extends StatelessWidget {
  final String label;
  final BusinessFeedPriority priority;

  const _FeedPill({required this.label, required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = priority == BusinessFeedPriority.attention
        ? AppColors.of(context).warning
        : AppColors.of(context).statusSuccess;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FeedSectionLabel extends StatelessWidget {
  final String label;

  const _FeedSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: AppColors.of(context).t3,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _BusinessFeedEmptyState extends StatelessWidget {
  final String? message;

  const _BusinessFeedEmptyState({this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.of(context).border.withValues(alpha: 0.54),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.activity,
            color: AppColors.of(context).modHome,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message ??
                  'Your business feed will appear here as bookings, payments, tasks and notes happen.',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedGroup {
  final String label;
  final List<BusinessFeedItem> items;

  const _FeedGroup({required this.label, required this.items});
}

List<_FeedGroup> _groupItems(List<BusinessFeedItem> items) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final groups = <String, List<BusinessFeedItem>>{
    'Today': [],
    'Yesterday': [],
    'Upcoming': [],
    'Earlier': [],
  };

  for (final item in items) {
    final day = DateTime(
      item.timestamp.year,
      item.timestamp.month,
      item.timestamp.day,
    );
    if (day == today) {
      groups['Today']!.add(item);
    } else if (day == yesterday) {
      groups['Yesterday']!.add(item);
    } else if (day.isAfter(today)) {
      groups['Upcoming']!.add(item);
    } else {
      groups['Earlier']!.add(item);
    }
  }

  return groups.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => _FeedGroup(label: entry.key, items: entry.value))
      .toList();
}

IconData _iconFor(String key) {
  return switch (key) {
    'alert' => LucideIcons.alertCircle,
    'banknote' => LucideIcons.banknote,
    'calendar' => LucideIcons.calendarDays,
    'check' => LucideIcons.checkCircle2,
    'clock' => LucideIcons.clock3,
    'inbox' => LucideIcons.inbox,
    'note' => LucideIcons.stickyNote,
    'receipt' => LucideIcons.receipt,
    'sparkles' => LucideIcons.sparkles,
    'target' => LucideIcons.target,
    'user' => LucideIcons.user,
    _ => LucideIcons.activity,
  };
}

Color _moduleColor(BuildContext context, String key) {
  return switch (key) {
    'bookings' => AppColors.of(context).modCalendar,
    'clients' => AppColors.of(context).modClients,
    'money' => AppColors.of(context).modFinance,
    'notes' => AppColors.of(context).modNotes,
    'tasks' => AppColors.of(context).modTasks,
    _ => AppColors.of(context).modHome,
  };
}

String? _priorityLabel(BusinessFeedPriority priority) {
  return switch (priority) {
    BusinessFeedPriority.attention => 'Attention',
    BusinessFeedPriority.positive => 'Good',
    BusinessFeedPriority.normal => null,
  };
}

String _timeAgo(DateTime timestamp) {
  final now = DateTime.now();
  final difference = now.difference(timestamp);
  if (difference.inMinutes.abs() < 60 && !timestamp.isAfter(now)) {
    return '${difference.inMinutes.clamp(0, 59)}m ago';
  }
  if (difference.inHours < 24 && !timestamp.isAfter(now)) {
    return '${difference.inHours}h ago';
  }
  if (timestamp.isAfter(now)) {
    final until = timestamp.difference(now);
    if (until.inHours < 24) return 'In ${until.inHours}h';
    return 'In ${until.inDays}d';
  }
  return '${difference.inDays}d ago';
}
