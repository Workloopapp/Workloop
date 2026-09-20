enum WorkloopNotificationEntity { booking, bookingRequest, payment, task, note }

const _notificationStaticRoutes = <String>{
  '/home',
  '/notifications',
  '/booking-requests',
  '/payments',
  '/work',
  '/tasks',
  '/notes',
  '/clients',
};

final _notificationEntityRoute = RegExp(
  r'^/(bookings|booking-requests|payments|tasks|notes)/'
  r'([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$',
  caseSensitive: false,
);

/// Returns only routes that are safe to open inside an authenticated Workloop
/// session. Entity IDs are UUIDs and are resolved through workspace-scoped
/// providers, so a crafted notification cannot cross the RLS boundary.
String? workloopNotificationRoute(String? value) {
  final route = value?.trim() ?? '';
  if (route.isEmpty || !route.startsWith('/')) return null;
  final uri = Uri.tryParse(route);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  if (_notificationStaticRoutes.contains(uri.path)) return uri.path;
  return _notificationEntityRoute.hasMatch(uri.path) ? uri.path : null;
}

/// Older alerts sometimes stored only a collection name. Never imply that
/// such a link identifies a record; the inbox retains the original update.
String? workloopNotificationDestination(String? value) {
  final route = workloopNotificationRoute(value);
  if (route == null) return null;
  if (_notificationEntityRoute.hasMatch(route) ||
      route == '/home' ||
      route == '/notifications') {
    return route;
  }
  return '/notifications';
}

bool workloopNotificationHasMissingRecordLink(String type, String? value) {
  const recordTypes = {
    'booking',
    'new_booking',
    'booking_request',
    'no_show',
    'payment',
    'payment_received',
    'invoice_overdue',
    'task',
    'task_due',
    'note',
    'note_created',
    'lead_followup',
  };
  return recordTypes.contains(type) &&
      !_notificationEntityRoute.hasMatch(
        workloopNotificationRoute(value) ?? '',
      );
}

String workloopNotificationEntityRoute(
  WorkloopNotificationEntity entity,
  String id,
) {
  final root = switch (entity) {
    WorkloopNotificationEntity.booking => 'bookings',
    WorkloopNotificationEntity.bookingRequest => 'booking-requests',
    WorkloopNotificationEntity.payment => 'payments',
    WorkloopNotificationEntity.task => 'tasks',
    WorkloopNotificationEntity.note => 'notes',
  };
  return '/$root/${id.trim()}';
}
