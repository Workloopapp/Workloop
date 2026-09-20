import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/expense_editor_screen.dart';
import 'package:workloop/features/finance/expense_receipt_section.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/receipt_capture_service.dart';
import 'package:workloop/features/finance/widgets/money_editor_widgets.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
ReceiptFile get _receipt => ReceiptFile.checked('receipt.jpg', _jpeg);

class _NativePicker extends ImagePicker {
  XFile? result;
  PlatformException? error;
  ImageSource? source;
  CameraDevice? camera;
  double? width;
  double? height;
  int? quality;
  bool? metadata;
  int calls = 0;
  int recoveries = 0;
  LostDataResponse lost = LostDataResponse.empty();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls++;
    this.source = source;
    camera = preferredCameraDevice;
    width = maxWidth;
    height = maxHeight;
    quality = imageQuality;
    metadata = requestFullMetadata;
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    recoveries++;
    return lost;
  }
}

class _Capture extends ReceiptCaptureService {
  final Future<ReceiptFile?> Function(ReceiptCaptureSource) action;
  final bool interrupted;
  final sources = <ReceiptCaptureSource>[];

  _Capture(this.action, {this.interrupted = false});

  @override
  Future<bool> discardUnscopedRecovery() async => interrupted;

  @override
  Future<ReceiptFile?> pick(ReceiptCaptureSource source) {
    sources.add(source);
    return action(source);
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required _Capture capture,
  ValueChanged<ReceiptFile?>? onChanged,
  ValueChanged<bool>? onPickingChanged,
  ReceiptFile? pending,
  String Function()? workspace,
  Future<ReceiptFile?> Function()? filePicker,
  double scale = 1,
  Widget? home,
  DateTime? now,
  String timezone = 'Europe/London',
}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      businessNowProvider.overrideWithValue(now ?? DateTime(2026, 9, 8, 12)),
      workspaceSettingsProvider.overrideWith(
        (ref) async => {'timezone': timezone},
      ),
      expenseReceiptsProvider.overrideWith((ref, id) async => []),
      workspaceIdProvider.overrideWith(
        (ref) async => workspace?.call() ?? 'first',
      ),
      receiptCaptureServiceProvider.overrideWithValue(capture),
      if (filePicker != null)
        expenseReceiptPickerProvider.overrideWithValue(filePicker),
    ],
  );
  addTearDown(container.dispose);
  await container.read(workspaceIdProvider.future);
  await container.read(workspaceSettingsProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home:
            home ??
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ExpenseReceiptSection(
                  pending: pending,
                  onChanged: onChanged ?? (_) {},
                  onPickingChanged: onPickingChanged,
                ),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _choose(WidgetTester tester, String title) async {
  final attach = find.text('Attach receipt photo or PDF');
  final another = find.text('Choose another receipt');
  final button = attach.evaluate().isNotEmpty ? attach : another;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'native receipt is a bounded compatible copy without broad metadata',
    () async {
      final picker = _NativePicker()
        ..result = XFile.fromData(_jpeg, name: 'converted.heic');
      final service = ReceiptCaptureService(picker: picker);
      expect(picker.calls, 0);
      final receipt = await service.pick(ReceiptCaptureSource.camera);
      expect(picker.source, ImageSource.camera);
      expect(picker.camera, CameraDevice.rear);
      expect(picker.width, 4096);
      expect(picker.height, 4096);
      expect(picker.quality, 95);
      expect(picker.metadata, false);
      expect(receipt!.name, 'Receipt photo.jpg');
      expect(receipt.mimeType, 'image/jpeg');
      expect(receipt.bytes, _jpeg);
      await service.pick(ReceiptCaptureSource.photos);
      expect(picker.source, ImageSource.gallery);
    },
  );

  test('native cancel yields no attachment', () async {
    final service = ReceiptCaptureService(picker: _NativePicker());
    expect(await service.pick(ReceiptCaptureSource.photos), isNull);
  });

  test(
    'native PNG is kept as PNG and mismatched HEIC is rejected clearly',
    () async {
      final picker = _NativePicker()
        ..result = XFile.fromData(
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
          name: 'receipt.png',
        );
      final service = ReceiptCaptureService(picker: picker);
      expect(
        (await service.pick(ReceiptCaptureSource.photos))!.name,
        'Receipt photo.png',
      );
      picker.result = XFile.fromData(
        Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits]),
        name: 'receipt.heic',
      );
      await expectLater(
        service.pick(ReceiptCaptureSource.photos),
        throwsA(
          isA<ReceiptCaptureException>().having(
            (e) => e.message,
            'help',
            contains('HEIC'),
          ),
        ),
      );
    },
  );

  test(
    'photos over the private storage limit are rejected before attachment',
    () async {
      final picker = _NativePicker()
        ..result = XFile.fromData(
          Uint8List(receiptMaxBytes + 1),
          name: 'large.jpg',
        );
      await expectLater(
        ReceiptCaptureService(picker: picker).pick(ReceiptCaptureSource.photos),
        throwsA(
          isA<ReceiptCaptureException>().having(
            (e) => e.message,
            'help',
            contains('over 10 MB'),
          ),
        ),
      );
    },
  );

  for (final entry in {
    'camera_access_denied': 'Settings',
    'camera_access_restricted': 'restricted',
    'already_active': 'Finish the open',
    'invalid_source': 'camera is unavailable',
  }.entries) {
    test(
      '${entry.key} gives recovery guidance and allows a later retry',
      () async {
        final picker = _NativePicker()
          ..error = PlatformException(code: entry.key);
        final service = ReceiptCaptureService(picker: picker);
        await expectLater(
          service.pick(ReceiptCaptureSource.camera),
          throwsA(
            isA<ReceiptCaptureException>().having(
              (e) => e.message,
              'help',
              contains(entry.value),
            ),
          ),
        );
        picker.error = null;
        picker.result = XFile.fromData(_jpeg, name: 'receipt.jpg');
        expect(await service.pick(ReceiptCaptureSource.camera), isNotNull);
      },
    );
  }

  test(
    'Android interrupted results are reported without choosing a new photo',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final picker = _NativePicker()
        ..lost = LostDataResponse(
          files: [XFile.fromData(_jpeg)],
          type: RetrieveType.image,
        );
      final service = ReceiptCaptureService(picker: picker);
      expect(await service.discardUnscopedRecovery(), true);
      expect(picker.calls, 0);
      expect(picker.recoveries, 1);
    },
  );

  testWidgets(
    'chooser offers all three sources at large text without opening permissions',
    (tester) async {
      final capture = _Capture((_) async => null);
      await _mount(tester, capture: capture, scale: 2);
      await tester.ensureVisible(find.text('Attach receipt photo or PDF'));
      await tester.tap(find.text('Attach receipt photo or PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Photo library'), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);
      expect(capture.sources, isEmpty);
      await tester.ensureVisible(find.text('Photo library'));
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();
      expect(capture.sources, [ReceiptCaptureSource.photos]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native cancel keeps an existing pending receipt and releases busy state',
    (tester) async {
      final result = Completer<ReceiptFile?>();
      final capture = _Capture((_) => result.future);
      var changes = 0;
      final busy = <bool>[];
      await _mount(
        tester,
        capture: capture,
        pending: _receipt,
        onChanged: (_) => changes++,
        onPickingChanged: busy.add,
      );
      busy.clear();
      await _choose(tester, 'Take photo');
      expect(busy, [true]);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Choose another receipt'),
      );
      expect(button.onPressed, isNull);
      expect(capture.sources.length, 1);
      result.complete(null);
      await tester.pumpAndSettle();
      expect(changes, 0);
      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(busy, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native permission failure keeps the attachment and permits retry',
    (tester) async {
      var attempts = 0;
      var changes = 0;
      final capture = _Capture((_) async {
        if (++attempts == 1) {
          throw const ReceiptCaptureException(
            'Allow Camera in Settings, then return and try again.',
          );
        }
        return _receipt;
      });
      await _mount(
        tester,
        capture: capture,
        pending: _receipt,
        onChanged: (_) => changes++,
      );
      await _choose(tester, 'Take photo');
      expect(find.textContaining('Allow Camera'), findsOneWidget);
      expect(changes, 0);
      await _choose(tester, 'Take photo');
      expect(changes, 1);
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native result is ignored after a business switch', (
    tester,
  ) async {
    var workspace = 'first';
    var changes = 0;
    final result = Completer<ReceiptFile?>();
    final capture = _Capture((_) => result.future);
    final container = await _mount(
      tester,
      capture: capture,
      workspace: () => workspace,
      onChanged: (_) => changes++,
    );
    await _choose(tester, 'Photo library');
    workspace = 'second';
    container.invalidate(workspaceIdProvider);
    await tester.pumpAndSettle();
    result.complete(_receipt);
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Files route keeps imported bytes and never invokes camera or photos',
    (tester) async {
      final capture = _Capture((_) async => null);
      final pdf = ReceiptFile.checked(
        'invoice.pdf',
        Uint8List.fromList('%PDF-1.4'.codeUnits),
      );
      ReceiptFile? attached;
      await _mount(
        tester,
        capture: capture,
        filePicker: () async => pdf,
        onChanged: (file) => attached = file,
      );
      await _choose(tester, 'Choose file');
      expect(attached, same(pdf));
      expect(capture.sources, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dismissing the capture chooser leaves the draft unchanged', (
    tester,
  ) async {
    var changes = 0;
    final busy = <bool>[];
    final capture = _Capture((_) async => _receipt);
    await _mount(
      tester,
      capture: capture,
      pending: _receipt,
      onChanged: (_) => changes++,
      onPickingChanged: busy.add,
    );
    busy.clear();
    await tester.tap(find.text('Choose another receipt'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(capture.sources, isEmpty);
    expect(busy, [true, false]);
    expect(find.text('receipt.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disposed receipt screen ignores a late picker response', (
    tester,
  ) async {
    var changes = 0;
    final result = Completer<ReceiptFile?>();
    final capture = _Capture((_) => result.future);
    final busy = <bool>[];
    await _mount(
      tester,
      capture: capture,
      onChanged: (_) => changes++,
      onPickingChanged: busy.add,
    );
    await _choose(tester, 'Photo library');
    final busyEvents = busy.length;
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete(_receipt);
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(busy.length, busyEvents);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'interrupted capture asks to choose again without attaching an unscoped result',
    (tester) async {
      var changes = 0;
      final capture = _Capture((_) async => _receipt, interrupted: true);
      await _mount(tester, capture: capture, onChanged: (_) => changes++);
      expect(
        find.textContaining('previous receipt capture was interrupted'),
        findsOneWidget,
      );
      expect(changes, 0);
      expect(capture.sources, isEmpty);
    },
  );

  testWidgets(
    'expense cannot save or leave while its native picker is pending',
    (tester) async {
      final result = Completer<ReceiptFile?>();
      final capture = _Capture((_) => result.future);
      await _mount(
        tester,
        capture: capture,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ExpenseEditorScreen(),
                ),
              ),
              child: const Text('Open expense'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open expense'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '25');
      await _choose(tester, 'Photo library');
      expect(
        tester.widget<MoneySaveAction>(find.byType(MoneySaveAction)).enabled,
        false,
      );
      final back = find.byWidgetPredicate(
        (widget) =>
            widget is WorkloopIconButton &&
            widget.semanticLabel == 'Back to Money',
      );
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseEditorScreen), findsOneWidget);
      expect(find.text('Save this expense?'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseEditorScreen), findsOneWidget);
      result.complete(null);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MoneySaveAction>(find.byType(MoneySaveAction)).enabled,
        true,
      );
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Save this expense?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a future paid date requires explicit correction and picker cancel preserves it',
    (tester) async {
      final capture = _Capture((_) async => null);
      await _mount(
        tester,
        capture: capture,
        home: ExpenseEditorScreen(
          expense: Expense(
            id: 'legacy',
            workspaceId: 'first',
            amount: 25,
            category: 'Travel',
            expenseDate: DateTime(2026, 9, 12),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The paid date is in the future.'),
        findsOneWidget,
      );
      expect(find.text('12 Sep 2026'), findsOneWidget);
      await tester.tap(find.text('Date paid'));
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.initialDate, DateTime(2026, 9, 8));
      expect(calendar.lastDate, DateTime(2026, 9, 8));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('12 Sep 2026'), findsOneWidget);
      await tester.tap(find.text('Date paid'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use date'));
      await tester.pumpAndSettle();
      expect(find.text('8 Sep 2026'), findsOneWidget);
      expect(
        find.textContaining('The paid date is in the future.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expense paid date follows the workspace across the date line', (
    tester,
  ) async {
    await _mount(
      tester,
      capture: _Capture((_) async => null),
      now: DateTime.utc(2026, 9, 8, 12),
      timezone: 'Pacific/Kiritimati',
      home: const ExpenseEditorScreen(),
    );
    expect(find.text('9 Sep 2026'), findsOneWidget);
    await tester.tap(find.text('Date paid'));
    await tester.pumpAndSettle();
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(calendar.lastDate, DateTime(2026, 9, 9));
    expect(calendar.initialDate, DateTime(2026, 9, 9));
    expect(tester.takeException(), isNull);
  });
}
