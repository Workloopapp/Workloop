#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "SUPABASE_ACCESS_TOKEN is required" >&2
  exit 2
fi
if [[ -z "${SUPABASE_PROJECT_REF:-}" ]]; then
  echo "SUPABASE_PROJECT_REF is required" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

max_age_hours="${BACKUP_MAX_AGE_HOURS:-36}"
if [[ ! "$max_age_hours" =~ ^[0-9]+$ ]] || (( max_age_hours < 1 )); then
  echo "BACKUP_MAX_AGE_HOURS must be a positive integer" >&2
  exit 2
fi

response_file="$(mktemp -t workloop-backups.XXXXXX)"
trap 'rm -f "$response_file"' EXIT

curl --fail --silent --show-error \
  --connect-timeout 10 \
  --max-time 30 \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_REF}/database/backups" \
  >"$response_file"

latest_epoch="$(
  jq -r '
    [.backups[]? | select(.status == "COMPLETED") | .inserted_at]
    | sort
    | last // empty
    | sub("\\.[0-9]+\\+00:00$"; "Z")
    | sub("\\+00:00$"; "Z")
    | fromdateiso8601
  ' "$response_file"
)"

if [[ -z "$latest_epoch" || "$latest_epoch" == "null" ]]; then
  echo "No completed Supabase backup was reported" >&2
  exit 1
fi

now_epoch="$(date -u +%s)"
age_seconds="$((now_epoch - latest_epoch))"
max_age_seconds="$((max_age_hours * 3600))"
if (( age_seconds < 0 || age_seconds > max_age_seconds )); then
  echo "Latest completed Supabase backup is outside the ${max_age_hours}-hour freshness window" >&2
  exit 1
fi

age_hours="$((age_seconds / 3600))"
echo "Supabase backup health passed: latest completed backup is ${age_hours} hour(s) old."
