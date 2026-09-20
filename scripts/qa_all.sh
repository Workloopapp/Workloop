#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# shellcheck source=scripts/dev_env.sh
source scripts/dev_env.sh

python3 -m unittest discover -s scripts/tests -p 'test_release_tools.py'

ci_supabase_url="https://example.supabase.co"
ci_supabase_key="ci-public-anon-key"
dart_defines=(
  "--dart-define=SUPABASE_URL=$ci_supabase_url"
  "--dart-define=SUPABASE_ANON_KEY=$ci_supabase_key"
)

dart format --output=none --set-exit-if-changed \
  lib test integration_test tool
flutter analyze
flutter test --coverage "${dart_defines[@]}"

deno_bin="${DENO_BIN:-deno}"
if command -v "$deno_bin" >/dev/null 2>&1; then
  "$deno_bin" fmt --check supabase/functions quality/load
  "$deno_bin" lint supabase/functions
  "$deno_bin" check \
    --config supabase/functions/complete-account-deletion/deno.json \
    supabase/functions/complete-account-deletion/index.ts
  "$deno_bin" check \
    --config supabase/functions/create-booking-request/deno.json \
    supabase/functions/create-booking-request/index.ts
  "$deno_bin" check \
    --config supabase/functions/confirm-booking-request/deno.json \
    supabase/functions/confirm-booking-request/index.ts
  "$deno_bin" check \
    --config supabase/functions/drain-booking-confirmation-emails/deno.json \
    supabase/functions/drain-booking-confirmation-emails/index.ts
  "$deno_bin" check \
    --config supabase/functions/get-public-booking-availability/deno.json \
    supabase/functions/get-public-booking-availability/index.ts
  "$deno_bin" check \
    --config supabase/functions/get-public-profile/deno.json \
    supabase/functions/get-public-profile/index.ts
  "$deno_bin" check \
    --config supabase/functions/join-waitlist/deno.json \
    supabase/functions/join-waitlist/index.ts
  "$deno_bin" check \
    --config supabase/functions/places-address-search/deno.json \
    supabase/functions/places-address-search/index.ts
  "$deno_bin" check \
    --config supabase/functions/request-account-deletion/deno.json \
    supabase/functions/request-account-deletion/index.ts
  "$deno_bin" check \
    --config supabase/functions/stripe-payments/deno.json \
    supabase/functions/stripe-payments/index.ts
  "$deno_bin" check \
    --config supabase/functions/stripe-webhook/deno.json \
    supabase/functions/stripe-webhook/index.ts
  "$deno_bin" check \
    --config supabase/functions/resend-webhook/deno.json \
    supabase/functions/resend-webhook/index.ts
  "$deno_bin" check supabase/functions/collect-apple-reporting/index.ts
  "$deno_bin" check supabase/functions/workloop-ai-assistant/index.ts
  "$deno_bin" test --allow-env --allow-read=supabase/templates --ignore=supabase/functions/stripe-payments,supabase/functions/workloop-subscription supabase/functions
  "$deno_bin" test --allow-env --config supabase/functions/stripe-payments/deno.json supabase/functions/stripe-payments
  "$deno_bin" test --allow-env --config supabase/functions/workloop-subscription/deno.json supabase/functions/workloop-subscription
else
  echo "Deno is unavailable; Edge Function checks were not run." >&2
  exit 69
fi

for profile in small medium large scale-50000; do
  dart run tool/quality/generate_test_data.dart \
    "--profile=$profile" \
    --dry-run >/dev/null
done

if [[ "${RUN_LOCAL_SUPABASE:-false}" == "true" ]]; then
  scripts/qa_local_supabase.sh
fi

if [[ "${RUN_INTEGRATION:-false}" == "true" ]]; then
  scripts/qa_integration.sh
fi

if [[ "${RUN_BUILDS:-false}" == "true" ]]; then
  flutter build apk --debug "${dart_defines[@]}"
  flutter build apk --profile "${dart_defines[@]}"
  flutter build web --release "${dart_defines[@]}"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    flutter build ios --debug --simulator "${dart_defines[@]}"
    flutter build ios --profile --no-codesign "${dart_defines[@]}"
    flutter build ios --release --no-codesign "${dart_defines[@]}"
  fi
fi

# Store artifacts intentionally stay separate: these commands must fail rather
# than fall back to debug signing when protected release credentials are absent.
if [[ "${RUN_SIGNED_BUILDS:-false}" == "true" ]]; then
  bash scripts/qa_signed_builds.sh
fi
