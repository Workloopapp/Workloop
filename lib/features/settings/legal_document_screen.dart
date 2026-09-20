import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/workloop_app_info.dart';
import '../../shared/widgets/slate_ui.dart';

enum WorkloopLegalDocument { privacy, terms }

class LegalDocumentScreen extends StatelessWidget {
  final WorkloopLegalDocument document;
  final String backSemanticLabel;

  const LegalDocumentScreen({
    super.key,
    required this.document,
    this.backSemanticLabel = 'Back to app preferences',
  });

  @override
  Widget build(BuildContext context) {
    final content = document == WorkloopLegalDocument.privacy
        ? _privacySections
        : _termsSections;
    final title = document == WorkloopLegalDocument.privacy
        ? 'Privacy policy'
        : 'Terms of use';
    final publicUrl = document == WorkloopLegalDocument.privacy
        ? WorkloopAppInfo.privacyUrl
        : WorkloopAppInfo.termsUrl;
    final effectiveDate = document == WorkloopLegalDocument.privacy
        ? WorkloopAppInfo.privacyEffectiveDate
        : WorkloopAppInfo.legalEffectiveDate;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                AppSpacing.screenTop,
                AppSpacing.pageX,
                AppSpacing.xxl,
              ),
              children: [
                WorkloopRouteHeader(
                  title: title,
                  backSemanticLabel: backSemanticLabel,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Effective $effectiveDate',
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                for (var index = 0; index < content.length; index++) ...[
                  _LegalSection(section: content[index]),
                  if (index != content.length - 1)
                    const SizedBox(height: AppSpacing.lg),
                ],
                const SizedBox(height: AppSpacing.xl),
                WorkloopPrimaryButton(
                  label: 'Open public copy',
                  icon: LucideIcons.externalLink,
                  secondary: true,
                  onPressed: () => _openPublicCopy(context, publicUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPublicCopy(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The public legal page could not be opened'),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  final _LegalContent section;

  const _LegalSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return WorkloopSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            section.body,
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalContent {
  final String title;
  final String body;

  const _LegalContent(this.title, this.body);
}

const _privacySections = <_LegalContent>[
  _LegalContent(
    '1. Who this policy covers',
    '${WorkloopAppInfo.operatorStatement} ${WorkloopAppInfo.registrationStatement} ${WorkloopAppInfo.registeredOfficeStatement} This policy explains how we handle personal data when a solo service business owner uses the Workloop app, public profile, or support channels. ${WorkloopAppInfo.operatorName} is the data controller for account administration, service security, diagnostics, Workloop communications and support information. For support and privacy questions, email ${WorkloopAppInfo.supportEmail}.',
  ),
  _LegalContent(
    '2. Data you provide',
    'We process account details, business profile and service information, working hours, client records, bookings, tasks, notes, income and expense records, and support messages. If you join the Workloop launch list, we process your email address, consent time and signup source to send a welcome receipt and relevant beta or launch access updates. A customer who submits a public booking request provides their name, phone number, email address, requested service or time, and any message. If the business accepts that request, Workloop uses the email address to send the customer a booking confirmation and scheduled reminders on behalf of the business, and retains it with the request and client record. If you use Stripe payment collection, Workloop also stores connected-account and transaction references, amounts, currency, status, receipt links, and refund or dispute status needed to show and reconcile payments. When a customer asks for a contactless-payment receipt, the email address you enter is sent to Stripe for receipt delivery and may be associated with the payment record. Workloop does not receive or store full card numbers or card security codes. If you choose a device import, Workloop reads the relevant contacts or calendar events on your device to present a review list, then adds only the records you confirm to your workspace. File imports process only the files you select.',
  ),
  _LegalContent(
    'Business records and receipt reading',
    'Business records can also include quote and invoice details, payment terms and deposits, receipt attachments, mileage journeys and reviewed tax-estimate inputs. Receipt reading takes place on your device. Workloop does not send receipt content to an OCR service or store the raw recognised text. Details you choose to apply become part of the expense record. Saved receipt attachments are uploaded to private workspace storage.',
  ),
  _LegalContent(
    '3. How data is used',
    'Data is used to authenticate you, provide and secure your workspace, connect business records into daily workflows, create exports, support public booking requests, answer support enquiries, prevent abuse, and meet legal obligations. We do not sell personal data. The current release contains no advertising SDK.',
  ),
  _LegalContent(
    'Email preferences and useful updates',
    'Essential account and booking messages are sent automatically. Workloop tips, product updates, referral ideas and inactivity reminders use consent or a qualifying customer relationship with an opt-out offered at signup. Every marketing email includes an unsubscribe link, and you can change your choice in Settings > Emails to you. We record this choice and recent app activity to avoid irrelevant reminders. We do not enrol your clients in Workloop marketing because they make a booking. Customers can stop booking reminders from the link in those emails without cancelling their booking.',
  ),
  _LegalContent(
    'Optional local weather',
    'Local weather is off until you enable it. If you choose Use my location, Workloop asks your phone for a foreground location and reduces its precision before sending it over an authenticated connection to our Supabase server function. That function requests a forecast from MET Norway using the reduced-precision coordinates; it does not pass your Workloop identity or device IP address to MET Norway. Weather locations are not saved in your business workspace or used for advertising, and weather does not track your device in the background. You may instead choose a UK area: the address or postcode query is sent to Google Places, and the area you choose is remembered only on this device, separately for each account, for less than 30 days. Weather responses are held in temporary caches. Tap the weather beside your Today greeting to change the area or turn weather off. Phone location permission can also be changed in your device settings.',
  ),
  _LegalContent(
    'Crash diagnostics',
    'Supported releases use Google Firebase Crashlytics to help us find and fix app failures. Reports include technical crash details, code locations, app version, operating system and device information, and installation or session identifiers. These reports are not fully anonymous. Workloop limits reports from its app code to fixed error categories and code locations rather than original error messages or customer content. Reports collected by native software may contain technical exception details and cannot undergo that same filtering. We do not add Workloop account IDs, client records or a history of screens visited and actions taken to Crashlytics reports. Google processes diagnostics under its Firebase data practices at https://firebase.google.com/support/privacy.',
  ),
  _LegalContent(
    '4. Legal bases',
    'Where UK or EU data-protection law applies, processing is based on performing our service contract, legitimate interests in operating and securing Workloop, legal obligations, and consent where a device permission or optional feature asks for it. Device permissions can be changed in your operating-system settings.',
  ),
  _LegalContent(
    '5. Service providers and sharing',
    'Supabase provides authentication, database, storage, and server functions. Resend processes email addresses and message content to deliver account, security, booking and eligible marketing emails under its privacy policy at https://resend.com/legal/privacy-policy. UK2/Stackmail hosts our support inbox. Stripe processes card payments, connected-account verification, payouts, refunds, disputes, and requested receipt delivery when you enable payment collection; Stripe receives payment, identity, and any customer receipt email you supply under its own privacy terms at https://stripe.com/gb/privacy. Google Places may process an address search query when you use address lookup or choose a weather area, subject to Google’s privacy policy at https://policies.google.com/privacy. MET Norway provides local forecasts using the reduced-precision coordinates sent by our weather server, subject to its privacy policy at https://www.met.no/en/About-us/privacy. Apple, Google, or your chosen device app may process information when you deliberately open a contact, calendar, map, email, or file action. We disclose data when legally required or when needed to protect users and the service.',
  ),
  _LegalContent(
    '6. Your clients’ information',
    'The business using Workloop decides which client information is entered and how it is used, and remains the data controller for its own client records. ${WorkloopAppInfo.operatorName} processes those records on that business’s behalf to provide Workloop. The business remains responsible for having a lawful reason to use the information, keeping it accurate and responding to its clients’ rights. If you are a customer of a business using Workloop, contact that business directly about your booking or its use of your information. Do not store unnecessary sensitive information in free-text fields.',
  ),
  _LegalContent(
    '7. Retention and deletion',
    'Workspace data is kept while your account is active and as needed to provide the service. You can export your workspace and request account deletion from Settings > Privacy & data. Deletion removes the account and workspace through a protected server process, subject to limited records that must be kept for security, dispute, tax, or other legal reasons and normal backup expiry cycles.',
  ),
  _LegalContent(
    '8. Security',
    'Workloop uses authenticated access, workspace isolation, database row-level security, encrypted network transport, and protected server functions. No online service can promise absolute security, so use a strong unique password and protect access to your device.',
  ),
  _LegalContent(
    '9. Your rights',
    'Depending on where you live, you may ask to access, correct, export, restrict, object to, or erase personal data. You may also complain to your local supervisory authority; in the United Kingdom this is the Information Commissioner’s Office. Contact support@workloop.uk to exercise a right.',
  ),
  _LegalContent(
    '10. International processing',
    'Service providers may process data outside your country. Where required, appropriate contractual or legal safeguards are used for international transfers.',
  ),
  _LegalContent(
    '11. Children',
    'Workloop is a business product and is not directed to children. It must not be used by anyone under 18 to create an account.',
  ),
  _LegalContent(
    '12. Changes',
    'We may update this policy as Workloop changes. Material changes will be communicated in the app or through the account contact details where appropriate.',
  ),
  _LegalContent(
    '13. Subscription access',
    'For a Workloop subscription purchased through Apple or Google, we store the store transaction reference, product, expiry, renewal or refund status and its association with your Workloop account to verify access. The store handles billing; Workloop does not receive your full payment-card details. We also keep verified trial dates, subscription reminder records and any lifetime beta-access grant. We use your account email to send service reminders about an upcoming trial renewal.',
  ),
];

const _termsSections = <_LegalContent>[
  _LegalContent(
    '1. Agreement',
    'These terms are between you and ${WorkloopAppInfo.operatorName}, the operator of Workloop. ${WorkloopAppInfo.operatorStatement} ${WorkloopAppInfo.registrationStatement} ${WorkloopAppInfo.registeredOfficeStatement} In these terms, “we”, “us” and “our” mean ${WorkloopAppInfo.operatorName}. By creating an account or using the service, you agree to these terms and confirm that you are at least 18 and able to enter a binding agreement. For support, email ${WorkloopAppInfo.supportEmail}.',
  ),
  _LegalContent(
    '2. The service',
    'Workloop is a mobile-first business operating system for solo service businesses. It organises business records and workflows but does not replace professional legal, tax, accounting, medical, or financial advice.',
  ),
  _LegalContent(
    '3. Your account',
    'Provide accurate information, keep your login secure, and tell us promptly about suspected unauthorised access. You are responsible for activity under your account and for keeping your contact details current.',
  ),
  _LegalContent(
    '4. Business and client data',
    'You retain ownership of content you enter. You give Workloop the limited permission needed to host, process, back up, and display it to operate the service. You are responsible for the legality, accuracy, and permissions for client records, public profile content, and messages you submit.',
  ),
  _LegalContent(
    '5. Acceptable use',
    'Do not use Workloop unlawfully, to harm or mislead others, to upload malicious code, to probe or bypass security, to scrape the service, to interfere with other users, or to store content you have no right to process.',
  ),
  _LegalContent(
    '6. Public profiles and booking requests',
    'You are responsible for services, prices, availability, claims, and contact information you publish. A booking request is not automatically a confirmed contract with your client; you remain responsible for confirming the booking and your own customer terms. Your business provides the booked service to your customer; ${WorkloopAppInfo.operatorName} provides the Workloop software and does not become the provider of that service.',
  ),
  _LegalContent(
    '7. Card payments',
    'Card collection is provided through Stripe and requires an eligible, verified connected account. You remain responsible for the services you sell, accurate prices and descriptions, customer communications, receipts, taxes, lawful refunds, and responding to disputes with appropriate evidence. Stripe controls payment acceptance, account verification, payout timing and availability, and may apply reserves, reversals, restrictions, or fees under its own agreement. Workloop is not a bank or payment institution and cannot guarantee that a payment, refund, dispute outcome, or payout will complete by a particular time.',
  ),
  _LegalContent(
    '8. Availability and exports',
    'We work to keep Workloop reliable but cannot guarantee uninterrupted availability. Maintain any records your business is legally required to keep and use the workspace export in Settings > Privacy & data as part of your own continuity process.',
  ),
  _LegalContent(
    '9. Third-party services',
    'Features may open or depend on services such as Supabase, Stripe, Google Places, MET Norway, maps, contacts, calendars, files, and email. Workloop includes Google Maps features and content; their use is subject to the Google Maps/Google Earth Additional Terms at https://maps.google.com/help/terms_maps/ and Google Privacy Policy at https://policies.google.com/privacy. Local weather uses MET Norway forecast data under the Creative Commons Attribution 4.0 licence at https://creativecommons.org/licenses/by/4.0/. Workloop presents this data as rounded temperatures and illustrated conditions. Forecasts can differ from actual conditions. Stripe payment services are subject to the connected-account and payment terms you accept with Stripe. Other third-party services have their own terms and availability.',
  ),
  _LegalContent(
    '10. Intellectual property',
    'Workloop’s software, visual identity, text, and service design are protected by intellectual-property law. These terms give you a personal, limited, revocable, non-transferable right to use the app for your business; they do not transfer ownership of Workloop.',
  ),
  _LegalContent(
    '11. Suspension and termination',
    'You may stop using Workloop and request account deletion. We may restrict or end access where reasonably necessary for security, illegal use, material breach, or protection of the service or others. Where practical, we will give notice and an opportunity to export data.',
  ),
  _LegalContent(
    '12. Liability',
    'Nothing in these terms excludes liability that cannot legally be excluded. To the extent permitted by law, Workloop is not responsible for indirect or consequential loss, lost profit, or business decisions made from records entered by a user. Consumer rights that apply to you remain unaffected.',
  ),
  _LegalContent(
    '13. Law, changes, and contact',
    'These terms are governed by the laws of England and Wales, subject to any mandatory rights in your home country. We may update them as the service changes and will communicate material changes where appropriate. Questions can be sent to support@workloop.uk.',
  ),
  _LegalContent(
    '14. Trials and subscriptions',
    'Eligible new Apple subscribers can start a one-month free trial by authorising the subscription with Apple. The trial starts when Apple confirms it, and automatically renews as a paid monthly subscription unless cancelled. The current UK monthly price is £14.99; Apple displays your local price, trial eligibility and billing terms before you confirm. Creating a Workloop account alone does not start a trial or authorise a charge. If you are not eligible for the introductory offer, the store displays the paid subscription terms before purchase.',
  ),
  _LegalContent(
    'Renewal, cancellation and reminders',
    'Cancel an Apple free trial at least 24 hours before it ends to avoid the first charge. You can manage or cancel from Your Workloop plan or your Apple subscription settings. When trial reminders are available for your plan, we aim to send email reminders seven and three days before a verified trial ends, but delivery may be delayed or fail; the renewal date shown by Apple applies whether or not a reminder arrives. Subscriptions renew automatically unless cancelled and are subject to the relevant store’s billing, cancellation and refund rules. Deleting the Workloop app or account does not cancel an Apple or Google subscription; cancel it in your store settings. Existing annual subscribers retain their store-managed billing period unless they change or cancel their plan.',
  ),
  _LegalContent(
    'Existing beta access and your records',
    'Existing beta testers with a lifetime access grant keep free lifetime access linked to their Workloop account. This means access for the lifetime of the Workloop service, not a cash value or a transferable purchase. An existing 30-day trial already started under our earlier terms is honoured until its recorded end date, with no automatic charge from that trial. New accounts do not receive that separate trial in addition to an Apple introductory offer. Export and account-deletion controls remain available after a trial or subscription ends. Stripe fees for collecting payments from your own customers are separate from the Workloop subscription.',
  ),
];
