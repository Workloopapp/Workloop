part of 'appointments_screen.dart';

class _AppointmentListView extends StatelessWidget {
  final List<Map<String, dynamic>> appointments;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final Function(Map<String, dynamic>) onTap;
  final RefreshCallback onRefresh;
  final bool groupByDate;
  final bool showStatusBadge;

  const _AppointmentListView({
    required this.appointments,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onTap,
    required this.onRefresh,
    this.groupByDate = false,
    this.showStatusBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.of(context).accentPrimary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                0,
                AppSpacing.pageX,
                AppSpacing.shellBottomClearance(context),
              ),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WorkloopEmptyState(
                        icon: emptyIcon,
                        title: emptyTitle,
                        subtitle: emptySubtitle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!groupByDate) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.of(context).accentPrimary,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageX,
            0,
            AppSpacing.pageX,
            AppSpacing.shellBottomClearance(context),
          ),
          itemCount: appointments.length,
          separatorBuilder: (_, _) => const SizedBox.shrink(),
          itemBuilder: (_, i) => _BookingRecordRow(
            rowKey: ValueKey('list-booking-row-${appointments[i]['id']}'),
            appointment: appointments[i],
            onTap: () => onTap(appointments[i]),
            showStatusBadge: showStatusBadge,
            showDivider: i != appointments.length - 1,
          ),
        ),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final appt in appointments) {
      final dt = DateTime.tryParse(
        appt['start_time'] as String? ?? '',
      )?.toLocal();
      final key = dt != null ? _dateKey(dt) : 'Unknown';
      grouped.putIfAbsent(key, () => []).add(appt);
    }

    final keys = grouped.keys.toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.of(context).accentPrimary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pageX,
          0,
          AppSpacing.pageX,
          AppSpacing.shellBottomClearance(context),
        ),
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final key = keys[i];
          final group = grouped[key]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: AppColors.of(context).t3,
                  ),
                ),
              ),
              ...group.indexed.map(
                (entry) => _BookingRecordRow(
                  rowKey: ValueKey('list-booking-row-${entry.$2['id']}'),
                  appointment: entry.$2,
                  onTap: () => onTap(entry.$2),
                  showStatusBadge: showStatusBadge,
                  showDivider: entry.$1 != group.length - 1,
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  String _dateKey(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = nextBookingCalendarDay(today);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = d.difference(today).inDays;

    if (d == today) return 'TODAY';
    if (d == tomorrow) return 'TOMORROW';
    if (diff > 0 && diff < 7) {
      const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      return days[dt.weekday - 1];
    }
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _BookingCalendarView extends StatelessWidget {
  final List<Map<String, dynamic>> appointments;
  final DateTime selectedDate;
  final DateTime today;
  final List<Map<String, dynamic>> selectedDayAppointments;
  final ValueChanged<DateTime> onDateSelected;
  final Function(Map<String, dynamic>) onTap;
  final RefreshCallback onRefresh;
  final VoidCallback onEmptyAction;

  const _BookingCalendarView({
    required this.appointments,
    required this.selectedDate,
    required this.today,
    required this.selectedDayAppointments,
    required this.onDateSelected,
    required this.onTap,
    required this.onRefresh,
    required this.onEmptyAction,
  });

  @override
  Widget build(BuildContext context) {
    final agenda = [...selectedDayAppointments]
      ..sort((a, b) {
        final aStart = _start(a);
        final bStart = _start(b);
        if (aStart == null || bStart == null) return 0;
        return aStart.compareTo(bStart);
      });
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.of(context).accentPrimary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          0,
          AppSpacing.shellBottomClearance(context),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
            child: _MonthCalendar(
              selectedDate: selectedDate,
              today: today,
              countForDay: _countForDay,
              onDateSelected: onDateSelected,
            ),
          ),
          Divider(
            key: const ValueKey('calendar-agenda-divider'),
            height: 1,
            color: AppColors.of(context).border.withValues(alpha: 0.9),
          ),
          Padding(
            key: const ValueKey('calendar-agenda-header'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageX,
              AppSpacing.md,
              AppSpacing.pageX,
              AppSpacing.sm,
            ),
            child: _DayAgendaHeader(
              date: selectedDate,
              today: today,
              appointments: agenda,
              onAddBooking: onEmptyAction,
            ),
          ),
          if (agenda.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
              child: _CalendarOpenDay(),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
              child: Column(
                children: [
                  for (var index = 0; index < agenda.length; index++) ...[
                    _BookingRecordRow(
                      rowKey: ValueKey(
                        'calendar-booking-row-${agenda[index]['id']}',
                      ),
                      appointment: agenda[index],
                      showTimelineRail: true,
                      showDivider: index != agenda.length - 1,
                      onTap: () => onTap(agenda[index]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  int _countForDay(DateTime day) {
    final start = _dateOnly(day);
    final end = nextBookingCalendarDay(start);
    return appointments.where((appt) {
      final dt = _start(appt);
      return dt != null &&
          !dt.isBefore(start) &&
          dt.isBefore(end) &&
          appt['status'] != 'cancelled';
    }).length;
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime selectedDate;
  final DateTime today;
  final int Function(DateTime day) countForDay;
  final ValueChanged<DateTime> onDateSelected;

  const _MonthCalendar({
    required this.selectedDate,
    required this.today,
    required this.countForDay,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final month = DateTime(selectedDate.year, selectedDate.month);
    final firstGridDay = month.subtract(Duration(days: month.weekday - 1));
    final days = List.generate(42, (index) {
      return firstGridDay.add(Duration(days: index));
    });
    const weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final effectiveToday = _dateOnly(today);

    void moveMonth(int delta) {
      final target = DateTime(selectedDate.year, selectedDate.month + delta, 1);
      final lastDay = DateTime(target.year, target.month + 1, 0).day;
      onDateSelected(
        DateTime(target.year, target.month, selectedDate.day.clamp(1, lastDay)),
      );
    }

    Widget monthButton({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
    }) {
      return Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: IconButton(
            tooltip: label,
            constraints: const BoxConstraints.tightFor(
              width: AppSpacing.minTouch,
              height: AppSpacing.minTouch,
            ),
            style: IconButton.styleFrom(
              backgroundColor: tokens.surface,
              foregroundColor: tokens.textPrimary,
              side: BorderSide(color: tokens.divider),
              shape: const CircleBorder(),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _monthName(month),
                    style: TextStyle(
                      color: AppColors.of(context).t1,
                      fontSize: 25,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${month.year}',
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).modCalendar,
                minimumSize: const Size(58, AppSpacing.minTouch),
              ),
              onPressed: () => onDateSelected(effectiveToday),
              child: const Text('Today'),
            ),
            const SizedBox(width: AppSpacing.xxs),
            monthButton(
              label: 'Previous month',
              icon: LucideIcons.chevronLeft,
              onPressed: () => moveMonth(-1),
            ),
            const SizedBox(width: AppSpacing.xxs),
            monthButton(
              label: 'Next month',
              icon: LucideIcons.chevronRight,
              onPressed: () => moveMonth(1),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: weekdayLabels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: AppColors.of(context).t3,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: AppSpacing.xxs),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 180) return;
            SlateHaptics.tap();
            moveMonth(velocity < 0 ? 1 : -1);
          },
          child: AnimatedSwitcher(
            duration: AppMotion.responsive(context, AppMotion.standard),
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.curve,
            child: GridView.builder(
              key: ValueKey('${month.year}-${month.month}'),
              itemCount: days.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 2,
                crossAxisSpacing: 4,
                mainAxisExtent: 44,
              ),
              itemBuilder: (context, index) {
                final date = days[index];
                final selected = _dateOnly(date) == _dateOnly(selectedDate);
                final isToday = _dateOnly(date) == effectiveToday;
                final inMonth = date.month == month.month;
                final count = countForDay(date);
                final selectedInk = tokens.onAccent;
                void handleTap() {
                  SlateHaptics.tap();
                  onDateSelected(_dateOnly(date));
                }

                return Semantics(
                  button: true,
                  selected: selected,
                  label:
                      '${isToday ? 'Today, ' : ''}${date.day}/${date.month}/${date.year}',
                  value: '$count booking${count == 1 ? '' : 's'}',
                  onTap: handleTap,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: handleTap,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: AppMotion.responsive(
                              context,
                              AppMotion.fast,
                            ),
                            curve: AppMotion.curve,
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.of(context).modCalendar
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: isToday && !selected
                                  ? Border.all(
                                      color: AppColors.of(context).modCalendar,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                color: selected
                                    ? selectedInk
                                    : inMonth
                                    ? AppColors.of(context).t1
                                    : AppColors.of(
                                        context,
                                      ).t3.withValues(alpha: 0.45),
                                fontSize: 14,
                                fontWeight: selected || isToday
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (count > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                count.clamp(1, 3),
                                (dotIndex) => Container(
                                  width: 4,
                                  height: 4,
                                  margin: EdgeInsets.only(
                                    left: dotIndex == 0 ? 0 : 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? selectedInk
                                        : AppColors.of(context).modCalendar,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

String _monthName(DateTime month) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month.month - 1];
}

class _DayAgendaHeader extends StatelessWidget {
  final DateTime date;
  final DateTime today;
  final List<Map<String, dynamic>> appointments;
  final VoidCallback onAddBooking;

  const _DayAgendaHeader({
    required this.date,
    required this.today,
    required this.appointments,
    required this.onAddBooking,
  });

  @override
  Widget build(BuildContext context) {
    final day = _dateOnly(date);
    final effectiveToday = _dateOnly(today);
    final tomorrow = nextBookingCalendarDay(effectiveToday);
    final relativeLabel = day == effectiveToday
        ? 'Today'
        : day == tomorrow
        ? 'Tomorrow'
        : _weekdayName(date);
    final count = appointments.length;

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.of(context).modBg,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              color: AppColors.of(context).modCalendar,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                relativeLabel,
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_fullDate(date)} · $count booking${count == 1 ? '' : 's'}',
                style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onAddBooking,
          icon: const Icon(LucideIcons.plus, size: 15),
          label: const Text('Add booking'),
        ),
      ],
    );
  }
}

class _CalendarOpenDay extends StatelessWidget {
  const _CalendarOpenDay();

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              'OPEN',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
        Container(width: 1, height: 78, color: tokens.divider),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: tokens.divider),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.calendarPlus,
                  color: AppColors.of(context).modCalendar,
                  size: 19,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This day is open',
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Use Add booking to schedule work here.',
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BookingRecordRow extends StatelessWidget {
  final Key? rowKey;
  final Map<String, dynamic> appointment;
  final bool showDivider;
  final bool showTimelineRail;
  final bool showStatusBadge;
  final VoidCallback onTap;

  const _BookingRecordRow({
    this.rowKey,
    required this.appointment,
    required this.onTap,
    this.showDivider = true,
    this.showTimelineRail = false,
    this.showStatusBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final status = appointment['status'] as String? ?? 'scheduled';
    final start = _start(appointment);
    final end = DateTime.tryParse(
      appointment['end_time'] as String? ?? '',
    )?.toLocal();
    final client = appointment['contacts']?['name'] as String? ?? 'Walk-in';
    final service =
        appointment['services']?['name'] as String? ??
        appointment['title'] as String? ??
        'Booking';
    final location = (appointment['location'] as String? ?? '').trim();
    final price = appointment['price'] as num?;
    final notes = appointment['notes'] as String? ?? '';
    final recurrenceRule = appointment['recurrence_rule'] as String?;
    final color = switch (status) {
      'completed' => AppColors.of(context).success,
      'cancelled' => AppColors.of(context).error,
      'no_show' => AppColors.of(context).warning,
      _ => AppColors.of(context).modCalendar,
    };
    final exceptionalStatusLabel = switch (status) {
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      'no_show' => 'No show',
      _ => null,
    };
    final statusLabel = showStatusBadge
        ? switch (status) {
            'completed' => 'Completed',
            'cancelled' => 'Cancelled',
            'no_show' => 'No show',
            _ => 'Scheduled',
          }
        : exceptionalStatusLabel;

    return Semantics(
      button: true,
      label:
          '${start == null ? 'Booking' : _calendarTime(start)}, $client, $service${statusLabel == null ? '' : ', $statusLabel'}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 54,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      start == null ? '--:--' : _calendarTime(start),
                      style: TextStyle(
                        color: AppColors.of(context).t1,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (end != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _calendarTime(end),
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 10,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              color: showTimelineRail ? tokens.divider : Colors.transparent,
            ),
            Expanded(
              child: WorkloopListRow(
                key: rowKey,
                onTap: onTap,
                flat: true,
                showDivider: showDivider,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                leading: Container(
                  width: 3,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadius.capsule),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        client,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (price != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        formatPounds(price),
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [service, if (location.isNotEmpty) location].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).t2,
                        fontSize: 12,
                      ),
                    ),
                    if (statusLabel != null) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _BookingMetaLabel(
                            label: statusLabel,
                            icon: status == 'completed'
                                ? LucideIcons.checkCircle
                                : status == 'cancelled'
                                ? LucideIcons.xCircle
                                : status == 'no_show'
                                ? LucideIcons.alertCircle
                                : LucideIcons.clock,
                            color: color,
                          ),
                          if (recurrenceRule != null &&
                              recurrenceRule.isNotEmpty)
                            _BookingMetaLabel(
                              label: 'Repeats',
                              icon: LucideIcons.repeat,
                              color: AppColors.of(context).t3,
                            ),
                        ],
                      ),
                    ] else if (recurrenceRule != null &&
                        recurrenceRule.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      _BookingMetaLabel(
                        label: 'Repeats',
                        icon: LucideIcons.repeat,
                        color: AppColors.of(context).t3,
                      ),
                    ],
                    if ((status == 'cancelled' || status == 'no_show') &&
                        notes.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        status == 'cancelled'
                            ? 'Cancelled: $notes'
                            : 'No show: $notes',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.of(
                            context,
                          ).error.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.of(context).t3,
                  size: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _weekdayName(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return weekdays[date.weekday - 1];
}

String _fullDate(DateTime date) =>
    '${date.day} ${_monthName(date)} ${date.year}';

String _calendarTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class _BookingMetaLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _BookingMetaLabel({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
