# Local weather

Implemented for the September 2026 improvement pass. The Today greeting uses a
real current-hour local forecast, independently of business data. A permission
prompt is only shown after the owner chooses **Use my location**. Weather starts
off and a neutral location marker replaces the previous decorative sun.

## Data and presentation

- `WorkloopWeatherGreeting` supplies the greeting, matching native illustrations,
  temperature and a compact condition/area label. Tapping it opens weather
  settings with the forecast update time, source and licence link.
- Foreground approximate device location is requested with a bounded timeout.
  Coordinates are rounded to two decimal places before they leave the device.
  GPS coordinates are held only in memory. No background location subscription.
- If permission is denied or location is unavailable, owners can choose a UK
  address/postcode using Workloop's existing authenticated Places search.
  Manual coordinates are rounded, stored only on the device per owner and expire
  before 30 days; the label is the owner's own typed query.
- Missing, stale, invalid, offline or failed responses never imply sunshine or
  zero degrees. They leave the rest of Today usable and offer another area/retry.
- A forecast is a model estimate for the present hour, not a claim to have a
  weather station at the owner's exact position. Forecast issue time remains
  visible in settings.

## Backend

Deploy `supabase/functions/local-weather` with normal JWT verification enabled.
It additionally validates the signed-in user with `auth.getUser`, rejects
anonymous identities, validates and rounds coordinates, and returns only a
small current reading. No service-role key or database schema change is needed.
There are no location fields in Workloop's business database.

The function proxies MET Norway Locationforecast requests so the provider sees
Workloop's server connection rather than the owner's device IP. It identifies
Workloop with its domain/support address, honours `Expires` and `Last-Modified`,
coalesces duplicate in-flight requests and backs off on provider throttling.
The mobile cache is bounded to eight areas; the warm-instance proxy cache is
bounded to 100 areas. Owner request limits are also bounded per warm instance.

The provider expressly allows commercial use with attribution. No paid plan or
secret API key was added. Manual area lookup uses the existing Places project
and its existing quota/billing settings.

Before a large rollout, review aggregate weather traffic: MET Norway requires
prior agreement above 20 requests/second for the application as a whole. The
current warm-instance cache and limiter are not a distributed global quota or
SLA. A shared caching gateway is the next step if observed volume requires it.

## Verification and release

- Ten Flutter regressions cover weather mapping, privacy rounding, caching,
  stale/invalid data, no startup permission prompt, denied-location manual
  fallback, owner isolation, stale-request cancellation, coordinate expiry,
  large text and the neutral UI.
- Four TypeScript regressions cover parsing, expiry/conditional caching,
  request coalescing and throttling.
- A real provider request for public Central London coordinates returned a
  valid current-hour forecast on 5 September 2026.
- Source verification does not prove deployed-function authentication, physical
  iPhone permission handling, Android permission handling or final installed
  UI. Record these separately before release. TestFlight remains on hold.
- Native privacy and terms now explain optional foreground weather, the proxy,
  reduced-precision coordinates, manual Google Places area selection, temporary
  caching, turning weather off and MET Norway's privacy/licence links.
- Store disclosures are recorded in `docs/StoreSubmission.md`. Apple treats the
  transmitted two-decimal weather coordinates as coarse. Google Play uses a
  different area-size definition, so a precise OS fix rounded to two decimals
  can still require **Precise location** on Play. Do not equate approximate
  permission support with a guarantee of Play's Approximate Location category.
  Stripe's existing location handling needs its own final build/provider audit.
- The website privacy/terms copy must receive the same disclosure before this
  feature's release; source and live policy publication are separate checks.

## Sources checked

- [MET Norway usage terms](https://api.met.no/doc/TermsOfService)
- [MET Norway commercial availability](https://api.met.no/)
- [MET Norway licensing](https://api.met.no/doc/License)
- [Locationforecast integration](https://api.met.no/doc/locationforecast/HowTO)
- [Geolocator platform configuration](https://pub.dev/packages/geolocator)
- [Google Places policies](https://developers.google.com/maps/documentation/places/web-service/policies)

`geolocator` is pinned to 14.0.2. Version 14.0.3 brings a Linux dependency that
requires a different `package_info_plus` major; the existing version-reporting
dependency was preserved. iOS location wording now includes weather, and the
plugin's Always Location permission path is disabled. Android retains the
existing precise permission used by payments and adds approximate permission.

### Integration evidence — 5 September 2026

The production function is ACTIVE at version 1 with platform JWT verification.
Both missing authorization and the public anonymous project key are rejected
with 401; the latter returns the handler's `sign_in_required` response, proving
the deployed bundle starts and enforces its additional signed-in-user check.
All four proxy regressions also passed in the root verification run.
Website privacy/terms version 33 is public; the actual workloop.uk privacy URL
was fetched and verified for weather, MET Norway and retention wording.
Authenticated device-to-function results are recorded separately in the app
improvement report; no isolated QA login was available for a scripted probe.

### Physical iPhone evidence — 5 September 2026

The installed profile build successfully displayed `16° · Partly cloudy · Near
you` with the matching illustration after optional location setup. Approximate
location was selected in the system prompt. This confirms the authenticated
device-to-function forecast path; it supersedes the earlier lack of a scripted
QA login as the end-to-end evidence limit. Android physical permission/location
testing remains outstanding. TestFlight remains on hold.
