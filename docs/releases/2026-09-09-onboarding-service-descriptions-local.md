# Onboarding service descriptions — local fix, 9 September 2026

Onboarding previously had no service-description input. Its request mapper and
database implementation also omitted the existing description field, so adding
only a visible input would still lose the text when setup completed.

The editor now accepts optional multiline descriptions, prefills them for edits,
and supports clearing them. A short preview appears in the service list. Shared
labels sit above the inputs, and help text explains that the description is
customer-facing. Description text survives draft restoration and the existing
onboarding save request; blank values become null and internal line breaks remain.

Regression checks also exposed controllers being disposed while the closing
sheet still used them. The editor now owns its controllers in widget state and
disposes them when the sheet is actually removed.

## Files and reasons

| Files | Reason |
| --- | --- |
| `lib/features/onboarding/screens/ob_services.dart` | Open the editor and show descriptions in service previews. |
| `lib/features/onboarding/screens/onboarding_service_editor.dart` | Keep input state alive for the sheet lifecycle; add the optional multiline field and shared labels. |
| `lib/shared/repositories/onboarding_repository.dart` | Include normalized descriptions in the existing JSON service rows. |
| `supabase/migrations/20260909082604_persist_onboarding_service_descriptions.sql` | Write descriptions into the existing column inside the original onboarding transaction. No new column, table, wrapper or privilege change. |
| `supabase/tests/database/032_onboarding_service_descriptions.test.sql` | Protect optional values, line breaks, retries, rollback, permissions and service-duration limits. |
| `test/onboarding_improvements_test.dart`, `test/shared/providers/onboarding_provider_test.dart`, `test/ui_audit_onboarding_test.dart` | Protect add/edit/clear/cancel, legacy drafts, save payloads and compact keyboard access. |
| `test/golden/onboarding_service_editor_golden_test.dart` and its two images | Review the complete modal in light and dark with phone safe areas. |

## Verification

After `source scripts/dev_env.sh`, analysis passed with no issues, the full
`flutter test --dart-define-from-file=.env` suite passed **1,204 tests** with ten
existing skips, and `flutter build ios --profile --dart-define-from-file=.env`
passed (79.8 MB). The 18 focused onboarding tests passed. Both screenshot
candidates were visually reviewed before accepting their baselines, and the
full suite subsequently compared them. `git diff --check` passed.

The isolated SQL harness replayed **102 migrations** and passed **63 assertions**
across suites 003, 013, 021 and 032. This includes 19 new description checks and
the existing security, verified-email and duration checks. The runtime was
PGlite 0.5.8 (PostgreSQL 18.3), with explicit Supabase Auth table/GUC, cron and
Vault stubs. This verifies SQL behavior; it does not simulate GoTrue, PostgREST,
scheduled delivery or an authenticated production onboarding session.

The initial interaction checks exposed the real controller lifecycle bug,
which was fixed. Test-only input-scroll timing and an absent preferences mock
were then corrected without weakening the assertions. The final checks above
passed on the resulting source.

Previews: [dark](../../test/golden/files/onboarding-service-editor-dark.png) and
[light](../../test/golden/files/onboarding-service-editor-light.png). These are
widget renders, not phone captures. Local verification logs and SQL/source
comparison evidence are saved under `build/service-description-checks/`.
Physical-device keyboard/VoiceOver checks were not repeated. The profile build
retains the existing nonblocking Swift Package Manager adoption warnings for
`device_calendar` and `flutter_local_notifications`.

## Data and release boundary

The existing owner service repository, `Service` model, `get-public-profile`
response and public-profile UI already support descriptions; they need no
change. The hosted private function was inspected read-only. Removing only the
new description insert from this migration leaves a body that matches the live
function byte for byte. Its SECURITY INVOKER mode, empty search path and existing
ACL remain intact; the public verified-email, MFA and deletion guards are intact.

No production mutation, app installation, version bump or TestFlight upload is
part of this fix. Deploy the migration with the next combined release before
distributing the app that sends descriptions. Source remains `1.0.0+19`; the
previously uploaded build does not contain this fix.

Suggested commit: `fix: preserve service descriptions during onboarding`
