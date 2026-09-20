/// Formats a stored currency amount for editing without losing pence.
///
/// Whole-pound values stay compact (`49`) while fractional values retain
/// exactly two decimal places (`49.50`). Currency values are rounded to the
/// two decimal places that the product can meaningfully collect and display.
String currencyInputValue(num? amount) {
  if (amount == null) return '';
  final value = amount.toStringAsFixed(2);
  return value.endsWith('.00') ? value.substring(0, value.length - 3) : value;
}

/// Formats an amount in pounds while preserving any pence.
String formatPounds(num amount) => '£${currencyInputValue(amount)}';

/// Compare totals at the same penny precision shown to the business owner.
double roundToPence(double amount) =>
    amount.isFinite ? double.parse(amount.toStringAsFixed(2)) : amount;
