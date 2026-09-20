enum AuthFormIntent { signIn, signUp, resetPassword }

const minimumWorkloopPasswordLength = 12;

const workloopPasswordLengthMessage =
    'Password must be at least $minimumWorkloopPasswordLength characters.';
const workloopPasswordStrengthMessage =
    'Include uppercase, lowercase, a number, and a symbol.';

bool isValidAuthEmail(String value) {
  final email = value.trim();
  if (email.isEmpty || email.length > 254) return false;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

/// Keep the country code explicit; guessing one could send an SMS to someone
/// else. Spaces, brackets and hyphens are only presentation characters.
String? normalizedAuthPhone(String value) {
  final phone = value.trim().replaceAll(RegExp(r'[\s()\-]'), '');
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone) ? phone : null;
}

String? validateAuthForm({
  required String email,
  required String password,
  required AuthFormIntent intent,
}) {
  if (email.trim().isEmpty) return 'Enter your email address.';
  if (!isValidAuthEmail(email)) return 'Enter a valid email address.';
  if (intent == AuthFormIntent.resetPassword) return null;
  if (password.isEmpty) return 'Enter your password.';
  if (intent == AuthFormIntent.signUp &&
      password.length < minimumWorkloopPasswordLength) {
    return workloopPasswordLengthMessage;
  }
  if (intent == AuthFormIntent.signUp && !isStrongWorkloopPassword(password)) {
    return workloopPasswordStrengthMessage;
  }
  return null;
}

String? validateNewPasswordPair(String password, String confirmation) {
  if (password.length < minimumWorkloopPasswordLength) {
    return workloopPasswordLengthMessage;
  }
  if (!isStrongWorkloopPassword(password)) {
    return workloopPasswordStrengthMessage;
  }
  if (password != confirmation) return 'The passwords do not match.';
  return null;
}

bool isStrongWorkloopPassword(String password) {
  return RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'\d').hasMatch(password) &&
      RegExp(r'''[!@#$%^&*()_+\-=\[\]{};'":|<>?,./`~\\]''').hasMatch(password);
}

String friendlyAuthErrorMessage(String rawMessage) {
  final message = rawMessage.toLowerCase();
  if (message.contains('user is banned') || message.contains('user_banned')) {
    return 'This account is currently unavailable. If you requested deletion, wait for completion and check your email. Otherwise, contact Workloop support.';
  }
  if (message.contains('token has expired') ||
      message.contains('otp_expired') ||
      message.contains('invalid otp') ||
      message.contains('invalid token')) {
    return 'That code or link is invalid or has expired. Request a new one.';
  }
  if (message.contains('invalid login') ||
      message.contains('invalid credentials')) {
    return 'Wrong email or password.';
  }
  if (message.contains('email not confirmed')) {
    return 'Please confirm your email before signing in.';
  }
  if (message.contains('already registered') ||
      message.contains('already been registered')) {
    return 'An account already exists for that email. Try signing in.';
  }
  if (message.contains('pwned') || message.contains('leaked')) {
    return 'That password has appeared in a known data breach. Choose a unique password.';
  }
  if (message.contains('password') && message.contains('weak')) {
    return workloopPasswordStrengthMessage;
  }
  if (message.contains('rate limit') || message.contains('too many')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  return 'We could not complete that request. Check your details and try again.';
}
