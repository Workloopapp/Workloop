import 'package:package_info_plus/package_info_plus.dart';

abstract final class WorkloopAppInfo {
  static const name = 'Workloop';
  static String version = '1.0.0';
  static String buildNumber = '19';
  static String get versionLabel => '$version ($buildNumber)';
  static const supportEmail = 'support@workloop.uk';
  static const operatorName = 'Haani Enterprise Limited';
  static const companyNumber = '15758586';
  static const registrationJurisdiction = 'England and Wales';
  static const registeredOffice = '35 Well Lane, Batley, WF17 5HQ, England';
  static const legalEffectiveDate = '12 September 2026';
  static const privacyEffectiveDate = '12 September 2026';
  static const operatorStatement = '$name is a trading name of $operatorName.';
  static const registrationStatement =
      'Registered in $registrationJurisdiction. Company number $companyNumber.';
  static const registeredOfficeStatement =
      'Registered office: $registeredOffice.';
  static const operatorDetails =
      '$operatorStatement\n$registrationStatement\n$registeredOfficeStatement\n'
      'For support, email $supportEmail.';
  static const privacyUrl = 'https://workloop.uk/privacy.html';
  static const termsUrl = 'https://workloop.uk/terms.html';
  static const accountDeletionUrl = 'https://workloop.uk/delete-account.html';

  static Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final platformVersion = packageInfo.version.trim();
      final platformBuildNumber = packageInfo.buildNumber.trim();
      if (platformVersion.isNotEmpty) version = platformVersion;
      if (platformBuildNumber.isNotEmpty) {
        buildNumber = platformBuildNumber;
      }
    } catch (_) {
      // Keep the pubspec fallbacks above if platform metadata is unavailable.
      // App launch and support access must not fail because diagnostics did.
    }
  }
}
