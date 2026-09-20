import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import 'getting_started_store.dart';

const _steps = [
  (
    destination: 'Today',
    title: 'Know what needs you next',
    description:
        'Your next booking and anything needing attention live here. Open a booking to see its details and take the next step.',
    tip: 'Start your day here. Your real work appears as you add it.',
    illustration: WorkloopIllustrationKind.calendar,
    action: 'Open Today',
    route: '/home',
  ),
  (
    destination: 'Clients',
    title: 'Keep each client together',
    description:
        'Save contact details once, then find their bookings, notes and payment history in one place.',
    tip: 'Start with one real client. A name is enough to begin.',
    illustration: WorkloopIllustrationKind.clients,
    action: 'Add a client',
    route: '/clients/new',
  ),
  (
    destination: 'Work',
    title: 'Turn plans into bookings',
    description:
        'Your schedule, tasks and notes share this space. A booking connects a client, service and time; repeat it weekly when the work is regular.',
    tip:
        'Open a booking to create its invoice. Existing client and service details come with it.',
    illustration: WorkloopIllustrationKind.tools,
    action: 'Create a booking',
    route: '/bookings/new',
  ),
  (
    destination: 'Money',
    title: 'From agreed work to getting paid',
    description:
        'Use a quote to agree the work and price, then an invoice to request payment. A deposit is part of that invoice, paid in advance. Save receipts with expenses and record business mileage in Spent.',
    tip:
        'Record money only when it is received. Tax planning uses reviewed figures; it does not file a tax return.',
    illustration: WorkloopIllustrationKind.receipt,
    action: 'Open Money',
    route: '/payments',
  ),
  (
    destination: 'Business',
    title: 'Make it easy to book you',
    description:
        'Keep your services, prices, working hours and contact details current. Invoice setup saves the legal details and payment instructions your new documents will use.',
    tip:
        'You can finish invoice setup when you need your first document. Return to this guide in Settings at any time.',
    illustration: WorkloopIllustrationKind.storefront,
    action: 'Review my business',
    route: '/business',
  ),
];

/// Resumes an interrupted guide; completed guides open at the beginning.
/// No workspace data, email preferences or completion triggers are changed.
Future<void> showWorkloopGettingStartedGuide(
  BuildContext context, {
  required String userId,
  required String workspaceId,
  bool replay = false,
}) async {
  if (userId.isEmpty || workspaceId.isEmpty) return;
  final scope = (userId: userId, workspaceId: workspaceId);
  final store = ProviderScope.containerOf(
    context,
  ).read(gettingStartedStoreProvider);
  final progress = await store.read(scope);
  if (!context.mounted) return;
  final nextStep = replay || progress.completed ? 0 : progress.nextStep;
  // Consume the introduction before showing it. Skip, swipe-dismiss and app
  // restarts must not repeatedly interrupt the owner's real work.
  await store.write(scope, GettingStartedProgress(nextStep: nextStep));
  if (!context.mounted) return;
  final route = await showWorkloopBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        GettingStartedGuide(scope: scope, store: store, initialStep: nextStep),
  );
  if (route == null || !context.mounted) return;
  if (route == '/clients/new' || route == '/bookings/new') {
    await context.push(route);
  } else {
    context.go(route);
  }
}

/// Wrap the verified MainShell, with the current account and workspace IDs.
/// Existing workspaces without a prepared introduction remain untouched.
class FirstUseGuideGate extends StatefulWidget {
  final String userId;
  final String workspaceId;
  final Widget child;

  const FirstUseGuideGate({
    super.key,
    required this.userId,
    required this.workspaceId,
    required this.child,
  });

  @override
  State<FirstUseGuideGate> createState() => _FirstUseGuideGateState();
}

class _FirstUseGuideGateState extends State<FirstUseGuideGate> {
  @override
  void initState() {
    super.initState();
    _scheduleIntroduction();
  }

  @override
  void didUpdateWidget(covariant FirstUseGuideGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.workspaceId != widget.workspaceId) {
      _scheduleIntroduction();
    }
  }

  void _scheduleIntroduction() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final userId = widget.userId;
      final workspaceId = widget.workspaceId;
      final store = ProviderScope.containerOf(
        context,
      ).read(gettingStartedStoreProvider);
      final progress = await store.read((
        userId: userId,
        workspaceId: workspaceId,
      ));
      if (!mounted ||
          userId != widget.userId ||
          workspaceId != widget.workspaceId ||
          !progress.pendingIntroduction ||
          progress.completed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      await showWorkloopGettingStartedGuide(
        context,
        userId: userId,
        workspaceId: workspaceId,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class GettingStartedGuide extends StatefulWidget {
  final GettingStartedScope scope;
  final GettingStartedStore store;
  final int initialStep;

  const GettingStartedGuide({
    super.key,
    required this.scope,
    required this.store,
    this.initialStep = 0,
  });

  @override
  State<GettingStartedGuide> createState() => _GettingStartedGuideState();
}

class _GettingStartedGuideState extends State<GettingStartedGuide> {
  late int _step;
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep.clamp(0, _steps.length - 1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _move(int step) async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.store.write(
      widget.scope,
      GettingStartedProgress(nextStep: step),
    );
    if (!mounted) return;
    setState(() {
      _step = step;
      _busy = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _close({String? route, bool complete = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.store.write(
      widget.scope,
      GettingStartedProgress(
        nextStep: route == null
            ? _step
            : (_step + 1).clamp(0, _steps.length - 1),
        completed: complete || (route != null && _step == _steps.length - 1),
      ),
    );
    if (mounted) Navigator.of(context).pop(route);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final text = Theme.of(context).textTheme;
    final step = _steps[_step];
    return SlateSheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Getting started', style: text.titleLarge),
                  ),
                  WorkloopIconButton(
                    icon: LucideIcons.x,
                    semanticLabel: 'Close getting started guide',
                    onTap: () => _close(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A quick look around. Try a step now, or come back through Settings.',
                style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                liveRegion: true,
                child: WorkloopCaption(
                  '${_step + 1} of ${_steps.length} · ${step.destination}',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: WorkloopIllustration(kind: step.illustration, size: 64),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(step.title, style: text.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                step.description,
                style: text.bodyLarge?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                step.tip,
                style: text.bodyMedium?.copyWith(
                  color: tokens.textTertiary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              WorkloopPrimaryButton(
                label: _step == _steps.length - 1 ? 'Finish guide' : 'Next',
                onPressed: _busy
                    ? null
                    : () => _step == _steps.length - 1
                          ? _close(complete: true)
                          : _move(_step + 1),
              ),
              const SizedBox(height: AppSpacing.sm),
              WorkloopPrimaryButton(
                label: step.action,
                secondary: true,
                onPressed: _busy ? null : () => _close(route: step.route),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  if (_step > 0)
                    WorkloopTextButton(
                      label: 'Back',
                      onPressed: _busy ? null : () => _move(_step - 1),
                    ),
                  WorkloopTextButton(
                    label: 'Skip for now',
                    onPressed: _busy ? null : () => _close(),
                  ),
                  if (_step > 1)
                    WorkloopTextButton(
                      label: 'Start over',
                      onPressed: _busy ? null : () => _move(0),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
