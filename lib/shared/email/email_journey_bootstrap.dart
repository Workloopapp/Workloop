import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/supabase_client_provider.dart';
import 'email_preferences_repository.dart';

class WorkloopEmailJourneyBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  const WorkloopEmailJourneyBootstrap({super.key, required this.child});
  @override
  ConsumerState<WorkloopEmailJourneyBootstrap> createState() =>
      _WorkloopEmailJourneyBootstrapState();
}

class _WorkloopEmailJourneyBootstrapState
    extends ConsumerState<WorkloopEmailJourneyBootstrap>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _auth;
  Timer? _timer;
  bool _busy = false;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = ref
        .read(supabaseClientProvider)
        .auth
        .onAuthStateChange
        .listen((_) => unawaited(_touch()));
    _timer = Timer.periodic(const Duration(hours: 1), (_) {
      if (_active) unawaited(_touch());
    });
    unawaited(_touch());
  }

  Future<void> _touch() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      await ref.read(emailPreferencesRepositoryProvider).recordActivity();
    } catch (_) {
      /* Email/activity reporting must never block access to the app. */
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_touch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
