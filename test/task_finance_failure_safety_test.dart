import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/expenses_repository.dart';
import 'package:workloop/shared/repositories/notifications_repository.dart';
import 'package:workloop/shared/repositories/payments_repository.dart';
import 'package:workloop/shared/repositories/tasks_repository.dart';

SupabaseClient _testClient() {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

class _ControlledTasksRepository extends TasksRepository {
  _ControlledTasksRepository() : super(_testClient());

  final statusMutation = Completer<void>();
  final editMutation = Completer<void>();
  final deletion = Completer<void>();
  int statusCalls = 0;
  int editCalls = 0;
  String? savedAppointmentId;
  int deleteCalls = 0;

  @override
  Future<List<TaskChecklistItem>> checklistItems(String taskId) async =>
      const [];

  @override
  Future<void> updateStatus(String taskId, String status) {
    statusCalls += 1;
    return statusMutation.future;
  }

  @override
  Future<void> update({
    required String taskId,
    required String title,
    required String priority,
    String reminderTiming = 'none',
    DateTime? dueDate,
    String? contactId,
    String? appointmentId,
  }) {
    editCalls += 1;
    savedAppointmentId = appointmentId;
    return editMutation.future;
  }

  @override
  Future<void> delete(String taskId) {
    deleteCalls += 1;
    return deletion.future;
  }
}

class _ControlledPaymentsRepository extends PaymentsRepository {
  _ControlledPaymentsRepository() : super(_testClient());

  final markPaidMutation = Completer<void>();
  final deletion = Completer<void>();
  int markPaidCalls = 0;
  int deleteCalls = 0;

  @override
  Future<void> markPaid(Payment payment) {
    markPaidCalls += 1;
    return markPaidMutation.future;
  }

  @override
  Future<void> delete(String paymentId) {
    deleteCalls += 1;
    return deletion.future;
  }
}

class _ControlledExpensesRepository extends ExpensesRepository {
  _ControlledExpensesRepository() : super(_testClient());

  final deletion = Completer<void>();
  int deleteCalls = 0;
  String? lastDeletedId;

  @override
  Future<void> delete(String expenseId) {
    deleteCalls += 1;
    lastDeletedId = expenseId;
    return deletion.future;
  }
}

class _FailingNotificationsRepository extends NotificationsRepository {
  _FailingNotificationsRepository() : super(_testClient());

  @override
  Future<void> create({
    required String workspaceId,
    required String type,
    required String title,
    required String body,
    String? deepLink,
  }) {
    return Future<void>.error(StateError('notification feed unavailable'));
  }
}

void main() {
  final now = DateTime.now();
  const task = SlateTask(
    id: 'task-1',
    workspaceId: 'workspace-1',
    title: 'Launch checklist',
    appointmentId: 'booking-linked',
  );

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpTasks(
    WidgetTester tester,
    _ControlledTasksRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTasksProvider.overrideWith((ref) async => const [task]),
          workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
          clientsProvider.overrideWith((ref) async => const []),
          tasksRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: TasksScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpFinance(
    WidgetTester tester, {
    required List<Payment> payments,
    required List<Expense> expenses,
    required _ControlledPaymentsRepository paymentsRepository,
    required _ControlledExpensesRepository expensesRepository,
  }) async {
    final summary = FinanceSummary.from(
      payments: payments,
      expenses: expenses,
      monthlyTarget: 1000,
      now: now,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoicesProvider.overrideWith((ref) async => payments),
          expensesProvider.overrideWith((ref) async => expenses),
          financeSummaryProvider.overrideWith((ref) async => summary),
          workspaceSettingsProvider.overrideWith(
            (ref) async => const {'revenue_target': 1000},
          ),
          paymentsRepositoryProvider.overrideWithValue(paymentsRepository),
          expensesRepositoryProvider.overrideWithValue(expensesRepository),
          notificationsRepositoryProvider.overrideWithValue(
            _FailingNotificationsRepository(),
          ),
        ],
        child: const MaterialApp(home: FinanceScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'task workflow payload preserves retry identity and cleans checklist',
    () {
      final payload = buildCreateTaskWorkflowPayload(
        workspaceId: 'workspace-1',
        title: '  Confirm launch  ',
        priority: 'high',
        reminderTiming: 'day_before',
        dueDate: DateTime(2026, 8, 1),
        contactId: 'contact-1',
        checklistTitles: const ['  Test iOS  ', '', 'Test Android'],
        idempotencyKey: 'task-workflow-key-123456',
      );

      expect(payload['title'], 'Confirm launch');
      expect(payload['due_date'], '2026-08-01');
      expect(payload['checklist_titles'], ['Test iOS', 'Test Android']);
      expect(payload['idempotency_key'], 'task-workflow-key-123456');
    },
  );

  test('task migration is private, tenant checked, and atomic', () {
    final migration = File(
      'supabase/migrations/'
      '20260726000048_transactional_task_creation.sql',
    ).readAsStringSync();

    expect(migration, contains('app_private.create_task_workflow'));
    expect(migration, contains("'create_task'"));
    expect(migration, contains('Workspace access denied'));
    expect(migration, contains('public.task_checklist_items'));
    expect(migration, contains('security invoker'));
    expect(migration, contains('from public, anon'));
    expect(migration, isNot(contains('to anon')));
  });

  test('ordinary edits preserve a partially collected payment', () {
    final receivedAt = DateTime.utc(2026, 7, 20, 12);
    final payment = Payment(
      id: 'payment-1',
      workspaceId: 'workspace-1',
      number: 'PAY-001',
      status: 'sent',
      issueDate: DateTime(2026, 7, 1),
      incomeRecordedAt: receivedAt,
      total: 100,
      amountPaid: 35,
    );

    final unchangedState = resolvePaymentUpdateState(
      existingPayment: payment,
      amount: 120,
      selectedStatus: 'sent',
      selectedDate: DateTime(2026, 7, 1),
      paymentStateChanged: false,
    );
    expect(unchangedState.status, 'sent');
    expect(unchangedState.amountPaid, 35);
    expect(unchangedState.incomeRecordedAt, receivedAt.toIso8601String());

    final explicitlyReceived = resolvePaymentUpdateState(
      existingPayment: payment,
      amount: 120,
      selectedStatus: 'paid',
      selectedDate: DateTime(2026, 7, 25),
      paymentStateChanged: true,
    );
    expect(explicitlyReceived.status, 'paid');
    expect(explicitlyReceived.amountPaid, 120);
  });

  test('explicitly changing a partial payment to unpaid clears collection', () {
    final payment = Payment(
      id: 'payment-1',
      workspaceId: 'workspace-1',
      number: 'PAY-001',
      status: 'sent',
      issueDate: DateTime(2026, 7, 1),
      incomeRecordedAt: DateTime.utc(2026, 7, 20, 12),
      total: 100,
      amountPaid: 35,
    );

    final changed = resolvePaymentUpdateState(
      existingPayment: payment,
      amount: 100,
      selectedStatus: 'sent',
      selectedDate: DateTime(2026, 7, 1),
      paymentStateChanged: true,
    );

    expect(changed.status, 'sent');
    expect(changed.amountPaid, 0);
    expect(changed.incomeRecordedAt, isNull);
  });

  testWidgets('failed task completion keeps confirmation open and announced', (
    tester,
  ) async {
    final repository = _ControlledTasksRepository();
    await pumpTasks(tester, repository);

    await tester.tap(find.bySemanticsLabel('Complete Launch checklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark Complete'));
    await tester.pump();

    expect(repository.statusCalls, 1);
    expect(find.text('Complete this task?'), findsOneWidget);
    expect(find.text('Completing...'), findsOneWidget);

    repository.statusMutation.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.text('Complete this task?'), findsOneWidget);
    expect(
      find.text(
        'Could not complete this task. Nothing was changed. Please try again.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('failed task edit stays on editor with visible feedback', (
    tester,
  ) async {
    final repository = _ControlledTasksRepository();
    await pumpTasks(tester, repository);

    await tester.tap(find.text('Launch checklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Edit task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Launch review');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(repository.editCalls, 1);
    expect(find.text('Edit task'), findsOneWidget);

    repository.editMutation.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.text('Edit task'), findsOneWidget);
    expect(
      find.text('Could not save these task changes. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('task edit retains booking link through normal route close', (
    tester,
  ) async {
    final repository = _ControlledTasksRepository();
    await pumpTasks(tester, repository);
    await tester.tap(find.text('Launch checklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Edit task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Updated linked task');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(repository.savedAppointmentId, 'booking-linked');
    repository.editMutation.complete();
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed task deletion keeps confirmation open and announced', (
    tester,
  ) async {
    final repository = _ControlledTasksRepository();
    await pumpTasks(tester, repository);

    await tester.tap(find.text('Launch checklist'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete Task'));
    await tester.tap(find.text('Delete Task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Task').last);
    await tester.pump();

    expect(repository.deleteCalls, 1);
    expect(find.text('Delete task?'), findsOneWidget);
    expect(find.text('Deleting...'), findsOneWidget);

    repository.deletion.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.text('Delete task?'), findsOneWidget);
    expect(
      find.text(
        'Could not delete this task. Nothing was removed. Please try again.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('failed mark-received keeps the Money action sheet open', (
    tester,
  ) async {
    final paymentsRepository = _ControlledPaymentsRepository();
    final expensesRepository = _ControlledExpensesRepository();
    final payment = Payment(
      id: 'payment-1',
      workspaceId: 'workspace-1',
      number: 'PAY-001',
      status: 'sent',
      issueDate: now,
      dueDate: now.add(const Duration(days: 7)),
      total: 125,
      clientName: 'Launch Client',
    );
    await pumpFinance(
      tester,
      payments: [payment],
      expenses: const [],
      paymentsRepository: paymentsRepository,
      expensesRepository: expensesRepository,
    );

    await tester.tap(find.text('Owed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch Client'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Received'));
    await tester.pump();

    expect(paymentsRepository.markPaidCalls, 1);
    expect(find.text('To collect'), findsOneWidget);
    expect(find.text('Updating...'), findsOneWidget);

    paymentsRepository.markPaidMutation.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.text('To collect'), findsOneWidget);
    expect(
      find.text(
        'Could not mark this payment as received. Nothing visible has changed; check your connection and try again.',
      ),
      findsOneWidget,
    );

    final close = find.text('Close');
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
  });

  testWidgets('confirmed payment closes even if optional notification fails', (
    tester,
  ) async {
    final paymentsRepository = _ControlledPaymentsRepository();
    final expensesRepository = _ControlledExpensesRepository();
    final payment = Payment(
      id: 'payment-1',
      workspaceId: 'workspace-1',
      number: 'PAY-001',
      status: 'sent',
      issueDate: now,
      dueDate: now.add(const Duration(days: 7)),
      total: 125,
      clientName: 'Launch Client',
    );
    await pumpFinance(
      tester,
      payments: [payment],
      expenses: const [],
      paymentsRepository: paymentsRepository,
      expensesRepository: expensesRepository,
    );

    await tester.tap(find.text('Owed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch Client'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Received'));
    await tester.pump();

    paymentsRepository.markPaidMutation.complete();
    await tester.pumpAndSettle();

    expect(find.text('To collect'), findsNothing);
    expect(find.text('£125 marked as received'), findsOneWidget);
  });

  testWidgets('failed expense deletion keeps confirmation open', (
    tester,
  ) async {
    final paymentsRepository = _ControlledPaymentsRepository();
    final expensesRepository = _ControlledExpensesRepository();
    final expense = Expense(
      id: 'expense-1',
      workspaceId: 'workspace-1',
      amount: 45,
      category: 'Materials',
      notes: 'Window-cleaning materials',
      expenseDate: now,
    );
    await pumpFinance(
      tester,
      payments: const [],
      expenses: [expense],
      paymentsRepository: paymentsRepository,
      expensesRepository: expensesRepository,
    );

    await tester.tap(find.text('Spent'));
    await tester.pumpAndSettle();
    final expenseRow = find.text('Window-cleaning materials');
    await tester.ensureVisible(expenseRow);
    await tester.pumpAndSettle();
    await tester.longPress(expenseRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Expense'));
    await tester.pump();

    expect(expensesRepository.deleteCalls, 1);
    expect(expensesRepository.lastDeletedId, 'expense-1');
    expect(find.text('Delete expense?'), findsOneWidget);
    expect(find.text('Deleting...'), findsOneWidget);

    expensesRepository.deletion.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.text('Delete expense?'), findsOneWidget);
    expect(
      find.text(
        'Could not confirm this deletion. The expense remains visible; check your connection and try again.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(expenseRow, findsOneWidget);
  });

  testWidgets('failed income deletion keeps confirmation open', (tester) async {
    final paymentsRepository = _ControlledPaymentsRepository();
    final expensesRepository = _ControlledExpensesRepository();
    final payment = Payment(
      id: 'payment-1',
      workspaceId: 'workspace-1',
      number: 'PAY-001',
      status: 'paid',
      issueDate: now,
      incomeRecordedAt: now,
      total: 125,
      amountPaid: 125,
      clientName: 'Launch Client',
    );
    await pumpFinance(
      tester,
      payments: [payment],
      expenses: const [],
      paymentsRepository: paymentsRepository,
      expensesRepository: expensesRepository,
    );

    final history = find.byKey(const ValueKey('money-history-toggle'));
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    await tester.tap(history);
    await tester.pumpAndSettle();
    final incomeCard = find.text('Launch Client');
    await tester.ensureVisible(incomeCard);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More payment actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete income').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete income entry?'), findsOneWidget);
    await tester.tap(find.text('Delete income'));
    await tester.pump();

    expect(paymentsRepository.deleteCalls, 1);
    expect(find.text('Delete income entry?'), findsOneWidget);
    expect(find.text('Deleting...'), findsOneWidget);

    paymentsRepository.deletion.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.text('Delete income entry?'), findsOneWidget);
    expect(
      find.text(
        'Could not confirm this deletion. The income entry remains visible; check your connection and try again.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
