import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/receipt_extraction.dart';
import 'package:workloop/features/finance/receipt_text_service.dart';

void main() {
  final today = DateTime(2026, 9, 8);
  ReceiptExtraction parse(String text) =>
      extractReceiptText(text, today: today);
  test('labelled receipt total wins over subtotal VAT cash and change', () {
    final result = parse(
      'ACME Supplies\nReceipt No: A123\nDate: 2026-09-07\nSubtotal £20.00\nVAT £4.00\nTOTAL £24.00\nCASH £50.00\nCHANGE £26.00',
    );
    expect(result.amountMinor?.value, 2400);
    expect(result.date?.value, DateTime(2026, 9, 7));
    expect(result.currency, 'GBP');
    expect(result.supplier?.value, 'ACME Supplies');
    expect(result.reference?.value, 'A123');
    expect(
      result.amountMinor?.confidence,
      ReceiptSuggestionConfidence.labelled,
    );
    expect(
      result.supplier?.confidence,
      ReceiptSuggestionConfidence.needsReview,
    );
  });
  test('separated total line and grouped pennies are supported', () {
    expect(
      parse('Supplier Ltd\nGRAND TOTAL\nGBP 1,234.56').amountMinor?.value,
      123456,
    );
    expect(
      parse('Supplier Ltd\nTOTAL including VAT £60.00').amountMinor?.value,
      6000,
    );
  });
  test(
    'conflicting total values remain manual rather than choosing the largest',
    () {
      final result = parse('ACME\nTOTAL £10.00\nTOTAL £12.00');
      expect(result.amountMinor, isNull);
      expect(result.ambiguousAmount, true);
      expect(result.warnings.join(' '), contains('Several different totals'));
      expect(
        parse('ACME\nTOTAL £10.00\nTOTAL PAID £10.00').amountMinor?.value,
        1000,
      );
    },
  );
  test(
    'VAT totals savings excluded prices and unlabelled values are not purchase totals',
    () {
      for (final line in [
        'TOTAL VAT £20.00',
        'TOTAL SAVINGS £20.00',
        'TOTAL ITEMS £20.00',
        'TOTAL EXCLUDING VAT £20.00',
        'SUBTOTAL £20.00',
        'BALANCE £20.00',
        '£200.00',
        'TOTALIZER £20.00',
        'TOTAL -£20.00',
        'TOTAL 1.234,56',
      ]) {
        expect(parse(line).amountMinor, isNull, reason: line);
      }
    },
  );
  test('accounting credit totals cannot become positive purchases', () {
    for (final total in [
      '(£20.00)',
      '£(20.00)',
      '(GBP 20.00)',
      '£20.00-',
      '£20.00 CR',
      '20.00CR',
      'REFUND £20.00',
      'RETURNED £20.00',
      'CREDIT £20.00',
    ]) {
      final result = parse('ACME\nTOTAL $total');
      expect(result.amountMinor, isNull, reason: total);
      expect(
        result.warnings.join(' '),
        contains('refund or credit note'),
        reason: total,
      );
    }
    expect(parse('TOTAL (£20.00)\nTOTAL £10.00').amountMinor, isNull);
    expect(parse('REFUND\nACME\nTOTAL £20.00').amountMinor, isNull);
    expect(parse('TOTAL £20.00 CREDIT CARD').amountMinor?.value, 2000);
    expect(parse('TOTAL £20.00 (including VAT)').amountMinor?.value, 2000);
  });
  test('foreign mixed and unidentified currencies are distinct from GBP', () {
    expect(parse('TOTAL EUR 10,50').currency, 'EUR');
    expect(parse('TOTAL EUR 10,50').amountMinor?.value, 1050);
    expect(parse('TOTAL €10.50').foreignCurrency, true);
    expect(parse(r'TOTAL $10.50').foreignCurrency, true);
    expect(parse('TOTAL £10.50\nUSD equivalent 12.00').foreignCurrency, true);
    expect(parse('TOTAL 10.50').currency, isNull);
  });
  test(
    'ambiguous numeric and conflicting dates stay flagged for manual review',
    () {
      final ambiguous = parse('Date 08/09/2026\nTOTAL £12.00');
      expect(ambiguous.date?.value, DateTime(2026, 9, 8));
      expect(ambiguous.ambiguousDate, true);
      expect(
        parse('Date 2026-09-07\nTransaction date 2026-09-08').date,
        isNull,
      );
      expect(parse('Date 31/12/25').ambiguousDate, false);
      expect(parse('Date 7 September 2026').date?.value, DateTime(2026, 9, 7));
    },
  );
  test('invalid dates are rejected and future dates explained', () {
    expect(parse('Date 31/02/2026').date, isNull);
    expect(
      parse('Date 2026-09-10').warnings.join(' '),
      contains('in the future'),
    );
    expect(
      parse('Date 2026-09-07\nDue date 2026-10-07').date?.value,
      DateTime(2026, 9, 7),
    );
  });
  test('invoice and credit-note text does not imply a paid purchase', () {
    expect(
      parse('INVOICE\nTOTAL £10.00').warnings.join(' '),
      contains('when you have paid'),
    );
    final credit = parse('CREDIT NOTE\nACME\nTOTAL £10.00');
    expect(credit.amountMinor, isNull);
    expect(credit.warnings.join(' '), contains('original expense'));
  });
  test('receipt reference formats and safe money input keep precision', () {
    expect(parse('Receipt No 0027').reference?.value, '0027');
    expect(parse('Invoice # INV-20').reference?.value, 'INV-20');
    expect(receiptAmountMinor('12.5'), 1250);
    expect(receiptAmountMinor('12.50'), 1250);
    expect(receiptAmountMinor('0.00'), isNull);
    expect(receiptAmountMinor('NaN'), isNull);
    expect(receiptAmountMinor('-10'), isNull);
    expect(receiptAmountMinor('12.501'), isNull);
    expect(receiptAmountMinor('1,2.50'), isNull);
    expect(receiptAmountMinor('1,200.50'), 120050);
    expect(parse('Date 7 Sept 2026').date?.value, DateTime(2026, 9, 7));
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('workloop/receipt_text');
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final file = ReceiptFile.checked(
    'receipt.jpg',
    Uint8List.fromList([255, 216, 255]),
  );
  tearDown(() => binding.setMockMethodCallHandler(channel, null));
  test(
    'native bridge sends only selected receipt bytes and exposes partial PDF status',
    () async {
      binding.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'recognize');
        expect(call.arguments, {'bytes': file.bytes, 'mimeType': 'image/jpeg'});
        return {'text': 'TOTAL £12.00', 'pageCount': 7, 'processedPages': 5};
      });
      final result = await ReceiptTextService().recognize(file);
      expect(result.text, 'TOTAL £12.00');
      expect(result.isPartial, true);
      expect(result.pageCount, 7);
    },
  );
  test(
    'native truncation is disclosed even when every page was processed',
    () async {
      binding.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': 'TOTAL £12.00',
          'pageCount': 1,
          'processedPages': 1,
          'textTruncated': true,
        },
      );
      final result = await ReceiptTextService().recognize(file);
      expect(result.textTruncated, true);
      expect(result.isPartial, true);
    },
  );
  test('native empty or locked receipts give a manual fallback', () async {
    binding.setMockMethodCallHandler(channel, (_) async => {'text': ''});
    await expectLater(
      ReceiptTextService().recognize(file),
      throwsA(isA<ReceiptRecognitionException>()),
    );
    binding.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'receipt_locked'),
    );
    await expectLater(
      ReceiptTextService().recognize(file),
      throwsA(
        isA<ReceiptRecognitionException>().having(
          (e) => e.message,
          'explanation',
          contains('password protected'),
        ),
      ),
    );
  });
  test('missing native bridge keeps manual receipt entry available', () async {
    await expectLater(
      ReceiptTextService().recognize(file),
      throwsA(
        isA<ReceiptRecognitionException>().having(
          (e) => e.message,
          'explanation',
          contains('enter the details'),
        ),
      ),
    );
  });
}
