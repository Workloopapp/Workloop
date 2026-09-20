import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/features/finance/documents/business_document_detail_screen.dart';
import 'package:workloop/features/finance/expense_receipt_section.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/receipt_capture_service.dart';
import 'package:workloop/shared/documents/workloop_document_viewer.dart';
import 'package:workloop/shared/documents/document_open_exception.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/business_documents_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Auth extends Fake implements AuthRepository {
  String? user = 'owner-a';
  final events = StreamController<AuthState>.broadcast();
  @override
  String? get currentUserId => user;
  @override
  Stream<AuthState> get authChanges => events.stream;
}

class _Documents extends Fake implements BusinessDocumentsRepository {
  _Documents(this.document);
  final BusinessDocument document;
  int loads = 0;
  @override
  Future<BusinessDocument> get(String workspaceId, String id) async {
    expect(workspaceId, 'business-a');
    expect(id, document.id);
    loads++;
    return document;
  }
}

class _Capture extends Fake implements ReceiptCaptureService {
  @override
  Future<bool> discardUnscopedRecovery() async => false;
}

class _Receipts extends Fake implements ExpenseRecordsRepository {
  _Receipts(this.receipt, this.bytes);
  final ExpenseReceipt receipt;
  final Uint8List bytes;
  int downloads = 0;
  @override
  Future<List<ExpenseReceipt>> receipts(
    String expenseId, {
    required String workspaceId,
  }) async {
    expect(workspaceId, 'business-a');
    expect(expenseId, 'expense');
    return [receipt];
  }

  @override
  Future<Uint8List> download(ExpenseReceipt receipt) async {
    expect(receipt, this.receipt);
    downloads++;
    return bytes;
  }
}

Uint8List _text(String text) => Uint8List.fromList(utf8.encode(text));

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required _Auth auth,
  required Future<Uint8List> Function() load,
  String mime = 'text/plain',
  String Function()? workspace,
  Future<String?> Function()? workspaceFuture,
  double scale = 1,
  Widget? home,
  BusinessDocumentsRepository? documents,
  ExpenseRecordsRepository? receipts,
}) async {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(auth.events.close);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      if (receipts != null) ...[
        expenseRecordsRepositoryProvider.overrideWithValue(receipts),
        receiptCaptureServiceProvider.overrideWithValue(_Capture()),
      ],
      if (documents != null) ...[
        businessDocumentsRepositoryProvider.overrideWithValue(documents),
        invoicesProvider.overrideWith((ref) async => []),
        workspaceTodayProvider.overrideWithValue(DateTime(2026, 9, 8)),
        workspaceSettingsProvider.overrideWith((ref) async => {}),
      ],
      workspaceIdProvider.overrideWith(
        (ref) async => workspaceFuture == null
            ? workspace?.call() ?? 'business-a'
            : workspaceFuture(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(workspaceIdProvider.future);
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
            WorkloopDocumentViewerScreen(
              workspaceId: 'business-a',
              title: mime.startsWith('image/') ? 'Receipt' : 'Invoice INV-001',
              fileName: mime.startsWith('image/') ? 'receipt.png' : 'INV-001.pdf',
              mimeType: mime,
              loadBytes: load,
            ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _finishRaster(WidgetTester tester) async {
  // Worker PDF generation and engine image encoding need real event-loop turns
  // outside the fake clock; the first isolate can take longer on cold CI hosts.
  await tester.pump(const Duration(milliseconds: 400));
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text('Page 1 of 2').evaluate().isNotEmpty) break;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const printing = MethodChannel('net.nfet.printing');
  const codec = StandardMethodCodec();
  final rendered = <Uint8List>[];
  var failRaster = false;

  Future<void> emit(String method, Map<String, dynamic> arguments) async {
    final done = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      printing.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    rendered.clear();
    failRaster = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(printing, (
      call,
    ) async {
      if (call.method == 'printingInfo') {
        return {'canRaster': true, 'canPrint': true, 'canShare': true};
      }
      if (call.method == 'rasterPdf') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        rendered.add(args['doc'] as Uint8List);
        scheduleMicrotask(() async {
          if (!failRaster) {
            for (var page = 0; page < 2; page++) {
              await emit('onPageRasterized', {
                'job': args['job'],
                'width': 16,
                'height': 24,
                'image': Uint8List.fromList(List.filled(16 * 24 * 4, 255)),
              });
            }
          }
          await emit('onPageRasterEnd', {
            'job': args['job'],
            if (failRaster) 'error': 'Could not parse document',
          });
        });
        return null;
      }
      throw StateError('Unexpected native operation ${call.method}');
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(printing, null),
  );

  testWidgets(
    'opens the generated PDF bytes in app with pages and accessible zoom',
    (tester) async {
      final bytes = _text('%PDF-1.7 exact saved invoice bytes');
      await _mount(
        tester,
        auth: _Auth(),
        mime: 'application/pdf',
        load: () async => bytes,
        scale: 2,
      );
      await _finishRaster(tester);
      final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
      expect(preview.allowPrinting, false);
      expect(preview.allowSharing, false);
      expect(preview.useActions, false);
      expect(preview.canChangePageFormat, false);
      expect(preview.canChangeOrientation, false);
      expect(rendered, isNotEmpty);
      expect(rendered.last, orderedEquals(bytes));
      expect(find.text('Page 1 of 2'), findsOneWidget);
      final zoom = find.byTooltip('Zoom in Page 1');
      await tester.ensureVisible(zoom);
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      final view = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer).first,
      );
      expect(
        view.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await tester.tap(find.text('Fit').first);
      await tester.pumpAndSettle();
      expect(view.transformationController!.value.getMaxScaleOnAxis(), 1);
      await tester.scrollUntilVisible(
        find.text('Page 2 of 2'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Share'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final type in ['invoice', 'quote']) {
    testWidgets('$type detail opens a refreshed PDF inside Workloop', (
      tester,
    ) async {
      final document = BusinessDocument.fromMap({
        'id': 'doc',
        'workspace_id': 'business-a',
        'type': type,
        'status': type == 'invoice' ? 'sent' : 'draft',
        'invoice_number': type == 'invoice' ? 'INV-001' : null,
        'issue_date': '2026-09-08',
        'total': 60,
        'subtotal': 60,
        'business_snapshot': {'name': 'Calm Cleaning'},
        'client_snapshot': {'name': 'Sam Example'},
        'items': [
          {'description': 'Cleaning', 'qty': '1', 'unit_price': '60'},
        ],
      });
      final repository = _Documents(document);
      await _mount(
        tester,
        auth: _Auth(),
        load: () async => _text('unused'),
        documents: repository,
        home: const BusinessDocumentDetailScreen(documentId: 'doc'),
      );
      await tester.pumpAndSettle();
      final view = find.widgetWithText(
        SlateButton,
        type == 'invoice' ? 'View PDF' : 'View draft PDF',
      );
      await tester.scrollUntilVisible(view, 250);
      await tester.ensureVisible(view);
      await tester.tap(view);
      await _finishRaster(tester);
      expect(find.byType(WorkloopDocumentViewerScreen), findsOneWidget);
      expect(repository.loads, 2);
      expect(String.fromCharCodes(rendered.last.take(5)), '%PDF-');
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('layout rejection shows the actionable generator message', (
    tester,
  ) async {
    await _mount(
      tester,
      auth: _Auth(),
      mime: 'application/pdf',
      load: () async {
        throw const DocumentOpenException(
          'Shorten the description and try again.',
        );
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Shorten the description and try again.'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('saved receipt row opens its original PDF in app', (
    tester,
  ) async {
    final bytes = _text('%PDF-1.7 original supplier receipt');
    final receipt = ExpenseReceipt(
      id: 'receipt',
      path: 'business-a/expense/receipt.pdf',
      name: 'Supplier receipt.pdf',
      mimeType: 'application/pdf',
      sizeBytes: bytes.length,
    );
    final repository = _Receipts(receipt, bytes);
    await _mount(
      tester,
      auth: _Auth(),
      load: () async => _text('unused'),
      receipts: repository,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpenseReceiptSection(expenseId: 'expense', onChanged: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.downloads, 0);
    await tester.tap(find.text('Supplier receipt.pdf'));
    await _finishRaster(tester);
    expect(find.byType(WorkloopDocumentViewerScreen), findsOneWidget);
    expect(repository.downloads, 1);
    expect(rendered.single, orderedEquals(bytes));
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading has no share action and a failed download can retry', (
    tester,
  ) async {
    var attempts = 0;
    await _mount(
      tester,
      auth: _Auth(),
      load: () async {
        if (++attempts == 1) throw StateError('network');
        return _text('Private tax estimate');
      },
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open this document. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Share'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Private tax estimate'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('a saved receipt image is visible with accessible zoom in app', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=',
    );
    await _mount(
      tester,
      auth: _Auth(),
      mime: 'image/png',
      load: () async => png,
      scale: 2,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PdfPreview), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, 'Receipt image');
    expect((image.image as MemoryImage).bytes, orderedEquals(png));
    await tester.tap(find.byTooltip('Zoom in Receipt image'));
    await tester.pumpAndSettle();
    final interactive = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      interactive.transformationController!.value.getMaxScaleOnAxis(),
      1.5,
    );
    expect(find.text('Share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace change discards an in-flight private download', (
    tester,
  ) async {
    final pending = Completer<Uint8List>();
    var workspace = 'business-a';
    final container = await _mount(
      tester,
      auth: _Auth(),
      workspace: () => workspace,
      load: () => pending.future,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    workspace = 'business-b';
    container.invalidate(workspaceIdProvider);
    await tester.pump();
    pending.complete(_text('Private prior account'));
    await tester.pumpAndSettle();
    expect(find.text('Private prior account'), findsNothing);
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace refresh hides content until its scope is confirmed', (
    tester,
  ) async {
    Future<String?> current = Future.value('business-a');
    final container = await _mount(
      tester,
      auth: _Auth(),
      workspaceFuture: () => current,
      load: () async => _text('Private report'),
    );
    await tester.pumpAndSettle();
    final share = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Share'))
        .onPressed!;
    final pending = Completer<String?>();
    current = pending.future;
    container.invalidate(workspaceIdProvider);
    expect(container.read(workspaceIdProvider).isLoading, isTrue);
    await tester.pump();
    expect(find.text('Private report'), findsNothing);
    expect(find.text('Share'), findsNothing);
    share();
    await tester.pump();
    pending.complete('business-a');
    await tester.pumpAndSettle();
    expect(find.text('Private report'), findsOneWidget);
    expect(find.text('Could not share this copy. Try again.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sign-out clears already loaded content even before workspace refresh',
    (tester) async {
      final auth = _Auth();
      await _mount(
        tester,
        auth: auth,
        load: () async => _text('Confidential report'),
      );
      await tester.pumpAndSettle();
      final share = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Share'))
          .onPressed!;
      expect(find.text('Confidential report'), findsOneWidget);
      auth.user = null;
      auth.events.add(AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();
      expect(find.text('Confidential report'), findsNothing);
      expect(find.text('Share'), findsNothing);
      share();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'malformed PDF explains render failure while retaining explicit export',
    (tester) async {
      failRaster = true;
      await _mount(
        tester,
        auth: _Auth(),
        mime: 'application/pdf',
        load: () async => _text('malformed'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not display this PDF. Try again or share a copy.'),
        findsOneWidget,
      );
      expect(find.text('Share'), findsOneWidget);
      expect(tester.takeException(), 'Could not parse document');
    },
  );
}
