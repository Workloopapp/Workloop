# Form requirements — 12 September 2026

Forms now state what is required before the owner starts entering details. Required uses stronger text; Optional stays quieter. Field names and requirements remain visible after typing and have accessible wording.

## Behaviour

- Client creation/editing requires a name; phone, email, address and extra context remain optional. The introductory copy now says this explicitly.
- New bookings require a client, service, date/time, duration and price. Existing booking edits retain their current blank-value fallbacks.
- Public requests and owner confirmation show their own current requirements. Optional email on legacy confirmation remains compatible.
- Conditional requirements follow the current state: VAT, enabled deposits, receipt values selected for use, and combined service duration.
- Invoice drafts explain which optional draft details are needed before issuing. Supplied optional values still have to pass validation.
- Days may all be off. Enabled working blocks must end after they start and must not overlap.
- Search/filter inputs and nonclearable default controls keep their existing presentation.

Booking/client relationships, validation, repositories, providers, schema and existing saved records are unchanged. This change labels the existing booking workflow; it does not add the separately discussed one-off-client booking mode.

## Changed files and reasons

### Shared controls

Reusable wrapping Required/Optional labels, accessible wording, optional extra services and logo.

- [lib/shared/widgets/additional_services_picker.dart](../../lib/shared/widgets/additional_services_picker.dart)
- [lib/shared/widgets/business_logo_editor.dart](../../lib/shared/widgets/business_logo_editor.dart)
- [lib/shared/widgets/workloop_form_field.dart](../../lib/shared/widgets/workloop_form_field.dart)

### Clients

Identify name as required and contact details as optional in the shared add/edit form; label linked task capture.

- [lib/features/clients/widgets/client_form.dart](../../lib/features/clients/widgets/client_form.dart)
- [lib/features/clients/widgets/client_tasks_tab.dart](../../lib/features/clients/widgets/client_tasks_tab.dart)

### Bookings

Label creation, editing, recurrence, cancellation and task fields according to their existing save rules.

- [lib/features/appointments/add_appointment_screen.dart](../../lib/features/appointments/add_appointment_screen.dart)
- [lib/features/appointments/add_appointment_widgets.dart](../../lib/features/appointments/add_appointment_widgets.dart)
- [lib/features/appointments/appointment_detail_screen.dart](../../lib/features/appointments/appointment_detail_screen.dart)
- [lib/features/appointments/recurring_booking_fields.dart](../../lib/features/appointments/recurring_booking_fields.dart)
- [lib/features/appointments/widgets/appointment_detail_widgets.dart](../../lib/features/appointments/widgets/appointment_detail_widgets.dart)

### Booking requests

Keep request and confirmation labels visible, with their distinct required contact and service rules.

- [lib/features/public_profile/booking_requests_screen.dart](../../lib/features/public_profile/booking_requests_screen.dart)
- [lib/features/public_profile/public_profile_screen.dart](../../lib/features/public_profile/public_profile_screen.dart)

### Tasks and notes

Label required titles/checklist items and optional task context.

- [lib/features/tasks/task_editor_widgets.dart](../../lib/features/tasks/task_editor_widgets.dart)
- [lib/features/tasks/tasks_screen.dart](../../lib/features/tasks/tasks_screen.dart)

### Note editor

State that note text is optional; attachment-only notes remain supported.

- [lib/features/notes/notes_screen.dart](../../lib/features/notes/notes_screen.dart)

### Money and documents

Label amounts, mileage, collection, deposits, tax inputs and optional context; explain draft versus issue requirements.

- [lib/features/finance/add_payment_screen.dart](../../lib/features/finance/add_payment_screen.dart)
- [lib/features/finance/documents/business_document_detail_screen.dart](../../lib/features/finance/documents/business_document_detail_screen.dart)
- [lib/features/finance/documents/business_document_editor_screen.dart](../../lib/features/finance/documents/business_document_editor_screen.dart)
- [lib/features/finance/documents/document_deposit_fields.dart](../../lib/features/finance/documents/document_deposit_fields.dart)
- [lib/features/finance/documents/document_editor_fields.dart](../../lib/features/finance/documents/document_editor_fields.dart)
- [lib/features/finance/expense_editor_screen.dart](../../lib/features/finance/expense_editor_screen.dart)
- [lib/features/finance/expense_receipt_section.dart](../../lib/features/finance/expense_receipt_section.dart)
- [lib/features/finance/mileage_screen.dart](../../lib/features/finance/mileage_screen.dart)
- [lib/features/finance/payment_collection_sheet.dart](../../lib/features/finance/payment_collection_sheet.dart)
- [lib/features/finance/receipt_review_sheet.dart](../../lib/features/finance/receipt_review_sheet.dart)
- [lib/features/finance/tax_estimate_screen.dart](../../lib/features/finance/tax_estimate_screen.dart)
- [lib/features/finance/widgets/money_editor_widgets.dart](../../lib/features/finance/widgets/money_editor_widgets.dart)
- [lib/features/finance/widgets/monthly_target_editor.dart](../../lib/features/finance/widgets/monthly_target_editor.dart)

### Forecasts

Identify optional forecast assumptions without changing calculations.

- [lib/features/reports/cashflow_widgets.dart](../../lib/features/reports/cashflow_widgets.dart)

### Account access

Keep identity, password and code requirements visible; adjust compact sign-in spacing to retain standard-phone fit.

- [lib/features/auth/auth_contact_email_screen.dart](../../lib/features/auth/auth_contact_email_screen.dart)
- [lib/features/auth/auth_screen.dart](../../lib/features/auth/auth_screen.dart)
- [lib/features/auth/mfa_screens.dart](../../lib/features/auth/mfa_screens.dart)
- [lib/features/auth/password_recovery_screen.dart](../../lib/features/auth/password_recovery_screen.dart)

### Onboarding

Label identity, service and booking inputs, optional target, and explain working-hours rules.

- [lib/features/onboarding/screens/ob_first_booking.dart](../../lib/features/onboarding/screens/ob_first_booking.dart)
- [lib/features/onboarding/screens/ob_handle.dart](../../lib/features/onboarding/screens/ob_handle.dart)
- [lib/features/onboarding/screens/ob_hours.dart](../../lib/features/onboarding/screens/ob_hours.dart)
- [lib/features/onboarding/screens/ob_profile.dart](../../lib/features/onboarding/screens/ob_profile.dart)
- [lib/features/onboarding/screens/ob_revenue_target.dart](../../lib/features/onboarding/screens/ob_revenue_target.dart)
- [lib/features/onboarding/screens/onboarding_service_editor.dart](../../lib/features/onboarding/screens/onboarding_service_editor.dart)

### Business and account settings

Propagate field requirements through shared settings controls, including conditional VAT and service-duration rules.

- [lib/features/settings/business_document_settings_screen.dart](../../lib/features/settings/business_document_settings_screen.dart)
- [lib/features/settings/widgets/business_email_contact_settings.dart](../../lib/features/settings/widgets/business_email_contact_settings.dart)
- [lib/features/settings/widgets/service_add_ons_editor.dart](../../lib/features/settings/widgets/service_add_ons_editor.dart)
- [lib/features/settings/widgets/settings_account_tab.dart](../../lib/features/settings/widgets/settings_account_tab.dart)
- [lib/features/settings/widgets/settings_business_tab.dart](../../lib/features/settings/widgets/settings_business_tab.dart)
- [lib/features/settings/widgets/settings_helpers.dart](../../lib/features/settings/widgets/settings_helpers.dart)

### Working-hours editor

Clarify that all days may be off, and enabled blocks require valid start/end times without overlaps.

- [lib/features/profile/working_hours_editor.dart](../../lib/features/profile/working_hours_editor.dart)

### Imports

State required name-column mapping, calendar selection and client linkage.

- [lib/features/imports/calendar_import_screen.dart](../../lib/features/imports/calendar_import_screen.dart)
- [lib/features/imports/csv_import_screen.dart](../../lib/features/imports/csv_import_screen.dart)

### Tests and visual references

The new shared-field tests check persistent labels, accessible requirement wording and wrapping at 2.5× text in light/dark appearances. Existing UI tests locate the updated labels and complete scrolling/layout before tapping; their save, validation and retry assertions remain.

- [test/booking_edit_audit_regression_test.dart](../../test/booking_edit_audit_regression_test.dart)
- [test/booking_request_conversion_recovery_test.dart](../../test/booking_request_conversion_recovery_test.dart)
- [test/client_document_workflow_test.dart](../../test/client_document_workflow_test.dart)
- [test/email_settings_section_test.dart](../../test/email_settings_section_test.dart)
- [test/expense_tax_audit_test.dart](../../test/expense_tax_audit_test.dart)
- [test/form_field_requirements_test.dart](../../test/form_field_requirements_test.dart)
- [test/golden/onboarding_service_editor_golden_test.dart](../../test/golden/onboarding_service_editor_golden_test.dart)
- [test/settings_account_safety_test.dart](../../test/settings_account_safety_test.dart)
- [test/stripe_payments_contract_test.dart](../../test/stripe_payments_contract_test.dart)
- [test/ui_audit_onboarding_test.dart](../../test/ui_audit_onboarding_test.dart)
- [test/ui_audit_public_profile_test.dart](../../test/ui_audit_public_profile_test.dart)

Reviewed appearance references were refreshed only for the affected forms:

- [test/golden/files/auth-ios-dark-hierarchy.png](../../test/golden/files/auth-ios-dark-hierarchy.png)
- [test/golden/files/auth-ios-light-hierarchy.png](../../test/golden/files/auth-ios-light-hierarchy.png)
- [test/golden/files/auth-login.png](../../test/golden/files/auth-login.png)
- [test/golden/files/auth-register.png](../../test/golden/files/auth-register.png)
- [test/golden/files/client-form.png](../../test/golden/files/client-form.png)
- [test/golden/files/onboarding-hours-dark.png](../../test/golden/files/onboarding-hours-dark.png)
- [test/golden/files/onboarding-hours-light.png](../../test/golden/files/onboarding-hours-light.png)
- [test/golden/files/onboarding-service-editor-dark.png](../../test/golden/files/onboarding-service-editor-dark.png)
- [test/golden/files/onboarding-service-editor-light.png](../../test/golden/files/onboarding-service-editor-light.png)
- [test/golden/files/sheet-confirmation-dark.png](../../test/golden/files/sheet-confirmation-dark.png)
- [test/golden/files/sheet-confirmation-light.png](../../test/golden/files/sheet-confirmation-light.png)

Canonical rules are appended in [UIDesignSystem](../UIDesignSystem.md), [DecisionsLog](../DecisionsLog.md), and [CurrentState](../CurrentState.md).

## Verification

All commands used the real checkout with `source scripts/dev_env.sh` (Flutter 3.44.8 / Dart 3.12.2).

| Check | Result |
| --- | --- |
| Dart formatting | Passed for the 59 changed Dart files |
| `flutter analyze` | No issues found |
| `flutter test --dart-define-from-file=.env` | 1,349 passed; 1 skipped |
| Reviewed golden updates | 11 affected light/dark form references; final full suite passed |
| `flutter build ios --profile --dart-define-from-file=.env` | Passed; development-signed `build/ios/iphoneos/Runner.app`, 80.5 MB |
| `git diff --check` | Passed |

The suite includes compact sign-in, keyboard/legal navigation, booking editing and retry, public requests, document/payment workflows, working-hours layouts, and shared requirement labels with enlarged text and semantics.

Local verification logs:

- `/tmp/workloop-required-final-analyze.log`
- `/tmp/workloop-required-final-tests.log`
- `/tmp/workloop-required-final-ios-build.log`

The initial run caught a 49-point compact sign-in overflow introduced by persistent labels. Compact spacing was adjusted while retaining the control sizes. Older field finders and screenshot references were then updated to match the reviewed labels. The final checks use the resulting implementation.

## Risks and follow-up

Labels are presentation metadata that must stay aligned with future validation changes. Keep conditional rules and draft/issue helpers in sync when changing a form. Physical-device form entry and manual VoiceOver/TalkBack review remain follow-up checks. This receipt covers local source and build verification; no store upload or phone installation was requested.

## Suggested commit

`Clarify required and optional fields across app forms`
