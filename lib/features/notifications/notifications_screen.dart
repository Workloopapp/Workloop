import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/notifications/local_reminder_service.dart';
import '../../shared/notifications/notification_route.dart';
import '../../shared/notifications/remote_push_service.dart';
import '../../shared/notifications/remote_push_registration.dart';
import '../../shared/providers/notifications_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_refresh.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/widgets/slate_ui.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _markingAllRead = false;

  Future<void> _markAllRead() async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (!mounted) return;
      if (workspaceId == null) {
        throw StateError('No active workspace');
      }
      await ref.read(notificationsRepositoryProvider).markAllRead(workspaceId);
      if (!mounted) return;
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notifications could not be marked as read. Try again.',
            ),
            backgroundColor: AppColors.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAllRead = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(unreadNotificationsProvider);
    try {
      ref.invalidate(notificationsProvider);
      await ref.read(notificationsProvider.future);
    } catch (_) {
      // The list renders the provider's retryable error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationsProvider);
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
                    AppSpacing.xs,
                  ),
                  child: WorkloopRouteHeader(
                    title: 'Notifications',
                    trailing: notifications.maybeWhen(
                      data: (items) {
                        final unread =
                            unreadCount.asData?.value ??
                            items.where((item) => !item.read).length;
                        if (unread == 0) return null;
                        return WorkloopTextButton(
                          label: _markingAllRead ? 'Marking…' : 'Mark all read',
                          onPressed: _markingAllRead ? null : _markAllRead,
                        );
                      },
                      orElse: () => null,
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.of(context).green,
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        notifications.when(
                          loading: () => SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.of(context).green,
                              ),
                            ),
                          ),
                          error: (_, _) => SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: WorkloopEmptyState(
                                icon: LucideIcons.wifiOff,
                                title: 'Could not load notifications',
                                subtitle:
                                    'Check your connection, then try again.',
                                action: WorkloopTextButton(
                                  label: 'Try again',
                                  onPressed: _refresh,
                                ),
                              ),
                            ),
                          ),
                          data: (items) {
                            if (items.isEmpty) {
                              return const SliverFillRemaining(
                                hasScrollBody: false,
                                child: _EmptyNotifications(
                                  title: 'No notifications',
                                  subtitle:
                                      'Important updates will appear here.',
                                ),
                              );
                            }
                            return SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.pageX,
                                AppSpacing.sm,
                                AppSpacing.pageX,
                                AppSpacing.xxl,
                              ),
                              sliver: SliverList.list(
                                children: _groupedNotificationChildren(items),
                              ),
                            );
                          },
                        ),
                      ],
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
}

class NotificationSettingsView extends ConsumerWidget {
  const NotificationSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        0,
        AppSpacing.pageX,
        AppSpacing.xxl,
      ),
      children: [
        const _AlertHint(
          'These alerts are for you. Customer messages and emails to you have their own settings.',
        ),
        const SizedBox(height: AppSpacing.md),
        WorkloopPaperPanel(
          title: 'Where you see updates',
          tone: WorkloopPaperTone.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WorkloopListRow(
                flat: true,
                showDivider: false,
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                leading: const Icon(LucideIcons.inbox, size: 22),
                title: const Text(
                  'In-app inbox',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Your updates inside Workloop. Open them here, even with phone alerts off.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.of(context).t3,
                  ),
                ),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const WorkloopDivider(margin: EdgeInsets.zero),
              const _DeviceReminderStatus(),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        prefs.when(
          loading: () =>
              const SlateLoadingBlock(height: 180, radius: AppRadius.lg),
          error: (_, _) => SlateErrorState(
            message:
                'Could not load your saved choices. Check your connection and try again.',
            onRetry: () => ref.invalidate(notificationPreferencesProvider),
          ),
          data: (saved) {
            final values = {...defaultNotificationPrefs, ...saved};
            final businessEnabled = values['all_notifications'] == true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkloopPaperPanel(
                  title: 'Business activity',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _AlertHint(
                        'In-app inbox + push alerts',
                        emphasis: true,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const _AlertHint(
                        'Choose which updates appear in your inbox and are sent to your phone. Push alerts appear on your lock screen or in your phone’s notification centre.',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _PreferenceGroup(
                        values: values,
                        items: const [
                          _PreferenceItem(
                            'all_notifications',
                            'Receive business updates',
                            'Turn the business updates below on or off together.',
                          ),
                        ],
                      ),
                      if (!businessEnabled) ...[
                        const SizedBox(height: AppSpacing.xs),
                        const _AlertHint(
                          'New business updates are paused. Your existing inbox stays available. Phone reminders and emails are unaffected.',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const WorkloopDivider(margin: EdgeInsets.zero),
                      _PreferenceGroup(
                        values: values,
                        enabled: businessEnabled,
                        items: const [
                          _PreferenceItem(
                            'booking_request',
                            'Booking requests',
                            'New customer requests and requests waiting for a response.',
                          ),
                          _PreferenceItem(
                            'new_booking',
                            'Confirmed bookings',
                            'A booking is created or confirmed.',
                          ),
                          _PreferenceItem(
                            'payment_received',
                            'Payments received',
                            'A booking or linked payment is marked as paid.',
                          ),
                          _PreferenceItem(
                            'invoice_overdue',
                            'Unpaid and overdue payments',
                            'A completed booking is unpaid, or an invoice is overdue.',
                          ),
                          _PreferenceItem(
                            'morning_digest',
                            'Morning overview',
                            'Your day’s bookings, tasks and payments, around 7am in your business timezone.',
                          ),
                          _PreferenceItem(
                            'quiet_sundays',
                            'Skip Sunday overview',
                            'The morning overview only. Other updates still arrive.',
                            dependsOn: 'morning_digest',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                WorkloopPaperPanel(
                  title: 'Phone reminders',
                  tone: WorkloopPaperTone.plain,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _AlertHint('Phone only · for you', emphasis: true),
                      const SizedBox(height: AppSpacing.xs),
                      const _AlertHint(
                        'Scheduled by the app on your phone. These do not send a message to your customer or add an inbox update.',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _PreferenceGroup(
                        values: values,
                        items: const [
                          _PreferenceItem(
                            'appointment_reminder_15',
                            '15 minutes before a booking',
                            'A reminder for your upcoming scheduled bookings.',
                            requiresDevicePermission: true,
                          ),
                        ],
                      ),
                      const WorkloopDivider(
                        margin: EdgeInsets.only(
                          top: AppSpacing.xs,
                          bottom: AppSpacing.sm,
                        ),
                      ),
                      const _AlertHint(
                        'Task reminders are chosen inside each task. Reminder choices sync with your workspace; each phone schedules its own alerts.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                WorkloopPaperPanel(
                  title: 'Quiet hours',
                  tone: WorkloopPaperTone.plain,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _AlertHint('Business push only', emphasis: true),
                      const SizedBox(height: AppSpacing.sm),
                      _PreferenceGroup(
                        values: values,
                        enabled: businessEnabled,
                        items: const [
                          _PreferenceItem(
                            'quiet_hours_enabled',
                            'Pause overnight alerts',
                            'Hold business push alerts from 9pm to 7am in your business timezone.',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const _AlertHint(
                        'Your inbox still updates immediately. Phone reminders and emails keep their own timings. Use your phone’s Focus or Do Not Disturb to silence all phone alerts.',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AlertHint extends StatelessWidget {
  final String text;
  final bool emphasis;

  const _AlertHint(this.text, {this.emphasis = false});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: emphasis ? AppColors.of(context).t1 : AppColors.of(context).t3,
      fontSize: 13,
      fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
      height: 1.45,
    ),
  );
}

class _DeviceReminderStatus extends ConsumerStatefulWidget {
  const _DeviceReminderStatus();

  @override
  ConsumerState<_DeviceReminderStatus> createState() =>
      _DeviceReminderStatusState();
}

class _DeviceReminderStatusState extends ConsumerState<_DeviceReminderStatus>
    with WidgetsBindingObserver {
  late Future<LocalReminderPermission> _status;
  StreamSubscription<void>? _permissionSubscription;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _status = ref.read(localReminderServiceProvider).permissionStatus();
    _permissionSubscription = ref
        .read(localReminderServiceProvider)
        .permissionChanges
        .listen((_) {
          if (mounted) _checkPermission();
        });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_permissionSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  void _checkPermission() {
    setState(() {
      _status = ref.read(localReminderServiceProvider).permissionStatus();
    });
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final request = ref
          .read(localReminderServiceProvider)
          .requestPermission();
      setState(() => _status = request);
      final result = await request;
      if (!mounted) return;
      if (result == LocalReminderPermission.granted) {
        try {
          await ref.read(remotePushServiceProvider).requestPermission();
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Phone permission is on, but business push could not connect. Scheduled phone reminders can still work. Try again.',
              ),
            ),
          );
        }
      }
      if (!mounted || result == LocalReminderPermission.granted) return;
      final message = result == LocalReminderPermission.unsupported
          ? 'Scheduled reminders are available in the iOS and Android apps.'
          : 'Notifications are still off. You can enable them in your device settings.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not enable notifications. Try again.'),
        ),
      );
      _checkPermission();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _openPhoneSettings() async {
    try {
      final opened = await ref
          .read(remotePushServiceProvider)
          .openNotificationSettings();
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open your phone’s Settings, choose Workloop, then Notifications.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = ref.watch(remotePushRegistrationStatusProvider);
    final remoteSupported = ref.watch(remotePushServiceProvider).isSupported;
    return FutureBuilder<LocalReminderPermission>(
      future: _status,
      builder: (context, snapshot) {
        final checking = snapshot.connectionState == ConnectionState.waiting;
        final failed = snapshot.hasError;
        final status = snapshot.data;
        final ready =
            !checking && !failed && status == LocalReminderPermission.granted;
        final unsupported =
            !checking &&
            !failed &&
            status == LocalReminderPermission.unsupported;
        final title = checking
            ? 'Checking phone permission'
            : failed
            ? 'Could not check phone permission'
            : ready
            ? 'Phone alerts allowed'
            : unsupported
            ? 'Phone alerts unavailable here'
            : 'Phone alerts are off';
        final connectionDescription = !remoteSupported
            ? 'Business push alerts are unavailable in this build. Scheduled phone reminders can still work.'
            : switch (registration) {
                RemotePushRegistrationStatus.registered =>
                  'Permission is on. Delivery also depends on your connection and Workloop’s notification service. Focus or Do Not Disturb can silence alerts.',
                RemotePushRegistrationStatus.registering =>
                  'Connecting this phone for business updates…',
                RemotePushRegistrationStatus.retrying =>
                  'The connection needs another attempt. Keep Workloop open with an internet connection.',
                RemotePushRegistrationStatus.failed =>
                  'This phone could not connect for business updates. Check your internet connection and try again.',
                RemotePushRegistrationStatus.idle =>
                  'Phone permission is on. Workloop is checking the connection for business updates.',
              };
        final subtitle = checking
            ? 'Checking this phone’s notification settings.'
            : failed
            ? 'Try again to check whether this phone allows reminders.'
            : ready
            ? connectionDescription
            : unsupported
            ? 'Use the Workloop iPhone or Android app for phone alerts.'
            : 'Allow notifications to receive your chosen reminders and business updates on this phone.';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkloopListRow(
              flat: true,
              showDivider: false,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              leading: Icon(
                ready ? LucideIcons.bellRing : LucideIcons.bellOff,
                size: 22,
                color: ready
                    ? AppColors.of(context).accentInk
                    : AppColors.of(context).t3,
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.of(context).t3,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            if (!checking && !unsupported)
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  if (failed ||
                      !ready ||
                      (remoteSupported &&
                          registration !=
                              RemotePushRegistrationStatus.registered))
                    WorkloopTextButton(
                      label: _requesting
                          ? 'Checking…'
                          : failed
                          ? 'Try again'
                          : ready
                          ? 'Check connection'
                          : 'Turn on',
                      onPressed: _requesting
                          ? null
                          : failed
                          ? _checkPermission
                          : _requestPermission,
                    ),
                  WorkloopTextButton(
                    label: 'Phone settings',
                    onPressed: _openPhoneSettings,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _PreferenceGroup extends ConsumerStatefulWidget {
  final bool enabled;
  final Map<String, dynamic> values;
  final List<_PreferenceItem> items;

  const _PreferenceGroup({
    this.enabled = true,
    required this.values,
    required this.items,
  });

  @override
  ConsumerState<_PreferenceGroup> createState() => _PreferenceGroupState();
}

class _PreferenceGroupState extends ConsumerState<_PreferenceGroup> {
  final Set<String> _savingKeys = {};

  Future<void> _updatePreference(_PreferenceItem item, bool next) async {
    if (_savingKeys.contains(item.key)) return;
    setState(() => _savingKeys.add(item.key));
    final originalWorkspace = ref.read(workspaceIdProvider).value;
    try {
      if (next && item.requiresDevicePermission) {
        final permission = await ref
            .read(localReminderServiceProvider)
            .requestPermission();
        if (!mounted) return;
        if (permission != LocalReminderPermission.granted) {
          final message = permission == LocalReminderPermission.unsupported
              ? 'Scheduled reminders are available in the iOS and Android apps.'
              : 'Notifications are off. Enable them in your device settings to receive reminders.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          return;
        }
      }
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (!mounted) return;
      if (workspaceId == null || workspaceId != originalWorkspace) {
        throw StateError('No active workspace');
      }
      await ref.read(notificationsRepositoryProvider).upsertPreferences(
        workspaceId,
        {item.key: next},
      );
      if (!mounted) return;
      ref.invalidate(notificationPreferencesProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationsProvider);
    } catch (_) {
      if (mounted) {
        ref.invalidate(notificationPreferencesProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'That notification setting could not be saved. Try again.',
            ),
            backgroundColor: AppColors.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingKeys.remove(item.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.items.length; i++) ...[
          _PreferenceRow(
            item: widget.items[i],
            value: widget.values[widget.items[i].key] as bool? ?? false,
            onChanged:
                !widget.enabled ||
                    (widget.items[i].dependsOn != null &&
                        widget.values[widget.items[i].dependsOn] != true) ||
                    _savingKeys.isNotEmpty
                ? null
                : (next) => _updatePreference(widget.items[i], next),
          ),
          if (i < widget.items.length - 1)
            const WorkloopDivider(margin: EdgeInsets.zero),
        ],
      ],
    );
  }
}

class _PreferenceItem {
  final String key;
  final String title;
  final String subtitle;
  final bool requiresDevicePermission;
  final String? dependsOn;

  const _PreferenceItem(
    this.key,
    this.title,
    this.subtitle, {
    this.requiresDevicePermission = false,
    this.dependsOn,
  });
}

class _PreferenceRow extends StatelessWidget {
  final _PreferenceItem item;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _PreferenceRow({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      key: ValueKey('notification-preference-${item.key}'),
      contentPadding: EdgeInsets.zero,
      title: Text(
        item.title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        item.subtitle,
        style: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

List<Widget> _groupedNotificationChildren(List<SlateNotification> items) {
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);
  final todayItems = items.where((item) {
    final created = item.createdAt?.toLocal();
    return created != null && !created.isBefore(todayStart);
  }).toList();
  final earlierItems = items
      .where((item) => !todayItems.contains(item))
      .toList();

  return [
    if (todayItems.isNotEmpty) ...[
      const _NotificationGroupLabel('Today'),
      for (var index = 0; index < todayItems.length; index++) ...[
        _NotificationTile(
          key: ValueKey(todayItems[index].id),
          item: todayItems[index],
        ),
        if (index != todayItems.length - 1)
          const WorkloopDivider(margin: EdgeInsets.zero),
      ],
    ],
    if (earlierItems.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.lg),
      const _NotificationGroupLabel('Earlier'),
      for (var index = 0; index < earlierItems.length; index++) ...[
        _NotificationTile(
          key: ValueKey(earlierItems[index].id),
          item: earlierItems[index],
        ),
        if (index != earlierItems.length - 1)
          const WorkloopDivider(margin: EdgeInsets.zero),
      ],
    ],
  ];
}

class _NotificationGroupLabel extends StatelessWidget {
  final String label;
  const _NotificationGroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, top: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerStatefulWidget {
  final SlateNotification item;
  const _NotificationTile({super.key, required this.item});

  @override
  ConsumerState<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends ConsumerState<_NotificationTile> {
  bool _activating = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final missingRecordLink = workloopNotificationHasMissingRecordLink(
      item.type,
      item.deepLink,
    );
    final destination = missingRecordLink
        ? '/notifications'
        : workloopNotificationDestination(item.deepLink);
    final hasDeepLink = destination != null && destination != '/notifications';
    final isInteractive = !_activating && (!item.read || hasDeepLink);

    Future<void> activate() async {
      if (_activating) return;
      setState(() => _activating = true);
      try {
        if (!item.read) {
          try {
            await ref.read(notificationsRepositoryProvider).markRead(item.id);
            if (!mounted) return;
            ref.invalidate(notificationsProvider);
            ref.invalidate(unreadNotificationsProvider);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'This notification could not be marked as read.',
                  ),
                  backgroundColor: AppColors.of(context).error,
                ),
              );
            }
          }
        }
        if (context.mounted && hasDeepLink) {
          refreshWorkspaceData(ref.invalidate);
          await context.push(destination);
        }
      } finally {
        if (mounted) setState(() => _activating = false);
      }
    }

    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    _iconForType(item.type),
                    color: item.read
                        ? AppColors.of(context).t3
                        : AppColors.of(context).t1,
                    size: 18,
                  ),
                ),
                if (!item.read)
                  Positioned(
                    right: 1,
                    top: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.of(context).brandAccent,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(width: 7, height: 7),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 14,
                    fontWeight: item.read ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.body,
                  style: TextStyle(
                    color: AppColors.of(context).t2,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                if (missingRecordLink) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'The original record link is unavailable for this older update.',
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasDeepLink) ...[
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(
                LucideIcons.chevronRight,
                color: AppColors.of(context).t3,
                size: 15,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: isInteractive,
      label:
          '${item.read ? '' : 'Unread notification. '}${item.title}. '
          '${item.body}',
      hint: switch ((item.read, hasDeepLink)) {
        (false, true) => 'Marks as read and opens the related item',
        (false, false) => 'Marks as read',
        (true, true) => 'Opens the related item',
        (true, false) => null,
      },
      onTap: isInteractive ? activate : null,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: isInteractive ? activate : null,
            child: tile,
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'payment' ||
      'payment_received' ||
      'invoice_overdue' => LucideIcons.banknote,
      'booking' ||
      'new_booking' ||
      'booking_request' => LucideIcons.calendarPlus,
      'task' || 'task_due' => LucideIcons.checkSquare,
      'no_show' => LucideIcons.userX,
      _ => LucideIcons.bell,
    };
  }
}

class _EmptyNotifications extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyNotifications({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bell, color: AppColors.of(context).t3, size: 38),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.of(context).t3),
            ),
          ],
        ),
      ),
    );
  }
}
