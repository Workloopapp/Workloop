import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/workloop_capabilities.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/payments/tap_to_pay_service.dart';
import '../../shared/repositories/stripe_payments_repository.dart';
import '../../shared/utils/currency_format.dart';
import '../../shared/utils/workflow_idempotency.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';

String friendlyPaymentError(Object error) {
  if (error is PostgrestException) {
    return error.code == 'P0001'
        ? (_safePaymentMessage(error.message) ??
              'Could not send this payment email. Please try again.')
        : 'Payments are temporarily unavailable. Please try again.';
  }
  if (error is FunctionException) {
    final details = error.details;
    final payload = details is Map
        ? Map<String, dynamic>.from(details)
        : const <String, dynamic>{};
    final code = payload['code']?.toString();
    if (code == 'collection_in_progress' &&
        payload['error']?.toString() ==
            'Payment request key was already used') {
      return 'This payment has changed. Close this sheet and refresh Money before trying again.';
    }
    if (code == 'platform_configuration_required') {
      return 'Payment setup is being finalised. Please try again shortly.';
    }
    if (error.status == 401) {
      return 'Your session has expired. Sign in again to continue.';
    }
    if (error.status == 403) {
      return 'You do not have access to manage payments for this business.';
    }
    final message = _safePaymentMessage(payload['error']);
    if (message != null) return message;
    return 'Payments are temporarily unavailable. Please try again.';
  }
  final text = error.toString().replaceFirst(
    RegExp(r'^(?:Bad state|\w+(?:Exception)?):\s*'),
    '',
  );
  final safeText = _safePaymentMessage(text);
  return safeText ?? 'Payments are temporarily unavailable. Please try again.';
}

String? _safePaymentMessage(Object? value) {
  final message = value?.toString().trim() ?? '';
  final normalized = message.toLowerCase();
  if (message.isEmpty || message.length > 200) return null;
  if (normalized.contains('functionexception') ||
      normalized.contains('reasonphrase') ||
      normalized.contains('http://') ||
      normalized.contains('https://') ||
      normalized.contains('dashboard.stripe.com') ||
      normalized.contains('sk_live_') ||
      normalized.contains('whsec_')) {
    return null;
  }
  return message;
}

bool isValidReceiptEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return true;
  if (email.length > 254) return false;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

/// Parse pounds as decimal digits, avoiding floating-point rounding and NaN.
int? parseRefundAmountMinor(String input, int refundableMinor) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final pounds = int.tryParse(match.group(1)!);
  if (pounds == null || pounds > refundableMinor ~/ 100) return null;
  final pennies = int.parse((match.group(2) ?? '').padRight(2, '0'));
  final amount = pounds * 100 + pennies;
  return amount > 0 && amount <= refundableMinor ? amount : null;
}

enum PaymentSetupAction { viewOwed }

String contactlessUnavailableMessage(
  TargetPlatform platform, {
  String? reason,
}) {
  if (!WorkloopCapabilities.tapToPayEnabled) {
    return 'Tap to Pay is not enabled in this version of Workloop. Use a card payment link.';
  }
  return _safePaymentMessage(reason) ??
      'Contactless payments are not available on this phone. Use a card payment link.';
}

Future<bool> showPaymentCollectionSheet({
  required BuildContext context,
  required Payment payment,
}) async {
  if (!WorkloopCapabilities.paymentCollectionEnabled) return false;
  return await showWorkloopBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _PaymentCollectionSheet(payment: payment),
      ) ??
      false;
}

Future<PaymentSetupAction?> showPaymentSetupSheet({
  required BuildContext context,
  required String workspaceId,
}) {
  if (!WorkloopCapabilities.paymentCollectionEnabled) {
    return showWorkloopBottomSheet<PaymentSetupAction>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SlateSheetFrame(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Card & contactless payments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Card payment collection is not enabled in this version of Workloop. You can still record payments you receive by cash or bank transfer.',
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Tap to Pay also requires a supported phone and payment-enabled version of Workloop.',
              ),
              const SizedBox(height: AppSpacing.lg),
              SlateButton(
                label: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
  return showWorkloopBottomSheet<PaymentSetupAction>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaymentCollectionSheet(workspaceId: workspaceId),
  );
}

class PaymentSetupCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;

  const PaymentSetupCard({
    super.key,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    if (compact) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        minTileHeight: AppSpacing.minTouch,
        leading: Icon(
          LucideIcons.smartphoneNfc,
          color: tokens.accentInk,
          size: 20,
        ),
        title: Text(
          'Card & contactless payments',
          style: TextStyle(fontSize: 13, color: tokens.textPrimary),
        ),
        trailing: Icon(
          LucideIcons.chevronRight,
          color: tokens.textSecondary,
          size: 18,
        ),
        onTap: onTap,
      );
    }
    return SlateSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(LucideIcons.smartphoneNfc, color: tokens.accentInk, size: 22),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Card & contactless payments',
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Take card payments by link, check Tap to Pay, and manage payouts.',
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.xs),
          Icon(
            LucideIcons.chevronRight,
            color: AppColors.of(context).t3,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _PaymentCollectionSheet extends ConsumerStatefulWidget {
  final Payment? payment;
  final String? workspaceId;

  const _PaymentCollectionSheet({this.payment, this.workspaceId});

  @override
  ConsumerState<_PaymentCollectionSheet> createState() =>
      _PaymentCollectionSheetState();
}

class _PaymentCollectionSheetState
    extends ConsumerState<_PaymentCollectionSheet> {
  late Future<StripeAccountStatus> _status;
  late Future<TapToPayAvailability> _tapAvailability;
  Future<List<Map<String, dynamic>>>? _transactions;
  bool _working = false;
  bool _linkCopied = false;
  String? _error;
  late final TextEditingController _receiptEmailController;
  String? _paymentLinkIdempotencyKey;
  String? _terminalPaymentIdempotencyKey;
  Payment? _linkPayment;
  Payment? _terminalPayment;
  Payment? _refreshedPayment;
  String? _terminalReceiptEmail;
  final Map<String, String> _refundIdempotencyKeys = {};

  String get _workspaceId =>
      widget.payment?.workspaceId ?? widget.workspaceId ?? '';

  bool get _sameWorkspace =>
      mounted && ref.read(workspaceIdProvider).value == _workspaceId;

  void _requireWorkspace() {
    if (!_sameWorkspace) {
      throw StateError(
        'Your business changed. Close this sheet and reopen the payment.',
      );
    }
  }

  Payment? get _displayPayment {
    for (final payment
        in ref.read(invoicesProvider).value ?? const <Payment>[]) {
      if (payment.id == widget.payment?.id &&
          payment.workspaceId == _workspaceId) {
        return payment;
      }
    }
    return _refreshedPayment ?? widget.payment;
  }

  Future<Payment> _latestPayment() async {
    _requireWorkspace();
    final reviewedAmount = _displayPayment?.collectionAmount;
    final payments = await ref.refresh(invoicesProvider.future);
    _requireWorkspace();
    for (final payment in payments) {
      if (payment.id == widget.payment?.id &&
          payment.workspaceId == _workspaceId) {
        if (payment.outstandingAmount <= 0) {
          throw StateError('There is no outstanding balance to collect.');
        }
        setState(() => _refreshedPayment = payment);
        if (reviewedAmount != payment.collectionAmount) {
          throw StateError(
            'The balance changed. Check the updated amount, then try again.',
          );
        }
        return payment;
      }
    }
    throw StateError(
      'This payment is no longer available. Close this sheet and refresh Money.',
    );
  }

  @override
  void initState() {
    super.initState();
    _receiptEmailController = TextEditingController(
      text: widget.payment?.clientEmail ?? '',
    );
    _status = _repository.accountStatus(_workspaceId);
    _tapAvailability = tapToPayService.availability();
    if (widget.payment != null) {
      _transactions = _repository.transactionsForInvoice(
        _workspaceId,
        widget.payment!.id,
      );
    }
  }

  @override
  void dispose() {
    _receiptEmailController.dispose();
    super.dispose();
  }

  StripePaymentsRepository get _repository =>
      ref.read(stripePaymentsRepositoryProvider);

  void _refreshStatus() {
    if (!_sameWorkspace) return;
    setState(() {
      _error = null;
      _status = _repository.accountStatus(_workspaceId);
    });
  }

  Future<void> _startOnboarding() async {
    await _run(() async {
      final link = await _repository.createOnboardingLink(_workspaceId);
      _requireWorkspace();
      if (!await launchUrl(link, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open Stripe setup.');
      }
    });
  }

  Future<void> _openDashboard() async {
    await _run(() async {
      final link = await _repository.createDashboardLink(_workspaceId);
      _requireWorkspace();
      if (!await launchUrl(link, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open Stripe.');
      }
    });
  }

  Future<void> _openReceipt(Map<String, dynamic> transaction) async {
    final receipt = Uri.tryParse(transaction['receipt_url'] as String? ?? '');
    if (receipt == null || receipt.scheme != 'https') return;
    await _run(() async {
      if (!await launchUrl(receipt, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open the Stripe receipt.');
      }
    });
  }

  Future<PaymentLinkResult> _loadPaymentLinkResult() async {
    _requireWorkspace();
    if (_paymentLinkIdempotencyKey == null) {
      _linkPayment = await _latestPayment();
      _paymentLinkIdempotencyKey = createWorkflowIdempotencyKey();
    }
    final payment = _linkPayment!;
    final result = await _repository.createPaymentLink(
      workspaceId: payment.workspaceId,
      invoiceId: payment.id,
      amountMinor: payment.hasDeposit
          ? (payment.collectionAmount * 100).round()
          : null,
      idempotencyKey: _paymentLinkIdempotencyKey!,
    );
    _requireWorkspace();
    return result;
  }

  Future<Uri> _loadPaymentLink() async => (await _loadPaymentLinkResult()).url;

  Future<void> _emailPaymentRequest() async {
    await _run(() async {
      final link = await _loadPaymentLinkResult();
      final preview = await _repository.paymentRequestEmail(
        link.transactionId,
        send: false,
      );
      _requireWorkspace();
      if (!mounted) return;
      final email = preview['email'] as String;
      final amount = (preview['amount_minor'] as num).toDouble() / 100;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Email payment request?'),
          content: Text(
            'Send a request for ${formatPounds(amount)} to $email. The email includes a secure Stripe payment link.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send email'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      _requireWorkspace();
      final result = await _repository.paymentRequestEmail(
        link.transactionId,
        send: true,
        expectedEmail: email,
      );
      _requireWorkspace();
      if (!mounted) return;
      final status = result['status'];
      if (status == 'failed' || status == 'cancelled') {
        throw StateError(
          'This payment email could not be sent. Create a fresh payment link or contact support.',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'sent'
                ? 'This payment request has already been emailed'
                : 'Payment request queued for $email',
          ),
        ),
      );
    });
  }

  Future<void> _sharePaymentLink() async {
    await _run(() async {
      final link = await _loadPaymentLink();
      _requireWorkspace();
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: 'Payment link for ${_linkPayment!.number}: $link',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    });
  }

  Future<void> _copyPaymentLink() async {
    await _run(() async {
      final link = await _loadPaymentLink();
      _requireWorkspace();
      await Clipboard.setData(ClipboardData(text: link.toString()));
      _requireWorkspace();
      if (!mounted) return;
      setState(() => _linkCopied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Secure payment link copied')),
      );
    });
  }

  Future<void> _takeContactlessPayment() async {
    await _run(() async {
      final receiptEmail = _receiptEmailController.text.trim();
      if (!isValidReceiptEmail(receiptEmail)) {
        throw StateError('Enter a valid receipt email or leave it blank.');
      }
      final availability = await tapToPayService.availability();
      _requireWorkspace();
      if (!availability.supported) {
        throw StateError(
          'Tap to Pay is not enabled for this Workloop build yet. '
          'You can still copy a secure payment link.',
        );
      }
      if (_terminalPaymentIdempotencyKey == null) {
        _terminalPayment = await _latestPayment();
        _terminalReceiptEmail = receiptEmail.isEmpty ? null : receiptEmail;
        _terminalPaymentIdempotencyKey = createWorkflowIdempotencyKey();
      }
      final payment = _terminalPayment!;
      final request = await _repository.createTerminalPayment(
        workspaceId: payment.workspaceId,
        invoiceId: payment.id,
        amountMinor: payment.hasDeposit
            ? (payment.collectionAmount * 100).round()
            : null,
        receiptEmail: _terminalReceiptEmail,
        idempotencyKey: _terminalPaymentIdempotencyKey!,
      );
      _requireWorkspace();
      final result = await tapToPayService.collect(
        clientSecret: request.clientSecret,
        locationId: request.locationId,
        connectionTokenLoader: () {
          _requireWorkspace();
          return _repository.createConnectionToken(payment.workspaceId);
        },
      );
      if (result.status != 'succeeded') {
        throw StateError('Stripe is still processing this payment.');
      }
      _requireWorkspace();
      if (!mounted) return;
      Navigator.pop(context, true);
    });
  }

  Future<void> _refundTransaction(Map<String, dynamic> transaction) async {
    if (!_sameWorkspace || _working) return;
    final amount = (transaction['amount_minor'] as num?)?.toInt() ?? 0;
    final refunded =
        (transaction['amount_refunded_minor'] as num?)?.toInt() ?? 0;
    final refundable = amount - refunded;
    if (refundable <= 0) return;
    final controller = TextEditingController(
      text: (refundable / 100).toStringAsFixed(2),
    );
    final route = DialogRoute<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refund card payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Up to ${formatPounds(refundable / 100)} can be refunded.'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  label: WorkloopFieldLabel(
                    'Refund amount (£)',
                    isRequired: true,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final minor = parseRefundAmountMinor(controller.text, refundable);
              if (minor == null) return;
              Navigator.pop(dialogContext, minor);
            },
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    final confirmed = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (confirmed == null || !_sameWorkspace) return;
    final transactionId = transaction['id'] as String;
    final refundOperation = '$transactionId:$confirmed';
    await _run(() async {
      await _repository.refund(
        workspaceId: _workspaceId,
        transactionId: transactionId,
        amountMinor: confirmed,
        idempotencyKey: _refundIdempotencyKeys.putIfAbsent(
          refundOperation,
          createWorkflowIdempotencyKey,
        ),
      );
      _requireWorkspace();
      if (!mounted) return;
      Navigator.pop(context, true);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working || !_sameWorkspace) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyPaymentError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceIdProvider).value;
    if (workspace != _workspaceId) {
      return SlateSheetFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your business changed. Close this sheet and reopen the payment.',
            ),
            SlateButton(
              label: 'Close',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
    ref.watch(invoicesProvider);
    final payment = _displayPayment;
    final media = MediaQuery.of(context);
    final availableHeight =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.top -
                AppSpacing.xl * 3)
            .clamp(240.0, media.size.height)
            .toDouble();
    return AnimatedPadding(
      duration: AppMotion.responsive(context, AppMotion.fast),
      curve: AppMotion.curve,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SlateSheetFrame(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: FutureBuilder<StripeAccountStatus>(
              future: _status,
              builder: (context, snapshot) {
                final status = snapshot.data;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Get paid',
                            style: TextStyle(
                              color: AppColors.of(context).t1,
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (status != null) _ModeLabel(mode: status.mode),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    if (payment == null)
                      Text(
                        'Connect Stripe to take card payments. Open an unpaid Money item to send a secure link or use Tap to Pay when available.',
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      )
                    else
                      _PaymentSummary(payment: payment),
                    const SizedBox(height: AppSpacing.lg),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const SlateLoadingBlock(height: 150, radius: AppRadius.md)
                    else if (snapshot.hasError)
                      SlateErrorState(
                        message: 'Could not check payment setup',
                        onRetry: _refreshStatus,
                      )
                    else if (status == null ||
                        (!status.ready &&
                            (payment?.stripeAmountPaid ?? 0) <= 0))
                      _buildSetup(status)
                    else
                      _buildReady(status),
                    if (status?.mode == 'test') ...[
                      const SizedBox(height: AppSpacing.md),
                      const _TestModeNote(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      SlateErrorState(message: _error!),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Stripe processing fees apply. Workloop adds no platform fee. Card details never pass through Workloop.',
                      style: TextStyle(
                        color: AppColors.of(context).t3,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SlateButton(
                      label: 'Close',
                      secondary: true,
                      onPressed: _working ? null : () => Navigator.pop(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetup(StripeAccountStatus? status) {
    final started = status?.connected == true;
    return Column(
      children: [
        _buildContactlessStatus(),
        const SizedBox(height: AppSpacing.lg),
        SlateButton(
          label: _working
              ? 'Opening Stripe...'
              : started
              ? 'Continue Stripe setup'
              : 'Set up secure payments',
          icon: LucideIcons.shieldCheck,
          onPressed: _working ? null : _startOnboarding,
        ),
        if (started) ...[
          const SizedBox(height: AppSpacing.sm),
          SlateButton(
            label: 'I’ve finished setup',
            secondary: true,
            onPressed: _working ? null : _refreshStatus,
          ),
        ],
      ],
    );
  }

  Widget _buildContactlessStatus() {
    return FutureBuilder<TapToPayAvailability>(
      future: _tapAvailability,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SlateLoadingBlock(height: 64, radius: AppRadius.md);
        }
        final available = snapshot.data?.supported == true;
        return _PaymentStatusRow(
          icon: LucideIcons.smartphoneNfc,
          iconColor: available
              ? AppColors.of(context).success
              : AppColors.of(context).t3,
          title: 'Contactless payments',
          detail: available
              ? 'This phone supports Tap to Pay. A verified Stripe account is required.'
              : contactlessUnavailableMessage(
                  Theme.of(context).platform,
                  reason: snapshot.data?.reason,
                ),
          status: available ? 'Supported' : 'Unavailable',
        );
      },
    );
  }

  Widget _buildReady(StripeAccountStatus status) {
    final payment = _displayPayment;
    if (payment == null) {
      return Column(
        children: [
          _PaymentStatusRow(
            icon: LucideIcons.circleCheck,
            iconColor: AppColors.of(context).success,
            title: 'Stripe is connected',
            detail: 'Secure payment links and payouts are ready.',
          ),
          const SizedBox(height: AppSpacing.lg),
          SlateButton(
            label: 'View payments to collect',
            icon: LucideIcons.arrowRight,
            onPressed: _working
                ? null
                : () => Navigator.pop(context, PaymentSetupAction.viewOwed),
          ),
          const SizedBox(height: AppSpacing.sm),
          SlateButton(
            label: 'Open Stripe payouts',
            secondary: true,
            onPressed: _working ? null : _openDashboard,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildContactlessStatus(),
        ],
      );
    }
    if (_transactions != null) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: _transactions,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SlateLoadingBlock(height: 112, radius: AppRadius.md);
          }
          if (snapshot.hasError) {
            return SlateErrorState(
              message: 'Could not load Stripe payment details',
              onRetry: () {
                setState(() {
                  _transactions = _repository.transactionsForInvoice(
                    _workspaceId,
                    payment.id,
                  );
                });
              },
            );
          }
          final transactions = snapshot.data ?? const [];
          final completed = transactions.where((transaction) {
            return const [
              'succeeded',
              'partially_refunded',
              'refunded',
            ].contains(transaction['status']);
          }).toList();
          final refundable = transactions.where((transaction) {
            final amount = (transaction['amount_minor'] as num?)?.toInt() ?? 0;
            final refunded =
                (transaction['amount_refunded_minor'] as num?)?.toInt() ?? 0;
            return amount > refunded &&
                const [
                  'succeeded',
                  'partially_refunded',
                ].contains(transaction['status']);
          }).toList();
          final receiptTransaction = completed
              .cast<Map<String, dynamic>?>()
              .firstWhere(
                (transaction) =>
                    Uri.tryParse(
                      transaction?['receipt_url'] as String? ?? '',
                    )?.scheme ==
                    'https',
                orElse: () => null,
              );
          if (completed.isEmpty) return _buildCollectionOptions();
          return Column(
            children: [
              if (status.ready && payment.outstandingAmount > 0) ...[
                _buildCollectionOptions(),
                const SizedBox(height: AppSpacing.lg),
              ],
              _PaymentStatusRow(
                icon: LucideIcons.circleCheck,
                iconColor: AppColors.of(context).success,
                title: refundable.isEmpty
                    ? 'Card payment refunded'
                    : 'Card payment received',
                detail: refundable.isEmpty
                    ? 'Stripe has returned the full collected amount.'
                    : 'Recorded in Money and reconciled by Stripe.',
                status: refundable.isEmpty ? 'Refunded' : 'Paid',
              ),
              if (receiptTransaction != null) ...[
                const SizedBox(height: AppSpacing.md),
                SlateButton(
                  label: 'View Stripe receipt',
                  icon: LucideIcons.receiptText,
                  secondary: true,
                  onPressed: _working
                      ? null
                      : () => _openReceipt(receiptTransaction),
                ),
              ],
              if (refundable.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                SlateButton(
                  label: _working ? 'Refunding...' : 'Refund card payment',
                  icon: LucideIcons.undo2,
                  secondary: true,
                  onPressed: _working
                      ? null
                      : () => _refundTransaction(refundable.first),
                ),
              ],
            ],
          );
        },
      );
    }
    return _buildCollectionOptions();
  }

  Widget _buildCollectionOptions() {
    return FutureBuilder<TapToPayAvailability>(
      future: _tapAvailability,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SlateLoadingBlock(height: 132, radius: AppRadius.md);
        }
        return _buildCollectionMethods(
          contactlessAvailable: snapshot.data?.supported == true,
          unavailableReason: snapshot.data?.reason,
        );
      },
    );
  }

  Widget _buildCollectionMethods({
    required bool contactlessAvailable,
    String? unavailableReason,
  }) {
    final sendLinkButton = SlateButton(
      label: 'Send payment link',
      icon: LucideIcons.send,
      secondary: contactlessAvailable,
      onPressed: _working ? null : _sharePaymentLink,
    );
    return Column(
      children: [
        if (contactlessAvailable) ...[
          TextField(
            controller: _receiptEmailController,
            enabled: !_working && _terminalPaymentIdempotencyKey == null,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) {
              setState(() {
                _error = null;
              });
            },
            decoration: InputDecoration(
              label: const WorkloopFieldLabel(
                'Email receipt',
                isRequired: false,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              hintText: 'customer@example.com',
              helperText:
                  'Optional. Leave blank if the customer declines a receipt.',
              errorText: isValidReceiptEmail(_receiptEmailController.text)
                  ? null
                  : 'Enter a valid email address',
              prefixIcon: const Icon(LucideIcons.mail, size: 18),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SlateButton(
            label: _working
                ? 'Preparing reader...'
                : 'Take contactless payment',
            icon: LucideIcons.smartphoneNfc,
            onPressed: _working ? null : _takeContactlessPayment,
          ),
          const SizedBox(height: AppSpacing.sm),
          sendLinkButton,
        ] else ...[
          sendLinkButton,
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Send the link by message or email. Stripe handles the card securely.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _PaymentStatusRow(
            icon: LucideIcons.smartphoneNfc,
            iconColor: AppColors.of(context).t3,
            title: 'Contactless payments',
            detail: contactlessUnavailableMessage(
              Theme.of(context).platform,
              reason: unavailableReason,
            ),
            status: 'Unavailable',
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        WorkloopTextButton(
          label: 'Email payment request',
          onPressed: _working ? null : _emailPaymentRequest,
        ),
        WorkloopTextButton(
          label: _linkCopied ? 'Payment link copied' : 'Copy payment link',
          onPressed: _working ? null : _copyPaymentLink,
        ),
      ],
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  final Payment payment;

  const _PaymentSummary({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatPounds(payment.collectionAmount),
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${payment.depositOutstandingAmount > 0 ? 'Deposit due' : 'Due'} from ${payment.clientName ?? 'your client'}',
            style: TextStyle(color: AppColors.of(context).t3, fontSize: 13),
          ),
          if (payment.depositOutstandingAmount > 0)
            Text(
              '${formatPounds(payment.outstandingAmount)} remains on the full invoice.',
              style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _PaymentStatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final String? status;

  const _PaymentStatusRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.divider),
          bottom: BorderSide(color: tokens.divider),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              status!,
              style: TextStyle(
                color: status == 'Ready'
                    ? AppColors.of(context).success
                    : AppColors.of(context).t3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TestModeNote extends StatelessWidget {
  const _TestModeNote();

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        'Test mode — no real money will move.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.of(context).t2,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ModeLabel extends StatelessWidget {
  final String mode;

  const _ModeLabel({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Text(
        mode == 'live' ? 'Live' : 'Test mode',
        style: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
