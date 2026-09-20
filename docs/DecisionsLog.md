# Workloop Decisions Log

Last updated: 2026-08-06

This log consolidates Notion decisions, Git history, and codebase reality.

## August 2026 - Studio Composition Uses One Shell-Clearance Contract

Decision:

Keep the approved Workloop Studio identity and floating four-tab dock, while
making page, section and component spacing ownership explicit. Shell content
clearance is calculated from the 72-point dock, its 12-point offset, the real
device bottom safe area and 22 points of visual breathing room. Pushed routes
without the shell do not inherit that clearance.

The supplied purple `W` artwork is the mobile launcher icon and the supplied
purple `workloop` wordmark is the native launch artwork. Native launch canvases
use the artwork's exact `#6362EB` background.

Reasoning:

Fixed padding allowed the dock to cover resting content on gesture-safe-area
devices, while nested page, section and child spacing made the approved Studio
composition feel swollen. Explicit ownership preserves the visual direction
without changing routes, retained state or workflows.

Consequences:

- Home, Clients, Bookings, Tools and retained Money, Tasks and Notes share the
  calculated shell inset.
- Home hero text uses explicit on-hero semantic roles in Light and Dark.
- Schedule/Requests remains the primary Bookings mode; Today/Upcoming/Past is
  a quieter secondary filter.
- App-icon and splash changes require native profile builds on both platforms.

## July 2026 - Brand Lime Is A Highlight, Not Light-Theme Ink

Status: Superseded by the 2026-07-26 exact-neon decision below. The contrast
principle remains, but the brand accent itself is now `#C1FF72` in both
appearances.

Decision:

Keep `#C1FF72` as Workloop's recognisable brand highlight, but use deep green `#3F6513` for accent text, thin icons, outlines, focus rings, and progress indicators on light surfaces.

Reasoning:

The bright lime did not maintain readable contrast against white or its own pale selected-state washes, especially in compact navigation labels and thin operational icons.

Consequences:

- Solid lime controls use dark `#17200D` foreground content.
- Light-theme selected controls pair a soft lime wash with deep-green content.
- Dark/OLED mode retains lime foreground accents where the background provides sufficient contrast.
- Theme tests enforce the core contrast pairs at WCAG AA normal-text level.

## May 2026 - Slate Is Focused On Solo Appointment Businesses

Decision:

Slate serves solo appointment-based service businesses first.

Reasoning:

Notion product vision identifies this ICP as the clearest wedge: users have repeated bookings, clients, payments, notes, and daily admin pain.

Consequences:

- V1 prioritises clients, bookings, money, tasks, dashboard, profile, notifications.
- Projects, team/staff, marketplace, generic productivity, advanced analytics, and AI-first workflows are parked.

## May 2026 - Core Loop Is Client -> Booking -> Work -> Payment -> Repeat

Decision:

Every major feature must support the operating loop.

Reasoning:

This keeps Slate from becoming an everything app.

Consequences:

- Dashboard is an HQ.
- Clients, bookings, tasks, and payments are connected.
- Feature proposals are filtered against daily business utility.

## May 2026 - Do Not Rebuild Slate

Decision:

Continue refactoring and building in place.

Reasoning:

Notion technical audit found Slate is already a functioning early MVP with real architecture, onboarding, business logic, and backend integration.

Consequences:

- Architecture is improved incrementally.
- Existing table names are preserved.
- Major rewrites are avoided unless they remove real risk.

## May 2026 - Supabase + Riverpod + Flutter Remain The Stack

Decision:

Keep Flutter, Riverpod, and Supabase.

Reasoning:

This stack supports mobile-first UX, quick iteration, auth, Postgres, RLS, and future Edge Functions.

Consequences:

- Supabase repositories are the backend boundary.
- Riverpod providers are the app state boundary.
- Flutter remains the only app UI implementation.

## May 2026 - Move Secrets To Dart Defines

Decision:

Supabase URL/key are loaded from `.env` through `--dart-define-from-file=.env`.

Reasoning:

Avoid hardcoded environment values and prepare for separate environments.

Consequences:

- `.env` is not committed.
- `.env.example` documents required values.
- Client publishable key is accepted in app bundle; service-role key is forbidden.

## May 2026 - RLS Is Mandatory

Decision:

All workspace-owned tables should have RLS.

Reasoning:

Application bugs must not expose cross-workspace data.

Consequences:

- `supabase/rls_policies.sql` was added.
- Live tables now have RLS enabled.
- Remaining work is policy cleanup/performance, not basic RLS enablement.

## May 2026 - User-Facing Language Changed From Appointments/Invoices To Bookings/Money

Decision:

Use Bookings and Money in product language while preserving `appointments` and `invoices` backend names.

Reasoning:

Bookings/Money are more natural for solo service users. Renaming live DB tables would add risk without enough benefit.

Consequences:

- UI says Bookings and Money.
- Internal code still contains appointment/invoice names.
- Docs must explicitly explain this translation.

## May 2026 - Tasks Need Deliberate Completion

Decision:

Avoid one-tap accidental task completion.

Reasoning:

Tasks can be business-critical. Completion should be intentional.

Consequences:

- Task rows open detail/actions.
- Completion can happen through sheet/action/swipe.
- Checklists and reminders were added.

## May 2026 - Bottom Nav Must Include Tasks

Decision:

Tasks became a first-class bottom-nav tab.

Reasoning:

Users should not have to scroll Dashboard to reach daily tasks.

Consequences:

- Main tabs are Home, Clients, Bookings, Money, Tasks.
- FAB remains for creation actions.

## May 2026 - UI Moved Through Several Theme Experiments

Decision:

Final current direction is neutral northbound greys with glass navigation.

Reasoning:

Pure dark was too harsh; pastel was too light; green-tinted grey felt wrong. Current palette uses soft grey hierarchy and premium neutral surfaces.

Consequences:

- `AppColors` are light neutral greys.
- Some legacy token names remain.
- UI design system needs this documented so future work does not drift.

## May 2026 - Public Profile V1 Is Request Booking, Not Full Slot Selection

Decision:

Public profile ships with static profile/service information and manual booking request.

Reasoning:

Full public slot-selection requires availability engine, conflict detection, confirmations, and more failure states.

Consequences:

- `/p/:handle` exists.
- Booking requests are stored and triaged in-app.
- Owner confirms manually.

## May 2026 - Calendar Sync Starts As A Contained Integration

Decision:

Calendar sync is represented by a contained screen/state and ICS export, not scattered booking logic.

Reasoning:

Avoid premature deep integration while still providing export utility.

Consequences:

- `CalendarSyncScreen`, `CalendarSyncRepository`, `calendar_sync_accounts`, and `buildSlateIcs`.
- True external provider sync remains future work.

## 2026-05-30 - Foundation Hardening

Decision:

Repository layer, schema contract, RLS docs, env setup, tests, and Git baseline were introduced before heavy feature expansion.

Reasoning:

The user explicitly paused feature expansion to strengthen the foundation.

Consequences:

- GitHub remote is connected.
- Commits and pushes happen regularly.
- `docs/foundation.md`, `docs/security.md`, `supabase/schema_contract.sql`, and `supabase/rls_policies.sql` exist.

## 2026-05-30 - Major UX Passes

Decision:

Dashboard, core layouts, tasks, bookings, and CRM were elevated with stronger UX.

Reasoning:

The app was functional but felt too generic/blocky.

Consequences:

- Dashboard was reorganized around revenue, pulse, schedule, tasks.
- Tasks gained templates, reminders, checklists, detail sheets.
- Bookings gained calendar, next booking, location, custom services, inline client creation, edit flow.
- CRM was expanded, then simplified after user feedback.

## 2026-05-31 - Money Tracking Expansion

Decision:

Money should track paid, unpaid, expenses, weekly target, and comparisons.

Reasoning:

The user compared against an older prototype and identified current Money as insufficient.

Consequences:

- `expenses` table/model/repository/provider added.
- Money screen tracks paid, unpaid, expenses, profit, target progress, comparisons.
- Weekly target derives from monthly onboarding/settings target.

## 2026-05-31 - Project Memory Created

Decision:

Create durable `/docs` memory for product, architecture, database, UI, current state, roadmap, Notion sync, and constitution.

Reasoning:

Prevent loss of project knowledge between threads.

Consequences:

- Future feature work should start from these docs.
- Notion remains product truth unless code has clearly superseded it.

## 2026-07-07 - UI Refounded Around Whitespace First

Decision:

Workloop's visual system should use whitespace, typography, alignment, and subtle dividers as the default grouping tools. Cards and heavy surfaces should become exceptions, not the default layout primitive.

Reasoning:

Real-device review showed that even after polish, the app still felt too boxed, too card-heavy, and too visually equal-weighted for the premium Apple/Linear/Notion-inspired product target.

Consequences:

- Shared UI primitives now include token-aware list rows and filter chips.
- Header stats should read as inline metrics rather than boxed mini cards.
- Activity feeds, clients, notes, bookings, tasks, and money summaries should prefer row/divider layouts.
- Lime is the active/accent system; module colours should be secondary semantic hints only.
- A light/dark token foundation exists, but full dark mode remains gated on migrating static `AppColors` usage.

## 2026-07-07 - Workloop Primitives Become Canonical

Decision:

Use `Workloop*` as the canonical screen-facing UI primitive layer for the final minimal premium system while keeping existing `Slate*` classes as compatibility foundations.

Reasoning:

The product needs one durable UI vocabulary across primary screens, bottom navigation, filters, metrics, rows, empty states, and actions. Renaming the screen-facing layer to Workloop makes the design system explicit without rewriting the app architecture or changing workflows.

Consequences:

- `lib/shared/widgets/slate_ui.dart` now exposes `WorkloopPage`, `WorkloopPageHeader`, `WorkloopMetricItem`, `WorkloopListRow`, `WorkloopSegmentedControl`, `WorkloopBottomNav`, `WorkloopFAB`, and related primitives.
- Primary screens now reference the canonical primitives for shared UI patterns.
- Locally hand-built segmented controls in Bookings and Settings have been replaced by `WorkloopSegmentedControl`.
- Dark mode remains staged, not enabled, until local static-colour widgets are migrated.

## 2026-07-15 - Primary Navigation Reduced To Four Destinations

Decision:

Use Home, Clients, Bookings, and More as the four bottom-navigation destinations. Move Money, Tasks, Notes, Profile, and Settings into More, remove the global floating create action, and place creation at the top of each create-capable feature.

Reasoning:

The six-destination navigation plus detached floating action was visually crowded and made creation feel disconnected from its feature context. A four-item navigation keeps the operating core legible while More preserves one-tap access to secondary modules. Feature-local creation makes the destination and resulting workflow unambiguous.

Consequences:

- Money, Tasks, and Notes retain their full existing screens and deep links, with More highlighted in the bottom navigation.
- Clients, Bookings, Money, Tasks, and Notes use the shared compact top action pattern.
- Dashboard provides minimal Tasks and Notes shortcuts so frequent capture and follow-up remain close at hand.
- No database, repository, provider, or package changes are required.

## 2026-07-15 - Dashboard Prioritises Calm Daily Awareness

Decision:

Order the dashboard around the owner's day rather than large performance figures: Today first, an optional and softly worded Worth a look section, compact Money and utility access, then Coming up and Recent activity.

Reasoning:

The dashboard should clarify the day without creating anxiety. Large financial heroes, urgency language, warning colours, long lists, and repeated module previews increase cognitive load even when the underlying information is useful.

Consequences:

- Worth a look is hidden when empty and capped at two neutral rows.
- The dashboard does not surface alarming totals, red badges, or labels such as urgent.
- Today and Coming up do not duplicate bookings, and Coming up is capped at three.
- Money remains informative but visually subordinate to the day's work.
- Every actionable row opens its booking detail or owning feature.

## 2026-07-16 - Keyboard Dismissal Is App-Wide Interaction Behaviour

Decision:

Override Flutter's mobile tap-outside editing intent once at the app boundary so tapping outside any active text field dismisses the keyboard, while tapping within the field preserves focus.

Reasoning:

Search, forms, notes, tasks, bookings, settings, and onboarding should all respond consistently. Screen-specific unfocus handlers are easy to miss and make a basic mobile interaction feel unreliable.

Consequences:

- All current and future editable fields inherit the same tap-away behaviour without feature-level wiring.
- Existing field tap regions remain authoritative, so selection, cursor movement, and editing inside a field are preserved.
- Widget tests protect both outside dismissal and inside focus retention.

## 2026-07-16 - Client Portfolio Uses Three Calm Views

Decision:

Keep All, Active, and Leads as the permanent client-list views, ordered from broadest to most specific. Present them as one bottom-navigation-inspired pill control and allow horizontal screen swipes to move between adjacent views.

Reasoning:

These three views answer distinct daily questions without turning the client screen into a CRM dashboard. Inactive contacts still need to remain discoverable, but they do not justify a fourth permanent destination for most solo operators.

Consequences:

- All contains every contact, Active contains only contacts explicitly marked active, and Leads contains contacts marked as leads.
- Inactive contacts remain accessible through All and search.
- Left and right swipes change one adjacent view at a time, while short incidental horizontal movements do nothing.
- The selector shares the floating glass surface, draggable animated capsule, stepped haptics, restrained accent, and rounded geometry of the main bottom navigation.

## 2026-07-16 - Inactive Becomes A First-Class Client View

Decision:

Supersede the three-view client portfolio with All, Active, Leads, and Inactive. Keep Inactive visually neutral and make it the final adjacent destination.

Reasoning:

Inactive is already an intentional, user-maintained client status rather than an inferred segment. Giving it a dedicated view makes paused relationships reliably retrievable and keeps Active semantically accurate.

Consequences:

- The draggable selector and full-screen swipe order are All, Active, Leads, then Inactive.
- Changing views returns the screen to the top instead of retaining an irrelevant position from the previous list.
- Empty views explain their category calmly, while active searches use search-specific no-results guidance.
- Inactive rows receive a quiet text marker inside All without warning colours or attention styling.

## 2026-07-16 - Client Detail Becomes A Relationship Workspace

Decision:

Organise client detail around the next booking, relationship context, calm follow-up signals, and short recent activity. Keep bookings, money, and tasks as linked views backed by their existing repositories rather than duplicating client-only records.

Reasoning:

A long contact-details card followed by repeated module histories gives every field equal weight and hides what helps the owner act. The client workspace should answer who this is, what happens next, and whether a small follow-up is useful without behaving like a dense CRM dashboard.

Consequences:

- The overview caps recent activity and progressively discloses secondary contact metadata.
- New bookings and payments begin with the current client selected.
- Client tasks remain canonical Tasks records through `contact_id`, and the client view provides an explicit route to the full Tasks workspace.
- Financial summaries use received and remaining amounts, including partial payments, with neutral language and colour.
- The workspace reuses the dashboard backdrop, typography, spacing, dividers, and draggable capsule navigation.

## 2026-07-16 - Client Data Entry Has One Canonical Form

Decision:

Use one shared mobile client form for both creation and editing. Organise it as Contact information, Client settings, Booking address, Client notes, and progressively disclosed Additional information.

Reasoning:

Add and Edit previously used separate field components, labels, spacing, and selection controls, which allowed validation and visual behaviour to drift. Familiar CRM terminology is useful, but Workloop should retain only the fields that support the client, booking, work, payment, and repeat workflow.

Consequences:

- Add and Edit now render the same input controls, status explanations, contact preferences, optional metadata, and field ordering.
- Client name is required and optional email addresses are validated before writes.
- Matching phone numbers and email addresses are checked against existing clients to reduce accidental duplicates without requiring schema changes.
- Lead source, tags, and birthday remain optional and collapsed by default unless an edited client already contains them.
- Important notes remain distinct because they are surfaced prominently in the relationship workspace.
- The change reuses the existing contacts schema, repository, providers, and security model.

## 2026-07-16 - Booking Address Search Uses a Trusted Server Boundary

Decision:

Use Google Places API (New) for client booking-address autocomplete through an authenticated Supabase Edge Function, rather than placing a Google web-service key in Flutter.

Reasoning:

Address entry should be fast and reliable on both iOS and future Android builds. A shared server boundary keeps provider credentials out of the downloadable app, centralises UK/language restrictions and field masks, and gives Workloop one integration to secure and monitor.

Consequences:

- Add and Edit Client share the same debounced Booking address search with manual entry fallback.
- Address entry deliberately remains a single-field workflow. Users start with the first line of an address for dependable suggestions; a postcode or any other manually typed location can be saved as entered. Workloop does not attempt a fragile postcode-to-property refinement flow.
- Suggestions remain interactive while being selected or scrolled, and a chosen result populates the field before canonical Place Details resolution.
- Scrolling the surrounding client form no longer clears suggestions; results close after selection or through their explicit Close action, avoiding accidental dismissal during one-handed repositioning.
- Saved booking addresses use standards-based Apple Maps and Google Maps direction URLs. The preferred maps app is a non-critical device preference, stored locally rather than adding workspace schema solely for a platform-specific choice.
- The function accepts authenticated users only, validates and limits input, uses Google session tokens, and requests only the minimum suggestion and address fields.
- No database migration is required; the selected formatted address continues to use the existing contact `address` field.
- Google Places billing, API enablement, an API-restricted key, quotas, and a Supabase function secret are required before live suggestions work.
- Coordinates are returned but deliberately not persisted until routing needs justify a contacts schema addition.
- Unit-prefixed input searches both the building and the full text, then keeps
  the typed flat/apartment/unit label when Google only identifies the building.
  This improves subpremise entry without adding another provider or schema.
- Public legal pages must include the Google Maps terms/privacy references before release.

## 2026-07-19 - Bookings Uses One Calm Connected Workspace

Decision:

Present Bookings as a calm Schedule / Requests workspace with explicit List and Calendar modes. Reuse the same textured backdrop, typography, spacing, segmented controls, compact header action, and form surfaces established by Home and Clients while preserving the existing appointment repository and workflows.

Reasoning:

The existing booking system already supports the important operating loop, but duplicated mode controls, dashboard-like metrics, and locally styled forms made it feel like a separate product. A solo operator primarily needs to see the next commitment, move between a chronological list and calendar, and create or update work without losing client, payment, or task context.

Consequences:

- Schedule and Requests remain first-class but visually restrained destinations; List and Calendar are explicit schedule views rather than duplicate header actions.
- Today, Upcoming, and Past use the shared segmented-control behaviour and remain swipeable through the existing tab view.
- Calendar creation carries the selected day into New booking and adds a direct Today shortcut.
- New and Edit booking use the same backdrop, header hierarchy, input treatment, and keyboard dismissal conventions as client data entry.
- Selecting a client can reuse that client's saved booking address, and saved physical booking locations use the shared Maps preference for directions.
- Dashboard, client detail, booking detail, Money, and Tasks continue to share canonical records and providers; no booking-only duplicate data or database migration is introduced.

## 2026-07-19 - Selection Lists Use One Mobile Picker Pattern

Decision:

Replace Flutter's native dropdown menus with a shared Workloop picker sheet for all in-app selection fields.

Reasoning:

The platform dropdown expands into a visually heavy, desktop-style menu that does not match Workloop's calm mobile design language. A bottom sheet keeps choices within thumb reach, supports long business lists, and gives every workflow the same interaction and selection hierarchy.

Consequences:

- Short option sets use a compact rounded sheet with a clear selected state.
- Longer sets, including clients, add search automatically and remain independently scrollable.
- Picker fields, rows, typography, spacing, haptics, and dismissal behaviour come from one shared component.
- Booking, onboarding, public-profile, task, and payment selectors now use the same interaction.
- No package, database, repository, or navigation change is introduced.

## 2026-07-19 - Booking Guardrails Inform Without Blocking Intent

Decision:

Reuse the authenticated Google Places booking-address field across client and booking capture, protect changed client and booking drafts before navigation, and treat saved working hours as guidance rather than an absolute booking restriction.

Reasoning:

Physical work needs the same dependable address capture wherever it is created. Accidental navigation should not lose customer or schedule edits, while a solo operator must still be able to accept legitimate early, late, or exceptional work without changing business settings first.

Consequences:

- New and edited physical bookings use the same address search and manual fallback as client booking addresses.
- Leaving a changed New/Edit Client or New/Edit Booking screen offers Save, Discard changes, or Keep editing.
- A booking outside saved working hours explains the exception and can continue through an explicit Book anyway action.
- Appointment overlap checks remain mandatory and cannot be bypassed by the working-hours confirmation.
- Existing repositories, Supabase security, routes, schema, and booking records remain unchanged.

## 2026-07-19 - Money Uses One Calm Ledger Hierarchy

Decision:

Present Money as a quiet period overview followed by target progress, money to collect, and one chronological activity ledger. Use a dedicated shared form vocabulary for income and expenses while preserving the existing payment and expense data model.

Reasoning:

The previous screen exposed the right capabilities but stacked several competing cards, metric tiles, pills, status colours, and locally styled forms. A solo operator needs to understand money received, money spent, what remains to collect, and recent movement without reading an accounting dashboard.

Consequences:

- Received is the primary period figure; Expenses and Net are supporting metrics rather than competing cards.
- Week, Month, and Custom use the canonical Workloop segmented control.
- Weekly target progress is a slim section with secondary comparison text.
- Empty expense categories are hidden, and income/expense activity remains visible even when one record type is empty.
- Collection rows retain due and overdue meaning with restrained styling rather than alarm-heavy surfaces.
- Income and expense creation/editing use shared Money fields and protect changed drafts before navigation.
- Existing Riverpod providers, repositories, Supabase tables, RLS, booking links, client links, and CRUD capabilities remain unchanged.

## 2026-07-19 - Money Separates Income, Outgoing, and Outstanding

Decision:

Use a first-class three-section navigation bar inside Money. Income, Outgoing, and Outstanding each own their summary, supporting information, empty state, and activity list.

Reasoning:

A combined money overview remained visually calm but required users to interpret received money, spending, and collection work in one long page. These are three distinct questions with different actions and time horizons. Separating them improves scanning while keeping all three one gesture away.

Consequences:

- Income shows period-filtered received money, weekly target progress, and received-income history.
- Outgoing shows period-filtered spending, category distribution, and expense history.
- Outstanding shows all currently uncollected money, split into Upcoming and Past due without applying an arbitrary period filter.
- Dashboard follow-up links open Money with Outstanding selected.
- The large navigation capsule represents peer Money destinations; the smaller Week / Month / Custom control remains a local filter inside Income and Outgoing.
- Add/Edit Income, Add/Edit Expense, repository behavior, Supabase schema, RLS, client links, and booking links are unchanged.

## 2026-07-19 - Money Uses Plain Business Language

Decision:

Name the three Money destinations Made, Spent, and Owed. Each destination answers one question with one primary figure. Keep payment timing on individual owed rows instead of presenting Upcoming and Past due as competing summary totals.

Reasoning:

Income, Outgoing, and Outstanding describe accounting states rather than the questions a solo business owner naturally asks. Made, Spent, and Owed are faster to understand and reduce the overview to the three figures that matter.

Consequences:

- Made is sourced from received payment records in the selected period.
- Spent is sourced from expense records in the selected period.
- Owed is the remaining balance across every unpaid payment, including future and overdue payments.
- Weekly and monthly views show the matching income target, percentage complete, and amount left; custom ranges do not show a misleading target.
- Due and overdue status remains visible on individual payment rows for action context.

## 2026-07-19 - Tasks Use Dedicated Working Screens

Decision:

Present Tasks as Now, Later, and Done. Open task detail, creation, and editing as dedicated screens instead of temporary sheets.

Reasoning:

A task can carry client context, timing, reminders, priority, a checklist, and deliberate completion actions. Full screens give that work the same stable hierarchy as Clients and Bookings, while the task list can remain a lightweight scanning surface.

Consequences:

- Now groups Overdue, Today, and Anytime tasks; Later contains future work; Done contains completed work.
- Tapping a task opens one canonical detail screen with checklist and completion actions.
- New and Edit Task use the same page header, textured backdrop, spacing rhythm, top save action, and progressive disclosure as Client and Booking forms.
- Changed task drafts offer Save, Discard, or Keep editing before leaving.
- Task repositories, providers, reminders, linked clients, checklists, deliberate completion, swipe actions, and Supabase records remain unchanged.

## 2026-07-19 - Notes Keep Writing Primary

Decision:

Treat the note editor as a dedicated Workloop writing screen with the shared textured backdrop, canonical page header, and one compact labelled formatting toolbar.

Reasoning:

The plain editor canvas preserved focus but looked disconnected from every other evolved workspace, while unlabeled formatting icons and a prominent destructive header action made basic editing less obvious than necessary.

Consequences:

- Back, title, pin, secondary actions, and Done follow the same header hierarchy as Task, Client, and Booking screens.
- Delete remains available with confirmation but moves behind the secondary note-actions control.
- Checklist and bullet controls show concise labels and selected state without covering the writing area.
- Link insertion and link-specific styling are intentionally removed; existing saved note text is not migrated or rewritten.
- Existing note parsing, checklist interaction, pinning, Supabase persistence, and routes remain unchanged.

## 2026-07-19 - Profile Is An Overview, Not Another Settings Form

Decision:

Give Profile its own calm owner-and-business overview backed by existing account, workspace, profile, settings, service, and booking-request providers. Profile owns business editing; Settings remains reserved for alerts, account security, and app preferences.

Reasoning:

The previous Profile entry simply opened Business settings, so it did not meet the familiar mobile expectation that a profile should explain who is signed in, which business is active, what clients can see, and where related account controls live. Sending Profile edits into a screen titled Settings also made both destinations feel duplicated.

Consequences:

- Profile presents business identity, a small operational snapshot, and Business and Online sections in the current Workloop design language. Personal account controls remain exclusively in Settings.
- The owner's preferred name is editable alongside business name and industry in Business Info because it is part of how the business workspace identifies its owner, without exposing account controls in Profile.
- Business details, Services, Working hours, and Public profile are presented as dedicated Profile-owned screens that reuse one established implementation underneath.
- Working hours use a direct full-screen editor and iOS-style scrolling time wheels, avoiding the redundant summary-screen-to-modal flow and Material clock face.
- Booking requests are compact list records that open a focused detail screen; this preserves scanability while keeping lifecycle actions and conversion details available on demand.
- Public profile previews opened from Profile use loaded authenticated workspace data on the same navigation stack and expose an explicit back action. Standalone public deep links remain self-contained and use the secured Edge Function.
- Settings is a calm overview that opens dedicated Account, Notifications, and App preferences screens. It no longer duplicates Profile routes or unfinished feature placeholders.
- Profile-link copying uses the platform clipboard without adding a sharing package.
- No Supabase schema, RLS, repository contract, or CRUD path changes.

## 2026-07-19 - Final Polish Uses One Honest Product System

Decision:

Treat the final application pass as a consolidation of Workloop's existing operating-system workflow, not a collection of isolated redesigns. Use one semantic light/dark theme, shared textured shell, shared interaction primitives, progressive onboarding, real-record activation guidance, and explicit capability labels across every module.

Reasoning:

Workloop should feel calm and premium because its behaviour and hierarchy are predictable. Visual consistency without behavioural consistency would leave users carrying the same mental load. Similarly, presenting imports, notifications, or calendar connections as live when only part of the pipeline exists would damage trust.

Consequences:

- The approved `#C1FF72` accent, spacing, type, shape, depth, motion, haptic, field, picker, sheet, dialog, loading, error, and empty-state treatments are centralised.
- System, Light, and OLED-aware Dark modes share semantic roles rather than per-screen colour fixes.
- New-user setup progress is computed from existing client, booking, and payment data and can be permanently dismissed.
- Contacts, calendar snapshots, client CSV, task text, and note text/Markdown are the supported import surfaces; unsupported private OS/app stores are not advertised.
- Notifications remain explicitly in-app until a real push/local scheduling delivery layer exists.
- Calendar import and ICS export do not imply continuous two-way sync.
- No new Supabase schema or unverified optional feature was introduced during this pass.
- `docs/FinalPolishAudit.md` is the release truth table for supported, unavailable, and externally dependent capability states.

## 2026-07-22 - Appearance Is A First-Class App Setting

Decision:

Expose System, Light, and Dark selection through a dedicated App appearance destination, and apply appearance changes atomically instead of animating theme and compatibility colours on different frames.

Reasoning:

Appearance is a device-level choice rather than a general app preference. Keeping it beside maps and calendar obscured that distinction, while the previous compatibility-palette update could leave parts of a screen briefly using the outgoing theme.

Consequences:

- Settings shows App appearance as its own destination with the current choice described in the row.
- App preferences now contains only maps, calendar, and product information under Apps and connections.
- Manual and system appearance changes resolve one effective brightness before the app tree builds.
- Theme animation is disabled and colour-animating controls are keyed by brightness so semantic tokens, textured surfaces, system chrome, and legacy adaptive colours switch together.
- Light and Dark palettes use opaque, contrast-tested semantic text roles and more distinct surface/divider roles; disabled colours are not used for essential information.
- No persistence contract, navigation route, or Supabase schema changes.

## 2026-07-22 - Contrast Comes From Surface Hierarchy And A Confident Brand Accent

Status: Superseded in part by the 2026-07-26 exact-neon decision below. The
neutral surface hierarchy remains; forest/mint are no longer the brand accent.

Decision:

Replace the pale lime-on-white visual system with an appearance-aware forest/mint accent, a neutral page canvas, crisp elevated surfaces, opaque selected controls, tighter display type, and denser page spacing.

Reasoning:

Repeated local contrast fixes left the application washed out because the root causes were shared: white pages and cards blended together, translucent lime selections lost legibility, oversized offsets weakened hierarchy, and module-specific pastels made the product feel inconsistent. A premium calm interface needs fewer colours, but the colours it keeps must be decisive and accessible.

Consequences:

- Light mode uses a `#F3F5F2` canvas, white surfaces, dark green-black text, and a deep forest `#246B4E` brand accent.
- Dark mode uses layered charcoal surfaces and a mint `#75C99A` brand accent.
- Active bottom navigation, workspace rails, segmented controls, filter chips, primary buttons, and picker checks use opaque accent fills with contrast-safe foregrounds.
- Shared headers, fields, cards, rows, empty states, sheets, and navigation use stronger surface separation, smaller display type, and reduced page padding.
- Clients, Bookings, booking requests, and More remove one-off pale treatments and inherit the same visual system.
- No schema, RLS, repository, or navigation contract changes are introduced.

## 2026-07-26 - The Icon Neon Is The Product Accent

Decision:

Use the exact icon and launch-artwork neon `#C1FF72` as Workloop's brand accent
in System, Light, and Dark appearances. Keep neutral surfaces and use
contrast-safe foreground roles instead of replacing the neon with a different
brand colour.

Reasoning:

The icon and launch artwork already establish the strongest recognisable part
of Workloop's identity. A separate forest accent inside the product weakened
that continuity. The accessibility issue is not the neon itself; it is using
neon as small text on light surfaces or placing light content on a neon fill.

Consequences:

- Primary fills, selected controls, navigation emphasis, switches, progress,
  icon/launch surfaces, and restrained highlights use `#C1FF72`.
- Content on a neon fill uses dark `#17200D`.
- Small accent text, focus outlines, and thin icons on light surfaces use the
  deeper `#4D7317` accent-ink role; Dark mode can use the neon directly.
- Inter is bundled with its licence so typography is deterministic offline.
- Theme tests lock the exact neon and contrast-critical foreground pairs.

## 2026-07-26 - Launch Integrations Must Be Useful And Honest

Decision:

Ship real on-device task and booking reminders and one-time calendar import/
`.ics` export. Do not describe either capability as remote push or live
calendar sync.

Reasoning:

The useful launch promise is a reminder that works on the owner's phone and a
portable calendar file the owner deliberately saves. APNs/FCM delivery and
continuous provider sync introduce operational and failure modes that are not
ready to promise.

Consequences:

- iOS and Android request notification permission only when the workflow needs
  it, schedule future task/booking reminders locally, reconcile changes, and
  route notification taps into Workloop.
- Remote cross-device push remains future work.
- Calendar access supports explicit reviewed import only.
- Calendar export is a point-in-time `.ics` file that can be saved or copied;
  no provider account or two-way connection is created.
- Store copy and reviewer notes must preserve these distinctions.

## 2026-07-26 - Multi-Record Workflows Are Atomic And Retry-Safe

Decision:

Create tasks with their initial checklist, create/convert bookings with their
related records, and complete bookings with payment handling through bounded
transactional RPCs. Reuse stable idempotency keys across retries. For
record-by-record imports, remove successful records from the retry set.

Reasoning:

Sequential mobile writes can be interrupted after only part of a business
workflow succeeds. Blindly retrying can then create duplicate clients,
bookings, payments, tasks, or checklist items. Both outcomes damage trust.

Consequences:

- Private workflow implementations authenticate the caller and validate
  workspace ownership and linked-record tenancy before writing.
- Booking conflict checks are serialised per workspace.
- Completed workflow retries return the stored result instead of writing again.
- Booking-request conversion updates the request in the same transaction as the
  booking and selected related records.
- Contacts, calendar, CSV, task-text, and note-text imports retain only failed
  records for retry after a partial attempt.
- The launch migrations and current Edge Function versions are recorded
  explicitly. Their structural/grant checks passed; production-like workflow,
  abuse, and destructive deletion tests remain release gates.

## 2026-07-26 - Workloop 1.0 Is A Portrait-First Mobile Release

Decision:

Launch Workloop 1.0 simultaneously on iOS and Android with an iPhone-only
portrait target on iOS and portrait orientation on Android. Standardise the
build baseline on Flutter 3.44.8, Android target/compile API 36, minimum
Android API 24, Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.20,
and Java 17.

Reasoning:

The current information architecture and interaction design are intentionally
phone-first. Constraining the first release avoids presenting unverified
tablet/landscape layouts while still supporting both mobile ecosystems.

Consequences:

- iOS targets device family 1 and portrait orientation with iOS 13 as the
  deployment floor.
- Android locks the main activity to portrait and uses API 36 for target and
  compile.
- CI has a Linux quality/Android/web lane with Deno checks and a separate
  macOS unsigned iOS profile-build lane.
- Physical iPhone and Android device matrices, signing, store accounts, legal
  hosting, production Auth/email, Edge Function deployment, accessibility, and
  store declarations remain launch gates.

## 2026-07-26 - Launch Evidence Must Be Environment-Safe And Honest

Decision:

Treat the comprehensive audit branch as a strong closed-beta candidate only
after its backend/Auth gates close. Do not call the app bug-free or publicly
launch-ready from source-only evidence. Keep destructive, multi-account,
booking-abuse, deletion, and load tests on disposable local/staging systems;
do not point them at production.

Reasoning:

The final local candidate passes 244 Flutter tests, 19 Deno tests, reviewed
goldens, an iOS simulator smoke, and every supported unsigned/source build.
Those results materially improve confidence, but they cannot prove a clean
database replay, tenant isolation under real Auth, deployed booking conversion,
destructive deletion, production email recovery, sustained load, store
signatures, or physical accessibility behaviour.

Consequences:

- Production received no migration, Function, destructive, or load mutation
  during the audit.
- Candidate database and booking-request changes must pass a clean replay and
  isolated staging before promotion.
- The 50,000-account profile remains a deterministic local representation, not
  a seeded-user or concurrency claim.
- Android and iOS store artifacts must fail closed while production signing
  credentials are absent.
- [`docs/testing/TEST_RESULTS.md`](testing/TEST_RESULTS.md) is the evidence
  ledger; [`docs/testing/KNOWN_GAPS.md`](testing/KNOWN_GAPS.md) is the release
  risk register. A missing environment or unexecuted suite remains a blocker,
  not a pass.

## 2026-07-26 - Shell Geometry And Typography Are One Product System

Decision:

Use one shared, iconless root-page header across Clients, Bookings, Money,
Tasks, Notes, and More. Place it at the platform safe area plus a 20-point top
inset, follow it with a 24-point content gap, and reserve one canonical
bottom-navigation clearance. Bundle Instrument Sans under the OFL and cap
interface weights at semibold.

Reasoning:

Mixing absolute and safe-area positioning made Clients sit visibly higher than
Bookings. Separate header constructions, decorative feature icons, inconsistent
content gaps, and 800-900 typography weights made connected modules feel like
different products. A quieter typeface and one measured shell grid improve
clarity without adding visual furniture.

Consequences:

- Home keeps a personalised greeting but consumes the same semantic display and
  supporting-text styles.
- Feature-local create actions use the same 48-point neon `+` treatment.
- Money's single create action discloses income and expense choices in a sheet.
- More gives Money, Tasks, and Notes primary workspace hierarchy while Profile
  and Settings remain secondary controls.
- Geometry, responsive, interaction, and safe-area-aware golden tests protect
  the system across iOS and Android.

## 2026-07-28 - Workflow Failures Preserve Context And Recovery

Decision:

Keep failure, saving, and retry state inside the workflow or section that owns
it. Do not dismiss an editor after a failed write, replace an entire screen
when one independent provider fails, or make users reconstruct valid input.
Creation and import paths that can write multiple related records must continue
through the existing validated, idempotent workflow boundary.

Reasoning:

Solo operators often use Workloop while interrupted or between jobs. Losing a
booking draft, hiding valid Money information because one source failed, or
offering only a transient snackbar creates uncertainty and duplicate work.
Local, specific recovery protects both user context and data trust without
adding another module or redesigning the product.

Consequences:

- Booking-request conversion stays open on validation or network failure and
  identifies conflicts, outside-hours decisions, and the next recovery action.
- Public booking requests use persistent labels and inline validation/error
  feedback in addition to any transient confirmation.
- Money, notifications, tasks, feed, onboarding, deletion, and import failures
  retry only their owning operation.
- Calendar import uses the same atomic booking workflow and stable idempotency
  contract as direct booking creation.
- Loading, success, and error semantics remain part of the shared interaction
  system and are covered at small-phone and large-text sizes.

## 2026-07-28 - Workloop Ships With One Dark Appearance

Decision:

Ship Workloop with one fixed, slightly lifted graphite Dark appearance. Remove
the System/Light/Dark preference and its Settings destination. Keep the exact
`#C1FF72` brand neon and use `#151A16` as the native and Flutter page canvas.

Reasoning:

One intentional appearance reduces preference and rendering state, prevents
platform-theme drift, and lets launch QA concentrate on the experience users
will actually receive. The previous OLED-black palette felt heavier than the
calm premium direction, so the graphite layers are lighter while retaining
contrast and restrained neon hierarchy.

Consequences:

- `MaterialApp`, semantic tokens, compatibility aliases, iOS launch
  storyboard, and Android launch theme resolve to the same dark system.
- Existing stored appearance values are ignored safely; no data contract or
  migration is required.
- Settings no longer exposes an obsolete appearance choice.
- Light/System entries earlier in this log remain historical and are
  superseded by this decision.
- Accessibility, responsive, golden, simulator, and physical-device checks
  target the shipped appearance; manual VoiceOver and TalkBack remain required.

## 2026-07-28 - Navigation Shortcuts Preserve Context

Decision:

Provide one app-level top-edge scroll shortcut and preserve platform-native
back navigation. Retained shell destinations own independent primary scroll
controllers. Clean pushed routes use native platform gestures; a protected iOS
route receives a thresholded edge-swipe fallback that invokes, rather than
bypasses, its existing pop guard.

Reasoning:

Solo operators move repeatedly between long client, booking, and money lists.
Returning to the beginning should be immediate, but it must target the visible
workspace rather than disturb an offstage tab. Back swipes reduce reach and
friction, but allowing an interactive pop to skip unsaved-draft confirmation
would weaken trust.

Consequences:

- A native iOS status-bar tap or short app top-edge tap animates the visible
  vertical scroll position to its minimum extent and respects reduced-motion
  preferences.
- Home, Clients, Bookings, Money, Tasks, Notes, and More retain independent
  scroll targets inside the shell.
- Existing explicit Clients, Money, and business-settings controllers register
  with the same shared assist system.
- Ordinary iOS and Android routes retain Flutter's native gesture behaviour.
- Protected editors keep their Save/Discard/Keep editing contract when reached
  by a left-edge swipe.

## 2026-07-29 - Navigation Shortcuts Follow the Real Visible Screen

Decision:

Replace per-screen scroll assumptions with app-level discovery of every
vertical scroll controller. Keep Flutter's native Cupertino back gesture, then
apply one route-aware left-edge fallback only when the native gesture has not
completed. Preserve reminder navigation history by pushing destinations rather
than replacing the active route.

Reasoning:

Physical-device use showed that the earlier contract tests were too narrow:
screens with implicit or nested controllers were not guaranteed to return to
the beginning, and ordinary routes had no fallback when the expected native
gesture did not complete. Navigation shortcuts must follow the actual visible
scrollable and the screen's existing back decision, not a shortlist of
screens.

Consequences:

- `ListView`, `SingleChildScrollView`, `CustomScrollView`, nested routes, and
  retained tabs participate without feature-specific wiring.
- Every visible vertical scroll layer returns to its beginning together;
  offstage routes and retained tabs remain untouched.
- Native iOS back navigation gets first refusal, preventing a double pop.
- Clean routes, direct routed headers, and protected editors share a forgiving
  edge-start zone and thresholded fallback recognized during the drag. A
  pointer cancellation after that deliberate threshold no longer loses the
  user's back action.
- Existing back callbacks and `PopScope` guards remain authoritative.
- Retained subordinate shell workspaces can register their own return target;
  Money, Tasks, and Notes return to the workspace that launched them.
- Clients no longer applies a hidden horizontal filter gesture across its full
  list because it competed with the top shortcut. Its visible filter rail is
  the canonical filter control, and top-zone client-row taps return to the
  header when the list is scrolled.

## 2026-07-30 - Hierarchy Follows the User's Next Decision

Decision:

Use three deliberate attention levels across Workloop: one labelled primary
screen action, one contextual focus area where the workflow has a meaningful
next decision, and quieter navigation/filter/content layers. Home's contextual
focus is the booking happening now, the next booking today, or the clear-day
path into Bookings.

Reasoning:

The shared component system had made the app consistent but too visually flat.
An unlabeled create icon, selected filters, record rows, and operational
attention frequently carried similar weight. Solo operators need to recognise
what is happening and what to do next before reading the rest of the screen.

Consequences:

- Create-capable root screens use a labelled neon action; secondary selected
  filters use raised graphite and accent text.
- Standard section headings use sentence-case title hierarchy; quiet variants
  remain available for dense date/count groups.
- Home uses a single daily-focus surface and keeps in-progress bookings visible
  until their end time.
- Existing provider/repository data sources, routes, four-tab navigation, and
  data contracts remain unchanged; only attention ordering changes.
- Booking detail places its operational action near the booking context, and a
  public profile exposes its booking-request action near the business hero.
- Golden, responsive, accessibility, provider, and workflow tests remain the
  verification boundary for future hierarchy changes.

## 2026-07-30 - Back Navigation Must Follow the Finger

Decision:

Keep Flutter's native Cupertino transition authoritative for clean pushed
routes. Replace binary retained-workspace back callbacks with a progress-driven
shell transition, and reserve the route fallback for direct routes or
draft-protected screens after pointer-up. Scroll-to-top targets only scrollables
that are actually painted and hit-testable on the visible page.

Reasoning:

A callback fired after an arbitrary distance is navigation, but it is not an
interactive back gesture. It cannot reveal the previous page, cannot be
reversed naturally, and made a cancelled swipe navigate away. Likewise,
mounted hidden tabs are not the screen the user intends to reset by tapping the
status bar.

Consequences:

- Clean pushed pages reveal the real previous route and can cancel using
  Flutter's native iOS gesture.
- Money, Tasks, and Notes preserve their retained state and bottom navigation
  while the remembered workspace appears beneath a finger-tracked transition.
- Draft-protected editors keep their Save/Discard/Keep editing contract and act
  only after the user releases a deliberate edge swipe.
- Hidden `PageView` and `TabBarView` scroll positions remain untouched by a
  status-bar tap.
- Scroll-to-top duration scales with distance, capped at 600 milliseconds, and
  reduced-motion users still jump immediately.

## 2026-07-30 - Tools Stay Grouped And Account Access Lives On Home

Decision:

Keep four stable bottom-navigation destinations: Home, Clients, Bookings, and
Tools. Rename the generic More destination to Tools, keep Money, Tasks, and
Notes there as equal full-width workspace rows, and expose Profile and Settings
as compact direct controls in the Home header.

Reasoning:

Adding Money, Tasks, and Notes individually would create a six-item bottom bar,
reducing label clarity, recognition, and comfortable thumb targets. The
previous More layout also mixed a Money hero, two smaller tiles, Profile, and
Settings, making the page feel like an uneven overflow drawer. Tools gives the
destination a clearer promise, while the Home header is the familiar place for
owner and app controls without turning them into daily dashboard content.

Consequences:

- The shell remains four destinations and retains existing workspace state,
  routes, providers, and back-swipe behaviour.
- Money, Tasks, and Notes receive equal row treatment; their order still
  follows the core business loop.
- Profile and Settings remain pushed screens and do not become dashboard
  sections that compete with Today.
- The old `MoreScreen` implementation name can be migrated separately; no
  architecture or data contract depends on that private presentation name.

## 2026-07-31 - Appearance Choice Returns With A Low-Glare Light Mode

Status: Supersedes the 2026-07-28 dark-only launch decision.

Decision:

Support persisted System, Light, and Dark appearances through a dedicated App
appearance destination in Settings. Keep the current lifted graphite Dark
palette and introduce a low-glare green-grey Light palette rather than a bright
white inversion.

Reasoning:

Appearance is a familiar device-level preference and users may need a lighter
canvas in bright environments. The choice should not weaken Workloop's calm
identity or create per-screen exceptions. A semantic theme plus an adaptive
compatibility bridge lets current screens move together while older static
colour call sites are migrated gradually.

Consequences:

- System follows platform brightness; Light and Dark override it and persist
  locally without changing workspace schema or account data.
- The exact `#C1FF72` brand neon remains the primary fill in both appearances.
  Light uses deep `#3F6711` accent ink for small foregrounds and focus states.
- Primary, secondary, tertiary, disabled, accent, status, module-icon, button,
  navigation, and field-focus pairs are contrast-tested in both appearances.
- iOS no longer forces `UIUserInterfaceStyle=Dark`; Android uses matching base
  and night startup resources before Flutter draws.
- Theme changes are applied atomically with no animation so semantic tokens and
  compatibility colours do not display different appearances between frames.

## 2026-07-31 - Tools Is A Launchpad, Not A Sparse Directory

Decision:

Keep Money, Tasks, and Notes grouped behind the stable Tools tab, but add direct
Record money, New task, and New note actions above their equal workspace rows.
Add one quiet live orientation line to each workspace rather than adding more
modules or moving secondary tools into the bottom navigation.

Reasoning:

The grouped navigation remains clearer than a six-item bottom bar, but a page
that only repeats three destinations wastes space and adds a navigation step to
frequent capture. Direct capture turns Tools into a useful operating surface
while preserving the existing information architecture.

Consequences:

- Quick actions invoke the existing Money choice sheet, Task editor, and Note
  editor; no parallel creation flow or business logic is introduced.
- Money shows the amount to collect, Tasks shows open work, and Notes shows the
  saved count when data is available. Load failures point users into the owning
  workspace rather than presenting false zeroes.
- The four-tab shell, retained workspace state, back-swipe behaviour, routes,
  providers, repositories, and Supabase contracts remain unchanged.

## 2026-08-03 - Navigation Motion Is One Shared System

Decision:

Give all programmatic shell destination changes one shared 240ms fade-through
with a small directional offset. Keep pushed routes theme-driven: restrained
fade and horizontal movement on Android, and native Cupertino movement on iOS
so the previous page continues to track an interactive back swipe.

Reasoning:

Pushed screens already inherited a common theme transition, but Home, Clients,
Bookings, Tools, Money, Tasks, and Notes changed in place without forward
motion. Fixing the retained shell primitive closes that inconsistency without
adding animation code to individual features or changing the route model.

Consequences:

- Root tabs and retained workspaces now enter through the same motion contract.
- The outgoing destination remains mounted during the transition, preserving
  providers, form state, scroll positions, and bottom navigation ownership.
- Existing iOS finger-tracked back gestures and Save/Discard/Keep editing
  guards remain authoritative.
- Reduced-motion settings bypass programmatic destination animation entirely.
- Feature screens must continue relying on shared navigation primitives rather
  than defining local full-screen transitions.

## 2026-08-03 - Retained Screens Must Never Be Reparented During Motion

Decision:

Keep every shell destination in one stable keyed layer for its entire lifetime.
Animation may change offset, scale, opacity, semantics, hit testing, and paint
order, but it must not move a feature screen between different wrapper trees.
Treat Tools create requests as one-shot intents and clear their widget input
after delivery.

Reasoning:

Physical-device recording showed the Add to Money sheet repeatedly appearing
over Tasks and Tools. The first navigation-motion implementation rebuilt its
outer stack structure between resting and animated phases. Flutter therefore
remounted retained Money, saw the previous non-zero create request in
`initState`, and replayed the sheet.

Consequences:

- Money, Tasks, Notes, and root destinations retain their State objects across
  forward transitions, tab changes, settled states, and interactive back.
- Dismissed creation sheets cannot reopen merely because another destination
  animates.
- A regression test holds a non-zero create request while switching repeatedly
  and proves it is delivered only once.
- Native iOS back-swipe, reduced motion, scroll retention, and draft guards are
  unchanged.

## 2026-08-03 - Light Mode Uses Stronger Layer Separation And Accent Edges

Decision:

Increase the tonal distance between the Light canvas, white content surfaces,
raised controls, and dividers. Give every neon-filled interactive primitive a
one-pixel semantic deep-green border rather than allowing the lime fill to
bleed into pale neighbouring surfaces.

Reasoning:

Physical review showed that the first low-glare Light palette was readable but
too tonally compressed. The dashboard canvas, daily focus, navigation capsule,
icon controls, and accent actions appeared to merge, weakening hierarchy.

Consequences:

- Light uses `#E7ECE4` background, `#FAFCF8` surface, `#D4DED2` raised surface,
  and darker divider roles while remaining softer than pure white.
- `accentBorder` is a canonical semantic token (`#5A8126`) used by buttons,
  top actions, selected navigation, floating actions, and accent icon chips.
- Dark retains its existing graphite layers and quieter accent edges.
- Contrast and golden tests protect the revised layer separation and border
  treatment.

## 2026-08-03 - Light Mode Uses Warm Neutrals And Selective Accent Edges

Decision:

Supersede the green-grey Light palette with a warm neutral system. Use a stone
page canvas, ivory content and raised surfaces, neutral grey interaction layers,
and the exact brand lime only for actions, selection, and compact emphasis.
Restrict the semantic accent border to genuinely accent-filled or accent-tinted
controls; high-level cards use neutral edges.

Reasoning:

Visual review of the stronger-separation pass showed that green tint across the
canvas and cards made the whole interface feel muddy, while deep green borders
made too many elements compete for attention. Hierarchy should come from
typography, spacing, surface luminosity, and a small number of confident lime
actions.

Consequences:

- Light uses `#EEEDE8` background, `#FFFEFA` surface, `#F8F7F2` raised surface,
  and neutral grey divider and interaction roles.
- `accentBorder` becomes quiet sage `#91B560`: still visible at one pixel on
  lime controls without reading as a dark frame.
- The dashboard focus hero uses a neutral border; its action and compact icon
  retain the accent treatment.
- Dark colours, navigation behaviour, workflows, and data contracts remain
  unchanged.
- Theme contrast contracts and Light dashboard, Tools, and Settings goldens
  protect the new direction.

## 2026-08-04 - Card Collection Uses Stripe Connect Direct Charges

Decision:

Extend the existing booking-linked Money record with Stripe Connect direct
charges. The connected business is the merchant of record and fee payer.
Workloop's platform fee remains server-controlled, disabled, and zero by
default. Support Tap to Pay and hosted Checkout links through authenticated
Supabase functions and signed, idempotent webhooks.

Reasoning:

Payment collection belongs at the end of the existing Client to Booking to Work
to Payment loop. A separate wallet or ledger would duplicate income and increase
reconciliation risk. Direct charges preserve clear merchant responsibility,
while Stripe-hosted onboarding and card entry keep regulated payment data out of
Workloop.

Consequences:

- Provider transactions reconcile atomically into `invoices.amount_paid` and
  retain a distinct provider-collected amount for refunds and manual edits.
- Authenticated clients can read their workspace's provider state but cannot
  mutate Stripe accounts, transactions, refunds, or webhook state directly.
- Provider-backed Money entries cannot be deleted while their ledger exists.
- iOS minimum support moves to 15 and Android minimum support to API 26 for the
  first-party Stripe Terminal 5.x SDKs.
- Production Tap to Pay on iPhone remains gated by Apple's development and
  distribution proximity-reader entitlements and App Review.
- Live mode remains disabled until a separate explicit go-live approval.

## 2026-08-05 - Payment Retries Are Logical Operations, Not Button Taps

Decision:

Retain one idempotency key for each payment-link, Terminal-payment, or refund
operation across user retries. Permit a failed or abandoned webhook claim to be
reclaimed after a bounded lease, while keeping processed and ignored events
final. Private counters, workflow keys, and webhook state use RLS plus explicit
false client policies even though the schema and grants already exclude clients.

Reasoning:

A network retry is the same business operation. Generating a new provider key
for every tap can create duplicate Checkout Sessions or refunds, while a failed
webhook row that can never be reclaimed can permanently block reconciliation.
The private-ledger policies make a deliberate backend-only boundary visible to
reviewers and security tooling.

Consequences:

- The Flutter sheet owns operation keys; repository methods require them.
- Stripe calls and local transaction upserts use the same stable key and reject
  reuse with different invoice, amount, or collection parameters.
- Refund totals are recomputed from succeeded refund rows.
- Failed events can retry immediately; stale `processing` work can retry after
  five minutes; completed work stays deduplicated.
- Live mode, Apple entitlement work, and platform fees remain unchanged.

## 2026-08-05 - Editorial Utility Replaces Warm Card-Heavy Presentation

Decision:

Supersede the warm Light palette with crisp soft-white and neutral-grey roles,
and make the shared interface denser through smaller type, spacing, radii, and
visual control geometry. Keep accessible touch targets. Prefer divider-led lists
over repeated cards and allow restrained native graphics only when real data
improves orientation.

Reasoning:

The product was functionally clear but felt visually heavy: large typography,
generous containers, and warm layered surfaces made routine information appear
more complex than it was. Workloop should feel like a calm mobile operating
system, not a generic admin dashboard or analytics product.

Consequences:

- Light uses `#F7F7F4` background, pure-white surfaces, and neutral interaction
  and divider roles; the exact brand lime remains reserved for primary action
  and selected state.
- Dark retains its established graphite and lime colour personality while
  sharing the denser typography and geometry.
- Notifications use one chronological list; unread state is communicated by a
  small lime marker and text weight rather than a separate filter.
- Home's schedule path is drawn natively from the current time and real booking
  positions. No invented analytics or raster decoration is introduced.
- Navigation, workflows, state, repositories, schema, and data contracts remain
  unchanged.

## 2026-08-05 - Page Grid and Reduced Motion Are Product-Wide Contracts

Decision:

Lock user-facing page content to the canonical 18-point horizontal grid and
require every presentation animation to use `AppMotion.responsive` or an
explicit immediate stable-state path. Explain the Workloop operating loop once
in onboarding with a semantic Flutter-native visual; do not add decorative
analytics to routine workspaces.

Reasoning:

The shared palette and typography were already coherent, but secondary routes
still contained 20- and 24-point outer insets and several local animations did
not honour the platform's reduced-motion preference. These small exceptions
made the app feel assembled screen by screen and created avoidable
accessibility drift.

Consequences:

- Authentication-adjacent, onboarding, notification, calendar, client-detail,
  booking, settings, public-profile, and Money/task supporting surfaces align
  to the same page grid.
- Selection, progress, keyboard-inset, calendar, workspace, and
  expand/collapse motion becomes immediate when animations are disabled.
- Static UI contracts reject feature-local raw colour literals, interface
  weights above 600, and unguarded canonical animation durations.
- Compact large-text coverage now includes secondary routes as well as primary
  launch surfaces.
- Workflows, navigation, Riverpod/Supabase contracts, and durable data remain
  unchanged.

## 2026-08-05 - Graphite Frame And Lime Signal Define The New Interface

Decision:

Replace the visually incremental editorial pass with a recognisable app-wide
composition system: a graphite structural frame in both appearances, lime as
the active signal, a compact two-line operating-loop mark, editorial header
rules, squared action geometry, and bold real-data focus panels.

Reasoning:

The previous palette and density work improved correctness but retained the
same header, navigation, surface, and control compositions. On-device, the
result read as the previous interface with different spacing. Workloop needs a
distinctive identity that remains calm and useful rather than a decorative
reskin or data-heavy dashboard.

Consequences:

- Root and pushed headers, the floating four-destination dock, peer navigation,
  segmented controls, search, empty states, and section anchors share one
  central primitive system.
- Home, Money, Tools, Auth, onboarding, and the public profile receive one bold
  graphic or operational anchor based on real state or product orientation.
- Light moves to cool chalk and neutral layers while retaining the existing
  Dark graphite personality; both appearances now share graphite structural
  controls and the exact `#C1FF72` active signal.
- Routes, workflows, providers, repositories, Supabase contracts, draft
  protection, retained tab state, and native back behaviour are unchanged.
- No new package, analytics surface, invented business data, gradient, stock
  illustration, or schema change is introduced.

## 2026-08-06 - Soft Editorial Surfaces Supersede The Graphite Frame

Decision:

Retire the 2026-08-05 graphite-frame composition after visual review. Use open
typographic headers, soft neutral semantic layers, a white Light-mode focus
surface, quiet selection rails, and small lime markers. Keep Dark lifted and
graphite-based without repeating near-black panels inside every workspace.

Reasoning:

The graphite direction was technically consistent but visually overbearing.
Large dark panels, boxed marks, repeated lime bars, and heavily framed controls
made Workloop feel closer to a concept dashboard than the minimal, clean and
useful mobile product shown in the approved references.

Consequences:

- Light returns to `#F7F7F4`, white content surfaces, neutral raised layers,
  crisp ink typography, and restrained lime.
- Headers, route controls, section titles, segmented controls, floating
  navigation, empty states, and search use shared neutral treatments.
- Home's real schedule path and onboarding's operating-loop graphic remain;
  decorative background geometry and the boxed signal mark are removed.
- The four-destination shell, routes, drafts, state retention, providers,
  repositories, Supabase contracts, and working business flows are unchanged.

## 2026-08-06 - Loopline Replaces Mixed Pill And Rectangle Geometry

Decision:

Adopt one Loopline interface language across the whole application. Functional
controls use a restrained soft-square scale, icon-only utilities are circular,
true status markers alone may be capsules, and navigation uses stable text/icon
rows with a two-pixel lime position line. The main navigation is docked to the
bottom edge instead of floating as a rounded glass container.

Reasoning:

Repeated visual reviews showed that switching palettes and card treatments did
not solve the deeper inconsistency: floating pill navigation, rounded segmented
rails, rectangular buttons, circular utilities and local one-off controls all
competed on the same screen. The interface needed one clear geometry rule and
a visibly different composition, while the product's working operating loop
and architecture did not need rebuilding.

Consequences:

- Light moves to a mineral `#F4F5F2` canvas with white surfaces and ink primary
  actions. Dark preserves its graphite surfaces and lime primary actions.
- Root navigation is an opaque edge-to-edge system bar. Client, booking, Money,
  task, note and request navigation use the shared line system.
- Auth loses its framed brand card; Tools loses its nested focus card; Settings
  becomes list-led; public-profile content uses open sections and dividers.
- `AppRadius.pill`, `StadiumBorder`, and literal `999` control radii are removed.
  `AppRadius.capsule` is restricted to status and progress, with a source test
  preventing the retired system from returning.
- Home's real schedule path, Money progress and the onboarding operating-loop
  graphic remain because they explain real state. No decorative analytics,
  package, provider, repository, route, schema or workflow is introduced.

## 2026-08-06 - Workloop Studio Supersedes Loopline

Decision:

Replace the complete application presentation layer with Workloop Studio: a
porcelain/midnight adaptive palette, Manrope typography, indigo action system,
relationship teal, selective module colour, contained navigation rails, a
floating four-destination dock and purposeful native-drawn graphics.

Reasoning:

The Loopline reset standardised geometry but still felt visually incremental,
heavy and generic on the physical phone. Workloop needs a recognisable mobile
business-operating-system identity with calm hierarchy, meaningful graphic
moments and enough operational data to be useful without resembling an admin
dashboard.

Consequences:

- Home, Clients, Bookings, Money and Tools now use different compositions that
  match their jobs while sharing one theme, type, spacing, shape and motion
  system.
- Notifications stays as one chronological list. Auth, onboarding, Settings,
  forms, sheets, empty states and public surfaces inherit the same Studio
  primitives.
- The operating-loop mark, daily schedule path and Money target arc are native
  Flutter graphics tied to product meaning or real state. No decorative or
  invented analytics are allowed.
- The retired lime launch artwork is removed from native startup; the existing
  app icon remains a separate release asset until deliberately replaced.
- Existing routes, Riverpod state, repositories, Supabase contracts, retained
  workspaces, draft protection, native back behavior and business workflows
  are unchanged.

## 2026-08-08 - Calendar Becomes A Native-Feeling Month And Day Workspace

Decision:

Replace the boxed booking calendar and stacked next-booking/list composition
with one time-led calendar workspace. Use an open month grid, circular date
selection, restrained booking dots, swipe and explicit month navigation, and a
selected-day agenda built around a vertical time rail and compact event blocks.

Reasoning:

The prior Calendar mode repeated several unrelated layers before the selected
day: a section label, display control, next-booking row, boxed grid and generic
booking list. This made the calendar feel denser and less direct than the
familiar mobile-calendar behaviour users already understand. The useful
principle from Apple Calendar is spatial orientation around month, date and
time—not its exact visual styling.

Consequences:

- The month and selected date become the primary hierarchy in Calendar mode.
- Month changes work through 44-point previous/next controls or horizontal
  swipes, while Today remains an explicit shortcut.
- Up to three dots communicate booking density without turning every date into
  a filled tile.
- The selected-day agenda sorts bookings chronologically and shows start/end
  time, client, service, location, price and non-scheduled status in context.
- Add booking still passes the selected date into the existing form; booking
  detail, List mode, Requests, providers, routes and data contracts are
  unchanged.
- Deterministic Light and Dark calendar goldens and interaction tests protect
  the new hierarchy.

## 2026-08-08 - Recurring Series Stay Outside V1 Creation

Decision:

Remove the recurring-series selector from New booking while preserving the
existing recurrence columns, repository payload support, validation utilities
and read-only recurrence labels for historic records.

Reasoning:

The exposed creation control could create a fixed batch, but Workloop did not
provide an honest series-edit scope, per-occurrence exceptions or complete
series-level conflict recovery. Completing those semantics safely would expand
the final V1 sweep into a calendar-series engine. A single-booking V1 is clearer
and safer than a partially supported recurring promise.

Consequences:

- New booking always creates one atomic, idempotent booking.
- Existing recurring records continue to render their repeat state and remain
  data-compatible; no migration or destructive rewrite is introduced.
- Recurrence can return only with explicit edit-scope, exception, conflict,
  retry and end-to-end coverage.

## 2026-08-08 - Write-Capable E2E Uses Disposable Staging Only

Decision:

Authenticated workflow, two-account isolation and public booking conversion
tests must require an explicit write opt-in, disposable credentials and a
non-production Supabase URL. The shared runner must reject the production
project reference before Flutter starts.

Reasoning:

These tests deliberately create, update and delete business records. Running
them against the live project would turn release verification into a data and
security risk. A compiled harness is useful implementation evidence, but only a
passing isolated run can close the corresponding launch blockers.

Consequences:

- `scripts/qa_staging_e2e.sh` is the canonical entry point for the three
  staging journeys.
- Missing configuration causes a safe skip in ordinary simulator QA; explicit
  staging execution fails early when required values are absent.
- Production data is never used to prove deletion or cross-tenant denial.
- The quoted branch cost and creation require explicit founder approval.

## 2026-08-08 - Money Context Supports Home But Does Not Enter Today

Decision:

Keep the purple Today panel focused on the owner's immediate day. Add a compact
monthly-target dial to Money inside Home's At a glance group, using real
paid-this-month and configured-target values.

Reasoning:

Revenue progress is useful command-centre context, but placing it inside Today
would mix a monthly business-health signal with the daily next-action hierarchy.
The supporting group makes the metric discoverable without crowding the panel
the owner must understand first.

Consequences:

- The dial is not decorative and does not invent a forecast.
- A missing target falls back to ordinary Money navigation rather than an empty
  progress claim.
- Business feed is promoted above Coming up, while Today remains the strongest
  visual and action hierarchy on Home.
- Future metrics must earn a place in At a glance and must not turn Home into a
  generic analytics dashboard.

## 2026-08-10 - Dark Mode Is Graphite With Controlled Periwinkle

Decision:

Use neutral graphite and slate for Dark-mode canvas, surfaces, dividers and
backdrop fields. Keep periwinkle for interaction and selection. Render Home's
Dark hero as a deep desaturated indigo field rather than the bright interactive
accent, and let the selected schedule node move with the browsed booking.

Reasoning:

The previous midnight palette repeated violet through the background, cards,
hero and navigation, reducing depth and making the app feel uniformly purple.
The schedule path also displayed every booking as an equal small dot, so it did
not reinforce which booking the carousel was showing.

Consequences:

- Dark surfaces are differentiated by neutral luminance and dividers rather
  than violet hue.
- White hero copy meets contrast across both hero gradient endpoints.
- The current-time tick stays subordinate; the active booking uses a larger
  ring and halo.
- Browsing jobs animates the active node for 280 ms with a single settling
  bounce and haptic tap. Reduced Motion skips the travel and bounce.
- Light mode keeps its saturated Home hero and existing canvas palette.

## 2026-08-10 - Booking Records Use One Visual Language

Decision:

Render Schedule and Calendar bookings through one shared flat booking-record
row. Preserve Calendar's selected-date header and continuous time rail, and
preserve Schedule's Today/Upcoming/Past filters and date grouping.

Reasoning:

The two views answer different navigation questions, but each row represents
the same booking and opens the same detail flow. Separate dot-and-line and
time-rail row designs made the module feel inconsistent and forced owners to
relearn the same record. A common start/end time, status marker, typography,
price position and divider rhythm improves recognition without erasing useful
calendar context.

Consequences:

- Both views show start and end times and the same booking information order.
- Calendar alone draws the continuous rail because it is a selected-day agenda.
- Schedule alone owns time filters and multi-day grouping.
- Booking data, providers, repositories, routes and tap behaviour are unchanged.

## 2026-08-10 - Bookings Prioritises Work Over View Controls

Status: Superseded in part by `Booking Requests Move To A Counted Inbox` below.

Decision:

Keep Schedule/Requests as the only full-width workspace decision. On standard
phones, place Today/Upcoming/Past and List/Calendar in one compact toolbar.
Stack them on narrow or accessibility-text layouts. Present the real seven-day
booking load as an inline divider-led strip and tighten Calendar spacing without
reducing the 44-point date targets.

Reasoning:

The previous hierarchy made users pass four control layers and a large chart
card before reaching the work they needed to run. The controls were individually
clear but collectively behaved like a settings panel. Workloop is a business
operating system: the daily schedule must arrive sooner, while Calendar must
retain enough month context for planning.

Consequences:

- The first populated Schedule row appears materially earlier on a standard
  phone.
- The weekly graphic remains real operational data but no longer reads as a
  dashboard card.
- Calendar keeps full month navigation, booking-density dots, selected-date
  handoff and its time rail.
- Large text expands the weekly strip and stacks the toolbar rather than
  clipping labels.
- Providers, repositories, routes, Requests and booking mutations are unchanged.

## 2026-08-10 - Booking Requests Move To A Counted Inbox

Decision:

Make the main Bookings workspace schedule-first. Remove the seven-day workload
graphic and the full-width Schedule/Requests switch. Keep requests visibly
owned by Bookings through a compact inbox action beside New booking, show the
active count when non-zero, and open the existing dedicated Active/New/Closed
request workspace.

Reasoning:

List and Calendar both serve the owner's daily scheduling workflow, while
requests are an exception inbox that must be triaged into accepted work. Giving
both equal full-width navigation weight delayed the schedule and duplicated a
less capable requests list. The seven-day count summarised data already visible
in List and Calendar but did not enable a distinct action. The new hierarchy
keeps incoming demand discoverable without making it a prerequisite decision
for every visit to Bookings.

Consequences:

- Bookings opens immediately into Today, Upcoming or Past schedule content.
- The active request count remains visible in the header and requests remain
  one tap away, including when the count is zero.
- Request triage has one canonical UI with Active, New and Closed views.
- List/Calendar, selected-date handoff, repositories, providers, mutations,
  routes and booking-request conversion behaviour remain unchanged.
- A request-provider failure no longer blocks the main booking schedule.

## 2026-08-10 - Feature Creation Uses A Compact Plus

Decision:

Render the feature-header create action for Clients, Bookings, Money, Tasks and
Notes as one circular `+` control. Preserve the specific action name as its
semantic label. In Bookings, replace the separate time-filter and List/Calendar
controls with one Today/Upcoming/Past/Calendar navigation rail.

Reasoning:

The labelled create capsules competed with page titles and request utilities,
especially on smaller phones. In a clearly named feature workspace, `+` is a
conventional and unambiguous creation affordance. Bookings also duplicated the
same choice across two adjacent segmented controls: Today, Upcoming and Past
already implied list presentation, so a separate List label added width without
adding meaning.

Consequences:

- Root feature headers gain more breathing room and use one shared 46-point
  create target.
- VoiceOver continues to announce New client, New booking, Add money, New task
  or New note rather than a generic plus.
- Form save, confirmation, conversion and destructive actions remain visibly
  labelled.
- Calendar remains explicit and one tap away; selecting Today, Upcoming or Past
  returns to the corresponding schedule list.
- Booking requests retain their counted inbox and dedicated triage workspace.
- Providers, repositories, routes, retained state and creation flows are
  unchanged.

## 2026-08-10 - Tools Owns Business Setup And The Booking Page Is A Workflow

Decision:

Remove Profile and Settings from the Home command panel. Put Booking page,
Business profile, and Settings in Tools, while Home retains Notifications as
its one utility. Split the owner-facing Booking page workflow from the business
identity screen. Publish customer pages at `/:handle` through the existing
Workloop website and secured public Edge Functions.

Reasoning:

Home should answer what is happening and what to do next; account and business
configuration are tools, not daily status. The previous Profile mixed owner
identity, public publishing controls, requests, preview and settings links, so
the feature lacked a clear job. A dedicated Booking page hub gives the owner a
single place to understand whether requests are open, complete setup, preview,
copy/share the link and open the canonical request inbox.

Consequences:

- Tools owns all secondary operating and setup destinations without adding a
  fifth bottom tab.
- Business profile contains only business details, services and working hours.
- Booking page shows a computed readiness state and reuses the existing editor,
  preview, request provider and request inbox rather than duplicating logic.
- The public website renders real profile data and proxies request submission
  to the existing bounded Edge Function; database writes remain server-owned.
- Public copy consistently states that a request is not confirmed work.
- `workloop.app` remains the canonical share origin; launch remains blocked
  until its DNS validation and SSL status are active.

## 2026-08-10 - Navigation Follows The Operating Loop, Not A Tools Drawer

Decision:

Replace the four-destination Home / Clients / Bookings / Tools shell with five
explicit operating destinations: Today, Clients, Work, Money, and Business.
Group Schedule, Tasks, and Notes as peer views inside Work. Make the customer-
facing Booking page the lead feature in Business, followed by Services,
Working hours, and Business profile. Keep Settings as a compact secondary
header action and remove Quick capture from the primary information
architecture.

Reasoning:

Tools mixed daily modules, capture shortcuts, customer acquisition, business
setup, and account administration at one level. That made valuable features
feel like overflow and added a navigation step to Money, Tasks, and Notes.
Solo service owners think in a smaller operating loop: understand today,
manage customers, deliver work, collect money, and shape how the business is
presented. The new shell makes that mental model visible without adding new
business logic or duplicating data.

Consequences:

- Money becomes one tap away from every primary screen.
- Schedule, Tasks, and Notes retain their existing providers, editors, drafts,
  routes, scroll state, and repository contracts while sharing one Work
  selector.
- Business exposes booking-page readiness, active request count, services,
  hours, and identity before account settings.
- Booking requests remain available from both the Schedule inbox and the
  Booking page workflow; they are not promoted to a permanent bottom tab.
- Existing deep links and internal destination indices remain compatible.
- No Supabase schema, RLS, repository, or persisted-data change is introduced.

## 2026-08-11 - Work Is A Retained Command Surface

Decision:

Keep the Work title, purpose, booking-request inbox and create action mounted
while Schedule, Tasks and Notes change inside a retained content region. Use one
line-led selection language for root navigation and peer navigation, and one
semantic indigo accent for operational modules.

Reasoning:

Rebuilding the whole screen on every Work selection made a local context change
feel like navigation and visually reset the user's orientation. Filled purple
selection blocks and unrelated module colours also competed with the content.
The retained shell clarifies that Schedule, Tasks and Notes are three views of
one workday, while neutral surfaces and a small active line preserve hierarchy.

Consequences:

- Existing Schedule, Tasks and Notes providers, repositories, editors and routes
  remain intact inside retained child surfaces.
- Each child keeps its own scroll and filter state when another child is shown.
- Feature creation remains local and uses the same circular 46-point control.
- Money and Business setup use semantic tokens rather than feature-specific
  decorative palettes.
- No Supabase schema, RLS, repository or persisted-data contract changes.

## 2026-08-11 - Stripe Live Cutover Is An Explicit Operational Boundary

Decision:

Keep the current app and Edge Functions in Stripe test mode until the Stripe
platform is fully verified, Apple grants Tap to Pay, distribution signing is
healthy, and the complete test-mode payment matrix passes. Do not silently turn
the existing test workspace into a live workspace or reuse test account IDs.

Reasoning:

The schema intentionally gives each workspace one connected Stripe account and
the server rejects a connected account whose mode differs from its secret key.
This prevents accidental test/live mixing, but it also means replacing secrets
alone is not a valid production migration. Payment and refund reliability is
more important than a fast flag flip.

Consequences:

- Live money remains disabled by both test secrets and the server kill switch.
- A dedicated staging environment is preferred. Any production cutover needs a
  reviewed cleanup/migration plan for test-only payment state.
- Apple entitlement approval and Stripe account verification remain separate
  external gates from TestFlight build readiness.
- The app may ship to internal beta with payment links in test mode, but no
  public launch claim may imply that live collection is ready.

## 2026-08-11 - V1 Authentication Uses Email, Apple, Google and Optional TOTP

Decision:

Ship V1 account access with confirmed email/password, native Sign in with Apple,
Google OAuth and optional TOTP authenticator security. Do not add phone/SMS,
Facebook, Microsoft or passwordless experiments to the beta surface.

Reasoning:

These three sign-in paths cover the credible iOS beta needs without multiplying
identity-provider configuration, recovery cases or privacy surface. TOTP provides
standards-based second-factor protection without depending on SMS delivery or
phone-number collection. Requiring AAL2 only after a user enrolls prevents a
security rollout from locking out existing accounts.

Consequences:

- Passwords use a 12-character, four-character-class baseline and Supabase's
  leaked-password check.
- Apple is native-only for V1, so there is no Apple web OAuth secret to rotate
  every six months.
- Google remains disabled until its production OAuth client is created and
  tested; the UI implementation alone is not treated as provider readiness.
- Verified MFA users are denied authenticated Data API access from AAL1 sessions.
- Recovery codes, passkeys and a native CAPTCHA flow remain future security work,
  not implied beta capabilities.

## 2026-08-11 - Workloop.uk Is The Canonical Owned Domain

Decision:

Use `workloop.uk` for the public website, booking links, legal URLs, Auth email
and support identity. Retire the planned `workloop.app` origin because it is
registered to an unrelated third party.

Reasoning:

Store submission, OAuth trust, email authentication and customer booking links
must use a domain controlled by Workloop. The exact `.uk` name is short,
credible for the initial UK market and avoids adding a qualifier to the product
name.

Consequences:

- App constants, public booking defaults, legal pages, tests and local Auth
  redirect configuration use `workloop.uk`.
- Resend and Supabase Auth send from the owned domain with DKIM, SPF and an
  enforced DMARC rejection policy.
- The public Sites deployment owns both the apex and `www` hostnames.
- Historic records that described the unowned `.app` plan remain as history;
  this decision supersedes them for current and future work.

## 2026-08-12 - Privileged Workflows Share One Opt-In MFA Boundary

Decision:

Every authenticated workflow that can bypass table RLS must evaluate the same
opt-in MFA policy before using security-definer or service-role access. A user
without a verified factor may continue at AAL1; a user with a verified factor
must hold an AAL2 session. Authenticated clients cannot call private workflow
implementations directly.

Reasoning:

An app-only challenge and restrictive table policies do not protect privileged
RPC or Edge Function paths. One bounded server-side policy prevents an AAL1
token from bypassing the protection the user enabled while preserving Workloop's
optional-MFA product decision.

Consequences:

- Onboarding, task creation, booking creation/completion, Stripe actions and
  account-deletion requests use the same policy.
- New privileged workflows must enter through the guarded public/Edge boundary.
- The forward migration and Edge sources require clean replay and disposable
  staging evidence before production promotion.

## 2026-08-12 - Payment Deletion Fails Closed And Provider Payloads Expire

Decision:

Close a Workloop-created Stripe Accounts v2 merchant account before deleting
its local workspace. If Stripe cannot confirm closure, release the deletion
claim and keep local data intact for retry/review. Retain full known-account
webhook payloads for no longer than 30 days; scrub unknown-account payloads
immediately and workspace payloads during deletion.

Reasoning:

Deleting Workloop rows while leaving a connected provider account or indefinite
provider payloads would make the user-facing deletion promise incomplete.
Failing closed preserves recoverability and bounded retention reduces privacy
risk without discarding the short retry/support window.

Consequences:

- Deletion depends on Stripe availability when a connected account exists.
- Offboarding is idempotent and rejects test/live key mismatches.
- Payment exports include account, transaction and refund records.
- Stripe test-mode offboarding/deletion E2E and legal review remain mandatory
  before the source is promoted.

## 2026-08-13 - Freeze Beta 4 With Payment Collection Off

Decision:

Keep `v1.0.0-beta.4` immutable on app-source commit
`81673f6e5f67b11a5c4f2697e51477d95811ab4f`. Preserve its exact App Store IPA
and provenance, keep both client and candidate server payment gates false, and
record later verification in a documentation-only commit rather than moving
the tag.

Reasoning:

The source, clean database replay and signed iOS artifact are reproducible, but
hosted staging, external Auth, exact-build manual accessibility and production
promotion are not complete. Moving the tag or enabling payments would blur the
artifact boundary and overstate the tested beta scope.

Consequences:

- Beta 4 may continue as an internal developer/founder candidate, but is not
  authorised for upload or tester distribution under the strict release brief.
- A disposable Supabase preview branch requires explicit cost approval before
  the hosted journeys can run.
- Production migration/Edge promotion, Apple upload and live-money activity
  remain separate approval boundaries.
- Any app-source change requires a new monotonically increasing build and tag;
  documentation-only evidence must identify the immutable binary SHA.

## 2026-08-13 - Booking Confirmation Uses A Durable Email Outbox

Decision:

Require email on new public booking requests and send a transactional
confirmation only after the owner converts the request. Commit one private
email intent in the same transaction as booking creation, then deliver it
through a separately leased and bounded Resend worker. Keep the originally
captured request address authoritative during conversion.

Reasoning:

Sending directly after the database commit can lose confirmation when an Edge
process or provider fails, while sending before commit can email a booking that
does not exist. A private outbox preserves the business workflow, supports safe
retry and prevents a client from redirecting the recipient.

Consequences:

- New intake requires a valid normalized email; legacy blank rows still work.
- Booking success is independent from provider availability and the owner sees
  sent, queued, failed or no-email truth.
- Resend secrets remain Edge-only and a token-authenticated worker must run
  every minute; delivery stops after eight attempts or 24 hours.
- Build 4 stays immutable. This source change requires Build 5, a new tag,
  controlled-inbox staging evidence and new signed artifacts.

## 2026-08-15 - Auth Email Pack And Verified-Account Welcome

Decision:

Use Supabase's managed Auth templates for every security-sensitive Auth email,
with one version-controlled Workloop visual and copy system. Send a separate
welcome message only after the user's email is confirmed, using a private
transactional outbox drained by the existing scheduled Resend worker.

Reasoning:

Verification and recovery links must stay inside the provider's secure Auth
flow. A post-verification message has a different job: confirm readiness and
help the owner take three useful first steps. Separating them keeps each email
short, accurate and recoverable without turning essential mail into marketing.

Consequences:

- Confirmation, invitation, magic-link, email-change, recovery,
  reauthentication and seven security notifications share Workloop styling.
- New email-verified and already-confirmed provider signups receive one welcome
  email. Existing users are not backfilled.
- Delivery is fixed-sender, idempotent, leased, retried and capped at eight
  attempts or 24 hours. Recipient and body data are never logged.
- Email opportunities remain purposeful: account security, onboarding,
  requested booking confirmation and explicit launch-list consent. Workloop
  does not send speculative lifecycle mail merely because it can.

## 2026-08-15 - Confirm Both Account Deletion Boundaries By Email

Decision:

Send one transactional email when an account deletion request is recorded and
a different email when deletion reaches the authoritative `completed` state.
Queue both through a private database outbox and the existing scheduled Resend
worker.

Reasoning:

The request receipt must not imply that data has already been removed, while a
completion message must never be sent before workspace and Auth deletion.
Database transitions provide the only reliable boundary for both claims and
remain durable if an Edge process or email provider is temporarily unavailable.

Consequences:

- The request email says clearly that deletion is not complete and gives an
  urgent support route for an unrecognised request.
- The completion email confirms sign-in removal and describes limited legal,
  security and financial retention without making an absolute deletion claim.
- Each event is unique per request, fixed-recipient, leased, idempotent and
  capped at eight attempts or 24 hours.

## 2026-08-15 - Automate Account Lifecycle And Business Attention

Decision:

Use the existing protected minute worker as one bounded automation runner.
Make account deletion its first and independently isolated job, keep customer
attention in the existing notifications model, and keep operational failures
in a private service-only alert ledger.

Reasoning:

Deletion is a security boundary and must not depend on the app remaining open
or an email provider being healthy. Booking, payment and daily-brief prompts
belong in Workloop's existing attention workflow rather than a parallel task
system. Operational incidents contain infrastructure detail and must never be
readable through the mobile Data API.

Consequences:

- Pending deletion blocks onboarding and workspace access at both Flutter and
  database boundaries; requesting deletion bans the identity and revokes its
  refresh sessions immediately.
- Scheduled completion tolerates an Auth user that was manually removed only
  when no workspace membership remains, preserving recovery without guessing
  ownership.
- Waiting requests, overdue payments and the daily brief respect notification
  preferences and stable deduplication keys. Appointment reminders continue
  to use the existing device scheduler.
- Health alerts and retention are service-only and scheduled. Backup health is
  verified by an opt-in read-only CI job, not inferred from configuration.
- Promotion requires ordered migration/function deployment and disposable
  destructive-path evidence; source and local tests alone do not make it live.

## 2026-08-31 - Use Aggregate-Only Founder Reporting

Decision:

Use a private reporting schema and a single owner-only Data Studio report for
product, website, email and Apple beta health. Import external provider data
through scheduled server-side collectors and store only aggregate metrics.

Reasoning:

The founder needs one operational view without giving a third-party dashboard
direct access to Workloop users, Auth records or business data. Provider keys
must remain server-side, and TestFlight tester identity is unnecessary for the
decisions the dashboard supports.

Consequences:

- Data Studio reads only three aggregate views through a constrained PostgreSQL
  login; it cannot query Auth or application schemas.
- App Store Connect has separate permanent Sales and Reports and Developer keys
  rather than an Admin key. The private key material lives only in Supabase Edge
  Function secrets.
- Apple collection is protected by a Vault-generated request token, runs daily,
  stores no tester names or email addresses and reports provider health alongside
  Supabase and Resend.
- TestFlight installs, sessions, crashes and feedback are live now. Public App
  Store downloads will be activated only when a public store release exists.

## 2026-08-31 - Deliver Business Attention Through A Durable Push Outbox

Decision:

Use Firebase Cloud Messaging as the cross-platform transport, with APNs for
iOS, while keeping `notifications` as Workloop's user-visible source of truth.
Fan each eligible notification into a private per-device delivery outbox and
drain it through the existing protected minute worker. Keep appointment and
task reminders scheduled locally on the device.

Reasoning:

Sending directly from a business workflow would couple core writes to a
third-party provider and lose alerts during timeouts. A durable outbox gives
Workloop retry, idempotency, token invalidation and operational evidence
without creating a second attention model. FCM avoids an iOS-only server
design while APNs remains the actual Apple delivery path.

Consequences:

- Device tokens are membership-checked, unique across accounts and removable
  during sign-out; clients cannot write or reassign token rows directly.
- Delivery respects stored preferences and local quiet hours. Lock-screen copy
  deliberately omits client names, phone numbers and payment amounts.
- Taps can open only known authenticated Workloop routes. Foreground events
  refresh the existing centre rather than showing duplicate banners.
- Provider credentials remain outside the app and repository. Build 6 is not
  releasable until Firebase/APNs configuration, backend promotion, physical
  iPhone delivery and production-signed TestFlight evidence all pass.

Amendment after provider configuration:

The Firebase iOS SDK remains responsible for permission, APNs registration and
message lifecycle, but the server sends iOS alerts directly to APNs. Google
Cloud's secure-by-default policy blocks downloadable service-account keys, and
that policy remains enabled. Direct APNs delivery uses the existing team-scoped
Apple key, removes a second long-lived server credential and is sufficient for
the iOS-only Build 6 beta. Android delivery remains out of scope until its own
provider path is deliberately enabled.

## 2026-09-01 - Make Beta Attention And Scheduling Exact But Forgiving

Decision:

Refresh recoverable Auth sessions before signing out, reveal the dashboard only
after one coherent user-scoped snapshot, and route notification taps to a
strictly allow-listed entity. Let owners deliberately accept schedule exceptions
after a warning, while preserving conflict rejection as the server default.
Store public booking-request time as an exact instant plus workspace timezone.

Reasoning:

An expired access token is a recoverable transport condition, not evidence that
the user intends to sign out. Brief cross-user or placeholder dashboard frames
damage trust. A notification that opens a generic list creates more work than it
saves. Overlaps and outside-hours work are valid owner decisions, but silently
allowing them would hide mistakes. Free-text requested times cannot reliably
survive timezone and daylight-saving boundaries.

Consequences:

- Session validation retries after refresh and clears local state only for
  explicit terminal session or user conditions.
- Booking, booking-request, payment, task and note notifications carry exact
  UUID routes; malformed, external or unauthenticated routes fall back safely.
- `allow_overlap` is explicit, defaults false and is accepted only by the
  authenticated workflow after the UI has shown a schedule warning.
- New public requests require a selected date/time, persist `timestamptz` plus
  the matching IANA workspace timezone and reject nonexistent DST wall times.
- The booking Edge Function keeps its legacy overload during the Build 6 to
  Build 8 transition so backend promotion cannot strand older beta clients.
- Build 7 predates this change set. The next distributable artifact is Build 8
  and still requires ordered backend promotion and physical-device evidence.

## 2026-09-01 - Fail Public Workspaces Closed And Keep Availability Honest

Decision:

Require at least one current workspace member at both public Edge boundaries
and at booking-request insert time. Present published working hours as guidance
for the selected service duration without exposing existing bookings or
claiming that a requested time is reserved.

Reasoning:

Service-role Edge Functions bypass RLS, so an orphaned workspace must not keep
publishing or collecting customer data. Workloop's public flow is a request,
not automatic scheduling: showing private calendar occupancy would leak
business information, while presenting every displayed time as available would
mislead customers and conflict with the owner's deliberate exception controls.

Consequences:

- Orphaned public handles return the same not-found response as an unknown
  profile, and future booking-request inserts fail at the database boundary.
- Customers see whether their preferred time fits the published day and
  service duration, but can still ask for another time and are reminded that
  the owner must confirm it.
- The member guard, exact-time migration and notification-route migration must
  pass isolated hosted replay/pgTAP and be promoted with their compatible Edge
  Functions before Build 8 is distributed.

## 2026-09-01 - Offer Suggested Times And Parent-Scoped Extras

Decision:

Show a bounded set of privacy-safe suggested request times after the customer
chooses a service. Model optional extras beneath one parent service, while
keeping packages and bundles as ordinary services with their own total name,
duration and price. Snapshot the selected composition at request and confirmed
booking time.

Reasoning:

Customers need useful guidance without being shown a private diary or being
promised an unheld slot. A generic product-composition engine would add owner
setup work and cognitive load; one service plus a few clear extras solves the
real workflow. Immutable snapshots protect historical names, durations and
prices when the owner later edits the catalogue.

Consequences:

- Suggested times respect the workspace timezone, split working hours, notice,
  booking window, buffer and the trusted aggregate duration of selected items.
- A customer can still request another time, and every request remains subject
  to owner confirmation.
- Public clients send at most eight unique IDs and never submit trusted price,
  duration or snapshot text.
- Older clients keep their existing RPC route; an insert-boundary trigger gives
  those requests the same trusted base snapshot before later confirmation.
- Availability and add-on migrations must be promoted in chronological order,
  followed by the three compatible public Edge Functions.

## 2026-09-02 - Authorize Private Booking RPCs By Database Role

Decision:

Protect the public-intake and availability RPCs with explicit Postgres EXECUTE
ACLs for `service_role` only. Do not duplicate that boundary inside the
functions by reading the optional `request.jwt.claim.role` transport setting.

Reasoning:

Supabase service clients can authenticate as `service_role` without populating
that legacy per-request GUC. Postgres evaluates function EXECUTE permission
before entering a SECURITY DEFINER body, so the ACL is the reliable database
boundary; the GUC check rejected legitimate Edge requests without adding a
separate security guarantee.

Consequences:

- `public`, `anon` and `authenticated` remain unable to execute the protected
  RPCs; only `service_role` is granted EXECUTE.
- Hosted tests deliberately leave the JWT role GUC blank while invoking as the
  database `service_role` role.
- Edge Functions remain responsible for public request validation, rate limits
  and safe response shaping before calling the private database capability.

## 2026-09-02 - Quarantine Invalid Service Durations

Decision:

Bound every base service to 5 minutes through 24 hours in Postgres and Flutter.
Normalize any legacy outlier to the existing 60-minute fallback while making
that service inactive and private until its owner reviews it.

Reasoning:

Service duration controls availability, request snapshots and booking end
times. Guessing that a corrupt public value is correct is unsafe, while leaving
it visible misleads customers. A quarantined fallback preserves the owner row,
allows correction in Settings and lets the database constraint be fully
validated immediately.

Consequences:

- Direct, legacy and future clients cannot create or update a base service
  outside 5-1,440 minutes.
- Public profile responses independently exclude invalid durations as defence
  in depth.
- Add-on duration rules remain unchanged: zero additional minutes is valid for
  a price-only add-on.

## 2026-09-02 - Keep One Persistent Application Canvas

Decision:

Render the Workloop textured background once above the Navigator and make route
scaffolds transparent. Seed route-level authentication gates from the current
session so a route for the same user reuses prepared workspace state.

Reasoning:

Repainting a decorative canvas and invalidating account-scoped providers on
every screen transition makes navigation feel like a reload. One stable canvas
preserves visual continuity, while session-aware gates retain the existing
security boundary without repeating startup work.

Consequences:

- Screens may keep `WorkloopTexturedBackdrop` for isolated widget tests, but it
  becomes transparent when rendered beneath `WorkloopAppCanvas`.
- Root and pushed-route scaffolds must use transparent backgrounds; cards,
  sheets and controls continue to use semantic surface tokens.
- A genuine account change still resets and prepares workspace-scoped state.
- Module colour stays restrained to navigation and hierarchy accents rather
  than becoming a second screen background.

## 2026-09-04 — Quiet + Warm brand rollout

Owner approved the Quiet retro + Warm desktop visual reference and requested the entire app, website, email and brand kit match it. Shared components and feature compositions were extended without replacing repositories, providers, navigation or payment/auth behaviour. Native vectors keep illustration assets sharp; icon/splash generation is reproducible. The editable Canva brand kit and complete local exports are recorded in `assets/brand/quiet-warm/README.md`.

Verification before mobile packaging: Flutter analysis clean; 485 tests passed, 4 skipped, including reviewed/regenerated visual baselines and compact/enlarged-text responsive checks. Website19 and email18 tests passed. All13 production Auth template contents were read back exactly after patching; unrelated Auth configuration stayed unchanged. Signed-device and TestFlight evidence is tracked separately in the release report.

## 2026-09-05 — Preserve the retro identity; simplify and trust the live workspace

The owner reported screen bleed-through, slow transitions, stale summaries,
fragile card corners and unfinished bottom dividers. Restore independent opaque
page surfaces and instant retained peer navigation; preserve native route/back
interactions. Consolidate linked records around canonical providers and refresh
once on app resume/push. A temporary verification failure blocks interaction
while preserving a verified user's draft; confirmed invalid identity still
removes protected content.

Remove visible Business Feed and duplicate Coming up from Today. The hero now
shows the next future booking when none remain today. Retain notifications for
incoming updates and remove noisy self-notifications after manual money/status
actions. Add independent opt-in local weather with reduced-precision coordinates,
authenticated caching proxy, manual UK-area fallback and honest unavailable
states. No database migration. TestFlight remains explicitly on hold.

### 2026-09-05 — Owner refinement: compact divided bottom navigation

Restore vertical tab dividers and lower the icons by reducing the standard
navigation row from 76 to 64 points. Draw dividers through the entire safe-area
background so they reach the screen bottom, while retaining enlarged-text
height, accessible touch targets and the selected blue marker. This supersedes
the intermediate divider removal; opaque pages and single-frame segmented
controls remain. Eight focused geometry/raster/accessibility tests and the
full 550-test suite pass.


### 5 September 2026 — first-use guidance and customer texts

Use a short, skippable and resumable guide over real workflows after successful
new-user setup, with replay in Settings. Do not populate fake work or interrupt
existing accounts on upgrade. Keep the wordmark on Today and minimise repeated
working-screen chrome.

Treat booking texts as a separate, provider-gated channel with explicit
permission for the exact customer number and business-level 24-hour/1-hour
choices. Existing email preferences and recorded mobile numbers do not opt
customers into SMS. Ambiguous dispatch outcomes must not be retried blindly.
A private pseudonymous 25-hour usage ledger preserves caps when bookings are
deleted; retention runs independently of sending. Phone-first account access
requires a verified email before business setup, in both app and backend.

### 2026-09-05 — Pause SMS on cost; review WhatsApp without activation

Decision: the owner has chosen to leave SMS inactive because of its recurring
cost. Retain the existing disabled implementation, but do not create/fund a
Twilio account, rent a sender, activate SMS phone authentication, enable business
text reminders or enroll customers. Email reminders continue independently.
The earlier SMS technical design remains a record of prepared groundwork, not
authorization to launch it or a promise of future availability.

Assess WhatsApp reminders only for cost, operational requirements and suitability
for Workloop. No implementation, provider activation, customer enrollment,
sending or spending is authorized until the owner makes a separate decision.
### 2026-09-05 — Manual WhatsApp booking reminders authorized

Following the SMS cost review, the owner chose a booking-level **Send WhatsApp
reminder** action. It prepares the message and opens a recipient-specific
WhatsApp link. The owner checks the message and sending account, then taps
Send in WhatsApp. There is no scheduled WhatsApp worker, paid API connection,
delivery assertion or automatic customer messaging in this scope.

Use the existing booking/client/business workflow and URL launcher. Recheck
the saved booking and recipient before handoff; explain missing details and
unavailable bookings. Keep automated email reminders and replace dormant SMS
settings/permission entry points with manual WhatsApp guidance. SMS backend
configuration remains off, and phone-number authentication stays disabled.
Full WhatsApp Business Platform automation remains outside this decision.

### 2026-09-05 — Separate settings by recipient; preserve independent reminders

Decision: keep three explicit communication destinations: **Your notifications**
for the owner, **Customer reminders** for client booking communication, and
**Emails from Workloop** for account guidance/tips. Each email screen reads only
its own settings. Privacy opens export/deletion directly; account/security and
ordinary device preferences stay separate.

Business-update preferences govern incoming business activity and related push
alerts, not personal task/booking reminders or email subscriptions. Quiet
Sundays applies to the morning overview only. Hide controls without an active
producer rather than imply that a stored boolean creates a working feature.
Show phone permission and device-token registration honestly without claiming
that provider delivery has been proven.

Retain the existing repositories, local preference stores and notification
services. Make saves retryable and guarded, keep large-text controls reachable,
and describe account deletion by its real consequences. Device sign-out uses
the existing expected-user local-session guard. Recheck current notification
preferences and active Auth-session bindings at server enqueue/claim; preserve
historical inbox records. Both server migrations are separately reviewed and
verified. No new SMS/automated WhatsApp activation or mobile-store upload is
part of this decision. See [the settings audit](releases/2026-09-05-settings-and-notifications.md).

### 2026-09-05 — Keep Money's overview independent of history length

Decision: received totals, cash movement, weekly/monthly targets and payment
collection setup precede the transaction list. Made and Spent show five recent
entries with a clearly labelled View all control above the rows. Reuse the same
filtered collection, order and record actions; do not introduce a second history
route or duplicate provider. Keep the disclosure in the same screen position
when it expands or collapses, and reset it when the selected period changes.

Spending category totals precede recent expenses. Owed remains a complete
overdue-first queue because every outstanding payment may still need action.
Payment setup is independent of the weekly/monthly target and remains reachable
for Custom dates. Keep flat transaction rows and the existing single-frame
overview components; add no nested content cards.

All totals and charts continue to use the entire matching collection, not just
the five displayed rows. This is presentation-level disclosure, not database
pagination: expanding a very large history still renders the matching records
from the existing provider. Forty focused tests and two visually reviewed Money
goldens pass; final integrated suite/build evidence is still pending the last
notification change. No payment-provider activation or store upload is implied.

### 2026-09-06 — Meaningful dashboard illustrations and exact attention targets

Decision: remove decorative calendar imagery from Today. A clock beside an
actual booking represents that booking's displayed start time, with a
minute-adjusted hour hand; it changes with the selected booking. Keep the
existing digital label and local-time display contract.

Every Needs attention row must identify and open its exact record. Replace
request counts with named active-request entries, refresh the relevant canonical
collection before opening, and use the existing review/detail actions. Do not
guess a destination from a malformed source or quietly substitute a generic
list when the record is missing. Exact-client lookup belongs behind the same
authenticated, workspace-scoped boundary as the other entity routes.

Keep the dashboard preview at four entries, with one from each available
attention category before filling by normal priority/oldest-first order. This
preserves visibility of overdue tasks/payments during a large request backlog.
Do not create new attention producers for undated notes or routine bookings;
their existing workflows and deliberate module shortcuts remain available.
Backend historical notification repair must be based on deterministic stored
identifiers and must not replay sends. Final source/build/provider/device
evidence remains separate from this product decision. See
[the dashboard report](releases/2026-09-06-dashboard-direct-actions.md).

### 2026-09-06 — One monthly target across Today and Money

The owner's target is a calendar-month receipt goal. History filters do not
convert it into a weekly estimate or hide it. Both visible indicators share
absolute completion thresholds: red below 50%, amber from 50% to below 100%,
green at/above 100%; these colours do not claim whether the business is on pace
for the date. Preserve numeric/spoken progress and compare currency at penny
precision. Target entry is monthly-only and continues to use the existing
`revenue_target` setting. See [implementation and evidence](releases/2026-09-06-monthly-targets.md).

### 2026-09-06 — Settings explains who receives a message before its channel

Use separate **For you** and **For your customers** groups. Your alerts governs
owner inbox/push/local reminders; Emails to you governs Workloop account email
preferences; Customer messages governs customer booking emails and explains
manual WhatsApp. Retain the existing coupled business inbox/push preference,
with independent phone permission, local reminders and email choices. Quiet
hours must explicitly say **Business push only**.

Use one shared paper frame per related group and flat controls inside it.
Interactive panel bodies need a transparent Material beneath native list tiles
and switches so ink feedback stays visible. Save failures must appear without
requiring a scroll to the bottom of the page.

Do not interpret an active limited welcome series as an ongoing account-tips
subscription. Show its actual scope and retain both a visible unsubscribe path
and an explicit ongoing-tips opt-in through the existing preference API. No
schema, saved defaults, notification production rules or provider policy change
is needed for this UI clarification. The existing Android remote-push hold and
store-upload hold remain in effect. See
[verification and limitations](releases/2026-09-06-notification-settings-clarity.md).

## 2026-09-06 — Net profit and one searchable Payments timeline

The owner asked for Cash movement to become income after expenses and for
income and expenses to share one searchable history. Rename the first Money
destination Overview, retain Spent for category analysis and Owed for collection,
and label the chart Net profit with an explicit Income minus expenses caption.
The monthly target remains an income target, independent of the history filter.

Compute the chart and timeline from existing records: received amounts including
part-payments and negative adjustments, less recorded expenses, using their
actual received/expense dates. Do not count unpaid balances as received income
or imply the aggregate payment model provides separate instalment events.
Unknown expenses must not appear as zero in profit calculations.

Search the complete selected period before applying progressive disclosure.
Show five recent transactions normally and up to 25 search matches immediately,
with an explicit control for all results. Keep the useful overview above history
and use one flat list with explicit income/expense/refund labels and signed
amounts. See [scope and verification](releases/2026-09-06-money-profit-and-timeline.md).

## 2026-09-06 — Standard crash diagnostics with a narrow data boundary

Use the existing Firebase project's Crashlytics SDK for technical crash/error
diagnosis. Do not create a custom telemetry backend, add Analytics/activity
breadcrumbs, attach customer or account identifiers, or forward arbitrary
exception descriptions. Preserve code locations through an allowlist and keep
native SDK privacy disclosures distinct from Dart sanitization. Reporting failure
must not block the product or hide the original app error. Release configuration
must record the reporting choice; a diagnostic test must remain outside the
normal app entry point. Source verification, native symbols and a real provider
receipt are separate completion gates. See
[the implementation report](releases/2026-09-06-crash-reporting.md).

## 2026-09-06 — Separate Workloop brand from company operator

At the owner's request, use Haani Enterprise Limited (15758586, England and
Wales) as the legal operator, while preserving Workloop as the product, trading
name, brand, domains and application identifiers. Keep tenant service businesses
as providers/controllers for their own customer workflows. Publish the current
registered office until a change has actually been filed; operational contact
addresses are distinct. Provider organisation verification, domain records,
store membership and legal/IP transfers must be evidenced individually.

Use shared operator constants/footer helpers to keep rendered disclosures
consistent. Deploy only isolated email/footer changes from reviewed live
bundles while unrelated local launch work remains unshipped. No new TestFlight
upload is part of this company-identity change.

## 2026-09-08 — Connect business documents, repeat work and tax preparation

The owner approved quotes/invoices, recurring bookings, receipt/mileage records
and a UK sole-trader tax estimate in four phases. Extend existing Money, booking
and expense workflows. Keep quotes and drafts separate from collectible invoice
rows so existing app versions do not count them as debt. Issue once into the
existing payment system, freeze the commercial snapshot, and retain dated cash
movements for partial payments and refunds.

Use bounded real booking occurrences in the saved business timezone, with
explicit occurrence-only edits. Keep mileage separate from cash expenses.
Retain private receipt originals through the account export/deletion lifecycle.
Compute tax from reviewed annual inputs with a versioned jurisdiction/year rule
set and explicit eligibility; do not represent it as an HMRC filing or convert
ordinary Money profit into taxable profit automatically.

See [implementation, boundaries and verification](releases/2026-09-08-business-tools.md).

## 2026-09-08 — Integrate commercial workflows into Money

Invoices and quotes are a primary Money destination, alongside Overview, Spent
and Owed. Mileage belongs with expenses; tax planning belongs before overview
history. Client and booking entry points open the same documents/payment rows.
The owner explicitly excluded profit per job.

Use current workspace settings for new document defaults, with one reviewed
Invoice setup screen. Reuse existing business address and customer contacts;
do not infer a legal name or tax residence from private account details. Keep
signup short and extend the existing Getting started guide. Issued documents
retain immutable commercial snapshots.

Deposit requests are part of the invoice balance, never income by themselves.
Only actual receipts affect collected money. Reused service/booking prices are
agreed gross prices by default; VAT is separated within them. Cash receipts and
manual refunds carry reviewed business dates and stable retry identities.

The Tomorrow dashboard row follows adjacent module typography and spacing.
Native photo capture is explicit and optional; receipt files remain private.
See [review findings and verification](releases/2026-09-08-business-workflow-review.md).

## 2026-09-08 — View documents and review locally extracted receipt details

Use one account/workspace-scoped document viewer for invoices, quotes, saved
receipt files and tax reports. Viewing is the primary action; sharing remains
available from the same loaded copy. Keep private document bytes in memory.

Read receipt images and PDFs locally using the platform's native recognition.
Present suggestions for review, preserve existing values by default, and retain
manual entry for uncertain or unsupported receipts. Supplier/reference details
reuse expense notes; no new database fields are justified for this workflow.

Money prioritizes actual unpaid balances, current cash figures and activity,
followed by planning and setup. This supersedes the previous placement of tax
before activity. Shared field labels sit above their input outline and wrap at
large text sizes.

Account deletion disconnects independently owned Standard Stripe accounts from
Workloop when Stripe rejects platform closure with its specific loss-liability
error. Record verified revocation in the existing server-only audit before local
deletion. Keep all unverified outcomes fail-closed; no schema or RLS changes.
The owner explicitly approved the production repair.

See [build 18 scope and evidence](releases/2026-09-08-build18-refinement.md).

## 2026-09-09 — Give account access a clear vertical hierarchy

Use an open brand row and shared page gutters for account access. Normal phone
heights distribute spare space above the form and before the legal footer;
short windows and keyboards use compact, scrollable content. Keep account
creation alongside the primary sign-in action, before alternate providers.
Retain existing authentication handlers, accessible touch targets and legal
navigation. Light and dark screenshot checks now include the iOS Apple button.

These are local tweaks for the owner's next combined release. No new TestFlight
upload or tester distribution is part of this refinement.

## 2026-09-09 — Replace the welcome diagram with an illustrated organiser

The owner found the welcome process graphic unconvincing. Replace the four
connected nodes and repeated benefits with one paper panel introducing the day,
client context and money. Reuse existing native illustrations and flat rows so
the welcome screen shares the operating app's visual language. The heading is
"Your business, in good order"; the single action still starts business setup.

This is presentation only: onboarding steps, draft restoration, providers and
data collection are unchanged. Hold this together with the account-access
refinement for the owner's next combined release; no TestFlight upload now.

## 2026-09-09 — Preserve service descriptions from onboarding

Use the existing optional, public-facing service description in the onboarding
editor, saved draft, RPC payload and transactional service insert. Trim outer
whitespace, preserve internal line breaks and normalize blank descriptions to
null. Do not add a parallel field or new schema column. Keep the verified-email,
MFA, account-deletion and workspace security boundaries unchanged.

The service editor owns its text controllers until its closing route is removed;
disposing them when the modal result first resolves can race the exit transition.
Use the shared persistent field labels for this editor. The app and migration
remain local for the owner's combined release.

## 2026-09-09 — Show the complete onboarding week together

The owner should be able to review and edit all seven working days without
scrolling at standard phone text sizes. Use a single compact weekly table with
day toggles and two time controls per row, instead of tall per-day sections.
Keep Continue fixed below the table and retain the shared time picker, existing
defaults and saved-hours format. Use the current theme's colours directly.

Accessibility text retains its requested size, full time values and 44-point
targets. When those controls need more space, scroll only the weekly body and
keep Continue available. This remains a local refinement for the combined
release; no upload or installation is included.

## 2026-09-09 — Replace the mutable palette bridge

An actual mounted Services card remained dark after switching to Light. Its
constant adaptive Color changed internally, so Flutter considered the new
decoration equal to the previous decoration and reused a cached dark Paint.
Synchronising the global palette earlier could not invalidate that cache.

Replace the bridge with immutable light/dark compatibility palettes selected
through `Theme.of(context)`. Preserve all 47 existing colour pairs and migrate
presentation call sites to their local context; no palette redesign is included.
Keep the standard appearance provider and MaterialApp System/Light/Dark handling.
Remove the shared surface's brightness key, retain its children, and apply
appearance changes without animating from an outgoing background. Resolve open
sheet/dialog colours locally and remove four forced-dark date-picker wrappers.

This remains local for the owner's combined release. No backend, schema,
installation or TestFlight action is part of the change.

## 2026-09-09 — Refine Dark independently of Light

The owner likes Light and requested a better Dark colour scheme. Keep the
existing composition and Light values; replace the brown/ochre Dark layers,
taupe ink and bright beige frames with charcoal, soft ivory and restrained
blue-grey framing. Use slightly brighter powder-blue actions and muted status
containers so the dark experience retains Workloop's identity and hierarchy.

This is a shared-palette change with matching native dark launch backgrounds.
No feature-local colour overrides, new layout, data changes or theme-state
changes are needed. Preserve every Light screenshot and accept Dark baselines
only after reviewing real screen renders and contrast. Hold for the combined
release; no upload or installation now.

## 2026-09-12 — Share private record attachments and preserve workflow context

Use one attachment model, repository, picker and viewer across bookings, notes
and clients. Keep immutable metadata and bytes tied to a workspace and exact
record; validate content and verify hashes when retrying a possibly completed
upload. Save a new note with a stable UUID before attaching, then keep editing
that same note. Delete bytes before metadata so a failure retains the cleanup
pointer. Include files in privacy export and account deletion.

Use narrowly scoped private trigger functions for native Storage completion,
whose database role lacks business-table access. Preserve the member/MFA checks
for authenticated callers and revoke direct trigger execution. Repair the same
reproduced privilege defect in receipt storage without broader table grants.

Record links preserve their caller, with canonical list fallbacks for direct
entry. Refresh current provider records on return and withhold stale actions
during scope changes or payment failures. Put the next document action before
supporting detail. New quote conversions bound deposit dates to the new invoice
period; recorded quotes and prior conversion retries remain stable. PDFs
distinguish non-VAT businesses from registered businesses charging zero VAT.

These changes are deployed and installed as described in the
[connected app polish report](releases/2026-09-12-connected-app-polish.md).
Customer acceptance portals, formal credit notes and mixed-rate VAT are separate
workflow additions; native sharing and owner-recorded decisions remain explicit.

## 2026-09-12 — Name customer settings for their actual booking workflow

Use **Booking reminders**, not Customer messages, for customer email timing and
manual WhatsApp reminder settings. A chat-bubble icon and generic messages label
imply an inbox that Workloop does not provide. Use the shared calendar/clock icon,
state the automatic-email/manual-WhatsApp distinction and explain where replies go.

Offer a bulk off action through the existing reminder-time preference. Re-enabling
requires choosing a time; do not silently restore defaults or alter customer
unsubscribe choices. Show saved selection rather than implying confirmed delivery.
Keep booking-update emails and business contact details separate from timing.
See the [implementation receipt](releases/2026-09-12-booking-reminder-settings.md).

### 2026-09-12 — Keep Money's overview short

Show the current cash result and unpaid-money action before supporting detail.
Use one cash panel with received/spent shortcuts; disclose the signed trend and
full payment history on demand. Keep the shared monthly target as an editable
row and payment setup as a compact footer action. Expense categories expand
above the expense list. Preserve normal text scaling and all record workflows;
return to the top when switching Money sections. This supersedes the earlier
always-expanded chart/history and separate Plan ahead section. See the
[implementation receipt](releases/2026-09-12-compact-money.md).


### 2026-09-12 — Make essential form information explicit

Use the shared Required/Optional field labels across booking, client, Money,
account, onboarding, business and supporting forms. The existing save rules
determine the label; the label does not introduce new validation or requirements.
A new client needs a name, while phone/email/address can remain blank. Combined
and conditional requirements are explained at the point of entry. Invoice draft
forms distinguish saving from the later requirements for issuing.

Persistent labels and text-based emphasis make requirements discoverable before
submission, including with enlarged text and assistive technology. See the
[change and verification receipt](releases/2026-09-12-form-requirements.md).


## 12 September 2026 — Native Apple introductory trial

Owner approved a one-month Apple free introductory offer followed by £14.99/month automatic renewal, with transparent pricing/cancellation and seven/three-day service reminders. New customers authorise with Apple before business setup; no new separate no-card trial is started. Preserve existing lifetime beta and started legacy access; retain historical annual receipts but offer monthly only. Sandbox access, purchase lifecycle tests and billing activation remain separate release gates. Public release is paused.
