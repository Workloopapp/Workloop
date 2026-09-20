import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/clients/add_client_screen.dart';
import 'package:workloop/features/appointments/add_appointment_screen.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/features/finance/add_payment_screen.dart';
import 'package:workloop/features/finance/expense_editor_screen.dart';
import 'package:workloop/features/finance/receipt_capture_service.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/clients_repository.dart';
import 'package:workloop/shared/repositories/expenses_repository.dart';
import 'package:workloop/shared/repositories/payments_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const _oldPageColour = Color(0xffff00ff);
const _newPageColour = Color(0xff00ffff);

/// The old page's sentinel colour also remains recognisable under the native
/// transition's dark scrim, unlike comparing a single exact RGB value.
Future<int> _oldPagePixels(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Rect region,
) async {
  return (await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var count = 0;
      final clipped = region.intersect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );
      for (var y = clipped.top.ceil(); y < clipped.bottom.floor(); y++) {
        for (var x = clipped.left.ceil(); x < clipped.right.floor(); x++) {
          final offset = (y * image.width + x) * 4;
          final red = data.getUint8(offset);
          final green = data.getUint8(offset + 1);
          final blue = data.getUint8(offset + 2);
          if (red > green + 80 && blue > green + 80) count++;
        }
      }
      return count;
    } finally {
      image.dispose();
    }
  }))!;
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

class _RetainedCounter extends StatefulWidget {
  const _RetainedCounter();
  @override
  State<_RetainedCounter> createState() => _RetainedCounterState();
}

class _RetainedCounterState extends State<_RetainedCounter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _oldPageColour,
    child: Center(
      child: TextButton(
        onPressed: () => setState(() => count++),
        child: Text('Saved state $count'),
      ),
    ),
  );
}

class _PendingPayment implements PaymentsRepository {
  final result = Completer<String>();
  int calls = 0;
  @override
  Future<String> create({
    required String workspaceId,
    required double amount,
    required String status,
    required DateTime date,
    DateTime? dueDate,
    String? contactId,
    String? appointmentId,
    String? notes,
    String? paymentId,
  }) {
    calls++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingExpense implements ExpensesRepository {
  final result = Completer<void>();
  int calls = 0;
  @override
  Future<void> create({
    required String workspaceId,
    required double amount,
    required String category,
    required DateTime date,
    String? notes,
    String? expenseId,
  }) {
    calls++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoInterruptedReceiptCapture extends ReceiptCaptureService {
  @override
  Future<bool> discardUnscopedRecovery() async => false;
}

class _PendingClient implements ClientsRepository {
  final result = Completer<String>();
  int calls = 0;
  @override
  Future<String> create({
    required String workspaceId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? importantNotes,
    String status = 'active',
    String preferredContactMethod = 'phone',
    String? source,
    DateTime? birthday,
    List<String> tags = const [],
  }) {
    calls++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BookingAuth extends Fake implements AuthRepository {
  @override
  String get currentUserId => 'booking-owner';
}

class _PendingBooking implements AppointmentsRepository {
  final result = Completer<AppointmentScheduleReview>();
  int calls = 0;
  @override
  Future<AppointmentScheduleReview> reviewSchedule({
    required String workspaceId,
    required DateTime startTime,
    required DateTime endTime,
    Map<String, dynamic>? workingHours,
    String? workingHoursTimezone,
    String? excludeAppointmentId,
    String? recurrenceRule,
    int repeatOccurrences = 1,
  }) {
    calls++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      '${theme.brightness.name} page backdrop covers old pixels inside the app canvas',
      (tester) async {
        _phoneSize(tester);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (_, child) => WorkloopAppCanvas(child: child!),
            home: RepaintBoundary(
              key: boundary,
              child: const Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: _oldPageColour),
                  WorkloopTexturedBackdrop(),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          await _oldPagePixels(
            tester,
            boundary,
            const Rect.fromLTWH(0, 0, 390, 844),
          ),
          0,
        );
      },
    );
  }

  testWidgets(
    'tab selection is immediate and retains the previous workspace state',
    (tester) async {
      _phoneSize(tester);
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: boundary,
            child: ValueListenableBuilder<int>(
              valueListenable: selected,
              builder: (_, index, _) => WorkloopInteractiveWorkspaceStack(
                index: index,
                previousIndex: index == 0 ? 1 : 0,
                onBack: () => selected.value = 0,
                children: const [
                  _RetainedCounter(),
                  ColoredBox(
                    color: _newPageColour,
                    child: Center(child: Text('New workspace')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Saved state 0'));
      await tester.pump();
      selected.value = 1;
      await tester.pump(); // No animation time is allowed to pass.
      expect(
        await _oldPagePixels(
          tester,
          boundary,
          const Rect.fromLTWH(50, 0, 340, 844),
        ),
        0,
      );
      selected.value = 0;
      await tester.pump();
      expect(find.text('Saved state 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native iOS income transition and keyboard resize cover the Money page',
    (tester) async {
      _phoneSize(tester);
      final navigator = GlobalKey<NavigatorState>();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clientsProvider.overrideWith((ref) async => [])],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
            builder: (_, child) => WorkloopAppCanvas(
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: const Scaffold(
              backgroundColor: _oldPageColour,
              body: Center(child: Text('Previous Money data')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        await _oldPagePixels(
          tester,
          boundary,
          const Rect.fromLTWH(0, 0, 390, 844),
        ),
        greaterThan(100000),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const AddPaymentScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final incoming = tester.getRect(find.byType(AddPaymentScreen));
      expect(incoming.left, greaterThan(0));
      expect(incoming.left, lessThan(330));
      final insideIncoming = Rect.fromLTRB(incoming.left + 24, 24, 386, 820);
      expect(
        await _oldPagePixels(tester, boundary, insideIncoming),
        0,
        reason: 'The prior Money screen must not show through the moving form.',
      );
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 310);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        await _oldPagePixels(
          tester,
          boundary,
          const Rect.fromLTWH(0, 0, 390, 530),
        ),
        0,
      );
      expect(find.text('Record income'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'booking save ignores duplicate taps and Back during schedule validation',
    (tester) async {
      _phoneSize(tester);
      final repository = _PendingBooking();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_BookingAuth()),
            clientsProvider.overrideWith((ref) async => []),
            servicesProvider.overrideWith((ref) async => []),
            appointmentsProvider.overrideWith((ref) async => []),
            workspaceSettingsProvider.overrideWith((ref) async => null),
            workspaceIdProvider.overrideWith((ref) async => 'workspace'),
            appointmentsRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AddAppointmentScreen(initialClientId: 'client'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom service'));
      await tester.pumpAndSettle();
      final serviceName = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Service name',
      );
      final price = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Price',
      );
      await tester.enterText(serviceName, 'Window clean');
      await tester.enterText(price, '45');
      await tester.pump();
      await tester.tap(find.text('Add').first);
      await tester.tap(find.text('Add').first);
      await tester.pump();
      expect(repository.calls, 1);
      tester
          .widget<WorkloopRouteHeader>(find.byType(WorkloopRouteHeader))
          .onBack!();
      await tester.pump();
      expect(find.text('Discard'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AddAppointmentScreen), findsOneWidget);
      repository.result.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        find.text('The booking could not be saved. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in ['income', 'expense', 'client']) {
    testWidgets(
      '$kind save ignores a second tap and Back while the write is pending',
      (tester) async {
        _phoneSize(tester);
        final payment = _PendingPayment();
        final expense = _PendingExpense();
        final client = _PendingClient();
        final screen = switch (kind) {
          'income' => const AddPaymentScreen(),
          'expense' => const ExpenseEditorScreen(),
          _ => const AddClientScreen(),
        };
        final overrides = <Override>[
          workspaceIdProvider.overrideWith((ref) async => 'workspace'),
          clientsProvider.overrideWith((ref) async => []),
          paymentsRepositoryProvider.overrideWithValue(payment),
          expensesRepositoryProvider.overrideWithValue(expense),
          // This test covers the repository write after native startup recovery.
          if (kind == 'expense')
            receiptCaptureServiceProvider.overrideWithValue(
              _NoInterruptedReceiptCapture(),
            ),
          clientsRepositoryProvider.overrideWithValue(client),
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides,
            child: MaterialApp(theme: AppTheme.light, home: screen),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          kind == 'client' ? 'Alex Test' : '45',
        );
        await tester.pump();
        await tester.tap(find.text('Add').first);
        await tester.tap(find.text('Add').first);
        await tester.pump();
        final calls = switch (kind) {
          'income' => payment.calls,
          'expense' => expense.calls,
          _ => client.calls,
        };
        expect(calls, 1);
        final header = tester.widget<WorkloopRouteHeader>(
          find.byType(WorkloopRouteHeader),
        );
        header.onBack!();
        await tester.pump();
        expect(find.text('Discard'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(screen.runtimeType), findsOneWidget);
        switch (kind) {
          case 'income':
            payment.result.completeError(StateError('offline'));
          case 'expense':
            expense.result.completeError(StateError('offline'));
          case 'client':
            client.result.completeError(StateError('offline'));
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('Please try again.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
