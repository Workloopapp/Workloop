# Booking request date and time prefill — 7 September 2026

Status: app source implemented and focused verification passed. The parent is running the integrated analysis/test/build pass for local build 14. No live customer booking, email send, migration, deployment or TestFlight upload was performed by this fix.

## Confirmed cause

The reported request said `2026-09-11 at 07:41`, while Confirm booking showed tomorrow at 09:00. These were two different data paths:

- The current marketing website's `app/[handle]/booking-request-form.tsx` generated `preferredTimeText` from its manual date and time inputs, but populated `requestedFor` and `requestedTimezone` only when the customer chose a suggested slot. This is a current manual-entry path, not evidence that all affected records are historical.
- The existing Edge function accepts that text-only compatibility path and stores it without a structured instant or timezone.
- The app displayed the preferred text under Asked for, but initialized confirmation from `requestedFor` alone. If that field was absent, it silently initialized tomorrow at 09:00.

The Flutter public-profile form already submits a structured instant and its profile timezone. The coordinated website-origin correction is owned by the website agent/parent; its publish status is separate from this app fix.

## Resulting behavior

- A saved structured request is authoritative, even if its display text disagrees. Leaving its date/time unchanged preserves the original UTC instant, including seconds and either occurrence of the autumn repeated hour.
- Text in the exact public-form format `YYYY-MM-DD at HH:mm` now prepopulates the matching date and time. For the reported London example, confirmation displays **11/09/2026, 07:41** and submits **2026-09-11T06:41:00.000Z**. It never substitutes the phone's local timezone.
- If an older/text-only request omitted its timezone, the existing repository reads the timezone from **that request's workspace**. Missing, invalid or unavailable settings fail visibly with retry. There is no hardcoded London fallback or new database field.
- An ISO date without a time preserves its date and asks the owner to choose the time. Freeform or ambiguous date text requires explicit choices; impossible dates and spring clock-change gaps cannot normalize silently into another date/time.
- A legacy clock time that occurs twice shows a compact occurrence selector. The owner must choose the agreed first/second occurrence. These contextual timezone/UTC-offset labels are retained because they distinguish otherwise identical clock times.
- The existing contact/service/price controls, bundle snapshots, schedule warning, overlap approval, confirmation/email outcome handling and idempotent retry remain in place. A form consistently uses its captured request, so a widget refresh cannot combine another request ID with the current draft.
- A delayed timezone lookup checks that the source route and request are still current before opening the sheet. It does not open a confirmation over a different screen. The repository discards a legacy timezone lookup if the authenticated user changed during the read.

## Files and reasons

| File | Reason |
| --- | --- |
| `lib/features/public_profile/booking_request_time.dart` | Strict compatibility resolver, calendar validation, explicit real-instant candidates and repeated-hour labels. |
| `lib/features/public_profile/booking_requests_screen.dart` | Use the resolved request for initial fields and submission; honest manual-choice/retry states; retain one captured request throughout the draft. |
| `lib/shared/repositories/profile_repository.dart` | Scoped read of a missing request timezone using the existing workspace settings and authentication boundary. |
| `test/booking_request_time_test.dart` | Exact screenshot format, international date boundary, structured precedence, invalid/freeform/date-only input, spring gaps and autumn folds. |
| `test/booking_request_conversion_recovery_test.dart` | Actual form prefill and submitted instant; failed save/retry; explicit manual selection and fold choice; missing-zone retry and hidden-route safety; existing conversion/draft/accessibility behavior. |
| `test/booking_time_repository_test.dart` | Real mocked HTTP path from legacy text through workspace lookup to the existing workflow's UTC start/end payload, plus saved/missing/invalid zone behavior. |

## Verification

- Scoped Dart analysis: **clean**, `/tmp/workloop-legacy-request-time-analyze.log`.
- Final focused batch: **79 passed**, `/tmp/workloop-legacy-request-time-final-tests.log`. It includes the three booking suites above, `ui_audit_public_profile_test.dart` and all six existing light/dark shared-sheet goldens in `golden/shared_sheet_experience_golden_test.dart`. No golden baseline was changed.
- The final mechanical captured-request closure cleanup was then analyzed clean and included in the parent's full-suite run. The parent should append its final receipt; the 79-test result is not a claim that this later integrated run has finished.
- Scoped `git diff --check`: clean. Dirty work was preserved; baseline status is `/tmp/workloop-legacy-request-time-start-status.txt`.

## Limits and follow-up

- A legacy request never recorded a timezone. Its current workspace setting is the available business-time authority; the app cannot reconstruct an undocumented historical timezone change. Future website requests should record an explicit instant and timezone at creation.
- This deliberately does not infer natural-language dates such as “Friday morning” or locale-ambiguous numeric dates. The owner can agree and select a precise time without losing the original customer text.
- Existing wrongly confirmed bookings are not silently rewritten. Any correction to a real booking remains an explicit owner action.
- Physical device/browser confirmation, the website-origin publish receipt, integrated full-suite results and the local build 14 install/launch remain parent verification steps. The already uploaded build 13 cannot acquire this app-source change without another build.

Suggested commit: `fix: preserve explicit booking request dates during confirmation`.
