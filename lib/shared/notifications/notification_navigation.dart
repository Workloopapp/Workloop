import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../widgets/slate_ui.dart';

/// A pageless detail, sheet or editor can sit above the entity's GoRouter page.
/// Its route name identifies the currently presented record, independently of
/// the parent URL, so another record can open without removing an active draft.
Route<dynamic>? workloopNotificationPresentedRoute(GoRouter router) {
  final observers =
      router.routerDelegate.navigatorKey.currentState?.widget.observers;
  for (final observer in observers ?? <NavigatorObserver>[]) {
    if (observer is WorkloopNavigationObserver) {
      return observer.topRoute;
    }
  }
  return null;
}
