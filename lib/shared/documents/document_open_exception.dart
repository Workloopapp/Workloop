/// An actionable, customer-safe error from a local document generator.
class DocumentOpenException implements Exception {
  final String message;
  const DocumentOpenException(this.message);
}
