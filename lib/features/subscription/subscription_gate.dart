import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/slate_ui.dart';
import '../settings/widgets/settings_account_tab.dart';
import 'store_purchase_service.dart';
import 'subscription_access.dart';
import 'subscription_screen.dart';

class SubscriptionGate extends ConsumerStatefulWidget {
  const SubscriptionGate({
    super.key,
    required this.userId,
    required this.child,
  });
  final String userId;
  final Widget child;
  @override
  ConsumerState<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends ConsumerState<SubscriptionGate>
    with WidgetsBindingObserver {
  Timer? _expiry;
  bool _opened = false;
  bool _expired = false;
  bool _presentedOffer = false;
  SubscriptionAccess? _observedAccess;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SubscriptionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId) {
      _expiry?.cancel();
      _observedAccess = null;
      _opened = false;
      _expired = false;
      _presentedOffer = false;
    }
  }

  void _watchExpiry(SubscriptionAccess value) {
    if (identical(value, _observedAccess)) return;
    _observedAccess = value;
    _expiry?.cancel();
    _expired = false;
    final end = value.accessEndsAt;
    if (end == null || !value.hasAccess) return;
    final remaining = end.difference(value.estimatedServerNow);
    final userId = widget.userId;
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted || widget.userId != userId) return;
      // Do not keep stale access interactive while the expiry refresh runs.
      setState(() => _expired = true);
      ref.invalidate(subscriptionAccessProvider(userId));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(subscriptionAccessProvider(widget.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = subscriptionAccessProvider(widget.userId);
    final access = ref.watch(provider);
    ref.watch(storePurchaseServiceProvider(widget.userId));
    final value = access.value;
    if (value != null && !access.isLoading && !access.hasError) {
      _watchExpiry(value);
    }
    final blocked =
        value == null || !value.hasAccess || access.hasError || _expired;
    if (value != null &&
        !value.hasAccess &&
        !access.hasError &&
        !access.isLoading) {
      _presentedOffer = true;
    }
    if (!blocked && !access.isLoading && _presentedOffer) {
      _presentedOffer = false;
      if (value.hasStoreSubscription) {
        final userId = widget.userId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || userId != widget.userId) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                value.isStoreTrial
                    ? 'Your free month has started. Welcome to Workloop.'
                    : 'Your Workloop subscription is ready.',
              ),
            ),
          );
        });
      }
    }
    if (!blocked) _opened = true;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_opened)
          ExcludeFocus(
            excluding: blocked,
            child: ExcludeSemantics(
              excluding: blocked,
              child: IgnorePointer(
                ignoring: blocked,
                child: KeyedSubtree(
                  key: ValueKey(widget.userId),
                  child: widget.child,
                ),
              ),
            ),
          ),
        if (blocked)
          Positioned.fill(
            child: value != null && !value.hasAccess
                ? const SubscriptionScreen(canClose: false)
                : Scaffold(
                    body: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (access.hasError) ...[
                                  const Text(
                                    'We could not check your Workloop access. Your records are safe.',
                                  ),
                                  const SizedBox(height: 16),
                                  WorkloopPrimaryButton(
                                    label: 'Try again',
                                    onPressed: () => ref.invalidate(provider),
                                  ),
                                  WorkloopTextButton(
                                    label: 'Manage account or sign out',
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => Scaffold(
                                          appBar: AppBar(
                                            title: const Text('Your account'),
                                          ),
                                          body: const SettingsAccountTab(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else
                                  const CircularProgressIndicator(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}
