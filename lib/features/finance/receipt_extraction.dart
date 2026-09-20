/// Conservative suggestions from on-device text. Nothing here proves payment,
/// tax allowability or OCR accuracy; the owner reviews before applying fields.
enum ReceiptSuggestionConfidence { labelled, needsReview }

class ReceiptSuggestion<T> {
  final T value;
  final String source;
  final ReceiptSuggestionConfidence confidence;
  const ReceiptSuggestion(this.value, this.source, this.confidence);
}

class ReceiptExtraction {
  final ReceiptSuggestion<int>? amountMinor;
  final ReceiptSuggestion<DateTime>? date;
  final ReceiptSuggestion<String>? supplier;
  final ReceiptSuggestion<String>? reference;
  final String? currency;
  final bool ambiguousAmount;
  final bool ambiguousDate;
  final List<String> warnings;
  const ReceiptExtraction({
    this.amountMinor,
    this.date,
    this.supplier,
    this.reference,
    this.currency,
    this.ambiguousAmount = false,
    this.ambiguousDate = false,
    this.warnings = const [],
  });
  bool get foreignCurrency => currency != null && currency != 'GBP';
}

int? receiptAmountMinor(String value) {
  final input = value.trim();
  if (!RegExp(
    r'^(?:\d{1,10}|\d{1,3}(?:,\d{3}){1,3})(?:\.\d{1,2})?$',
  ).hasMatch(input)) {
    return null;
  }
  final normalized = input.replaceAll(',', '');
  if (!RegExp(r'^\d{1,10}(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final minor =
      int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return minor > 0 ? minor : null;
}

ReceiptExtraction extractReceiptText(String text, {required DateTime today}) {
  final lines = text
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .take(2000)
      .toList();
  final currencies = <String>{};
  final full = lines.join('\n').toUpperCase();
  if (full.contains('£') || RegExp(r'\bGBP\b').hasMatch(full)) {
    currencies.add('GBP');
  }
  if (full.contains('€') || RegExp(r'\bEUR\b').hasMatch(full)) {
    currencies.add('EUR');
  }
  for (final currency in [
    'USD',
    'CAD',
    'AUD',
    'NZD',
    'CHF',
    'JPY',
    'CNY',
    'INR',
    'AED',
    'ZAR',
  ]) {
    if (RegExp('\\b$currency\\b').hasMatch(full)) currencies.add(currency);
  }
  if (full.contains(r'$') &&
      !currencies.any((c) => ['USD', 'CAD', 'AUD', 'NZD'].contains(c))) {
    currencies.add('dollar currency');
  }
  if (full.contains('¥') && !currencies.any((c) => c == 'JPY' || c == 'CNY')) {
    currencies.add('yen/yuan');
  }
  final currency = currencies.length == 1
      ? currencies.single
      : currencies.isEmpty
      ? null
      : 'mixed currencies';
  final totals = <int, String>{};
  var creditTotal = false;
  final amountPattern = RegExp(
    r'(?<![\d.,])(?:£|€|\$|GBP\s*|EUR\s*|USD\s*)?((?:\d{1,3}(?:,\d{3})+|\d{1,10})[.,]\d{2})(?![\d.,])',
    caseSensitive: false,
  );
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final label = RegExp(
      r'^(?:GRAND\s+TOTAL|TOTAL\s+(?:PAID|AMOUNT|DUE)|AMOUNT\s+(?:PAID|DUE)|TOTAL)\b\s*[:=]?\s*',
      caseSensitive: false,
    ).firstMatch(line);
    if (label == null ||
        RegExp(
          r'\b(?:SAVINGS|DISCOUNT|ITEMS|EXCL|EXCLUDING|BEFORE|THIS PAGE|CARRIED)\b|^TOTAL\s+(?:VAT|TAX)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      continue;
    }
    var valueLine = line.substring(label.end);
    if (valueLine.trim().isEmpty && i + 1 < lines.length) {
      valueLine = lines[i + 1];
    }
    // Never pick the largest number: conflicting labelled totals require review.
    final matches = amountPattern.allMatches(valueLine).toList();
    final hasCreditNotation = RegExp(
      r'[-−]\s*(?:£|€|\$|[A-Z]{3}\s*)?\s*\d|\(\s*(?:£|€|\$|[A-Z]{3}\s*)?\s*\d[\d.,]*\s*(?:[A-Z]{3})?\s*\)|\d[\d.,]*\s*(?:[-−]|CR\b)|\b(?:CR|REFUND(?:ED|S)?|RETURN(?:ED|S)?|CREDIT(?!\s+CARD))\b',
      caseSensitive: false,
    ).hasMatch(valueLine);
    if (hasCreditNotation) {
      creditTotal = true;
      continue;
    }
    if (matches.length != 1) {
      continue;
    }
    final raw = matches.single.group(1)!;
    // A comma decimal is only unambiguous when it is the final separator.
    final normalized = raw.contains('.') ? raw : raw.replaceAll(',', '.');
    final amount = receiptAmountMinor(normalized);
    if (amount != null) {
      totals[amount] =
          line + (valueLine == line.substring(label.end) ? '' : '\n$valueLine');
    }
  }

  final dates = <DateTime, String>{};
  final labelledDates = <DateTime, String>{};
  for (final line in lines) {
    if (RegExp(
      r'\b(?:DUE|EXPIR|VALID UNTIL|DELIVERY)\b',
      caseSensitive: false,
    ).hasMatch(line)) {
      continue;
    }
    for (final date in _receiptDates(line)) {
      dates[date] = line;
      if (RegExp(
        r'\b(?:DATE|PAID|PURCHASED|TRANSACTION)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        labelledDates[date] = line;
      }
    }
  }
  final preferredDates = labelledDates.isNotEmpty ? labelledDates : dates;
  final date = preferredDates.length == 1 ? preferredDates.keys.single : null;
  final numericDateUncertain =
      date != null &&
      RegExp(
        r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2}|\d{2})\b',
      ).allMatches(preferredDates[date]!).any((m) {
        final first = int.parse(m[1]!);
        final second = int.parse(m[2]!);
        return first <= 12 && second <= 12 && first != second;
      });
  final creditNote = lines
      .take(5)
      .any(
        (line) => RegExp(
          r'^(?:CREDIT NOTE|REFUND RECEIPT|RETURN RECEIPT)\b|^(?:REFUND|RETURN)\s*$',
          caseSensitive: false,
        ).hasMatch(line),
      );
  ReceiptSuggestion<String>? supplier;
  for (final line in lines.take(7)) {
    if (line.length < 3 ||
        line.length > 80 ||
        !RegExp(r'[A-Za-z]{3}').hasMatch(line) ||
        RegExp(
          r'^(?:RECEIPT|INVOICE|TAX INVOICE|CUSTOMER COPY|MERCHANT COPY|THANK YOU|WELCOME|DATE|TIME|TOTAL|VAT|TEL|PHONE|WWW\.|HTTP)',
          caseSensitive: false,
        ).hasMatch(line) ||
        RegExp(r'\d{3}|@|£|€|\$').hasMatch(line)) {
      continue;
    }
    supplier = ReceiptSuggestion(
      line,
      line,
      ReceiptSuggestionConfidence.needsReview,
    );
    break;
  }
  ReceiptSuggestion<String>? reference;
  for (final line in lines) {
    final match = RegExp(
      r'\b(?:RECEIPT|INVOICE|TRANSACTION|REFERENCE|REF)(?:\s*(?:NO\.?|NUMBER|ID)\s*[:#\-]?|\s*[:#\-])\s*([A-Z0-9][A-Z0-9\-/]{1,39})\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) {
      reference = ReceiptSuggestion(
        match.group(1)!,
        line,
        ReceiptSuggestionConfidence.labelled,
      );
      break;
    }
  }
  final warnings = <String>[
    if (totals.length > 1)
      'Several different totals were found. Check the receipt and enter the amount paid.',
    if (preferredDates.length > 1)
      'Several receipt dates were found. Choose the date you actually paid.',
    if (numericDateUncertain)
      'The numeric date could use day/month or month/day. Check the actual paid date.',
    if (date != null &&
        date.isAfter(DateTime(today.year, today.month, today.day)))
      'The receipt date is in the future. Choose the actual paid date yourself.',
    if (currency != null && currency != 'GBP')
      '$currency was found. Convert the expense and enter its GBP amount yourself.',
    if (currency == null)
      'No currency was identified. Confirm pounds sterling before using an amount.',
    if (RegExp(
      r'\b(?:INVOICE|AMOUNT DUE|BALANCE DUE)\b',
      caseSensitive: false,
    ).hasMatch(full))
      'This may be an invoice. Only record an expense when you have paid it.',
    if (creditNote || creditTotal)
      'This looks like a refund or credit note. Review the original expense instead of adding another purchase.',
  ];
  return ReceiptExtraction(
    amountMinor: totals.length == 1 && !creditNote && !creditTotal
        ? ReceiptSuggestion(
            totals.keys.single,
            totals.values.single,
            ReceiptSuggestionConfidence.labelled,
          )
        : null,
    date: date == null
        ? null
        : ReceiptSuggestion(
            date,
            preferredDates[date]!,
            labelledDates.isNotEmpty
                ? ReceiptSuggestionConfidence.labelled
                : ReceiptSuggestionConfidence.needsReview,
          ),
    supplier: supplier,
    reference: reference,
    currency: currency,
    ambiguousAmount: totals.length > 1,
    ambiguousDate: preferredDates.length > 1 || numericDateUncertain,
    warnings: warnings,
  );
}

Iterable<DateTime> _receiptDates(String line) sync* {
  DateTime? checked(int year, int month, int day) {
    if (year < 2000 ||
        year > 2100 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  for (final m in RegExp(
    r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b',
  ).allMatches(line)) {
    final value = checked(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (value != null) yield value;
  }
  for (final m in RegExp(
    r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2}|\d{2})\b',
  ).allMatches(line)) {
    final rawYear = int.parse(m[3]!);
    final value = checked(
      rawYear < 100 ? 2000 + rawYear : rawYear,
      int.parse(m[2]!),
      int.parse(m[1]!),
    );
    if (value != null) yield value;
  }
  const months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  for (final m in RegExp(
    r'\b(\d{1,2})\s*[-/]?\s*(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s*[-/,]?\s*(20\d{2}|\d{2})\b',
    caseSensitive: false,
  ).allMatches(line)) {
    final rawYear = int.parse(m[3]!);
    final value = checked(
      rawYear < 100 ? 2000 + rawYear : rawYear,
      months.indexOf(m[2]!.substring(0, 3).toLowerCase()) + 1,
      int.parse(m[1]!),
    );
    if (value != null) yield value;
  }
}
