#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
source scripts/dev_env.sh

# Store builds never inherit the placeholder defines used by qa_all.sh.
: "${RELEASE_DEFINES_FILE:?Set RELEASE_DEFINES_FILE to the production .env or JSON file.}"
: "${RELEASE_PAYMENT_COLLECTION_ENABLED:?Set RELEASE_PAYMENT_COLLECTION_ENABLED explicitly to true or false.}"
: "${RELEASE_PLATFORMS:?Set RELEASE_PLATFORMS to ios, android, or ios,android.}"
case "$RELEASE_PLATFORMS" in
  ios|android|ios,android|android,ios) ;;
  *) echo "RELEASE_PLATFORMS must be ios, android, or ios,android." >&2; exit 64 ;;
esac
if [[ "$RELEASE_PLATFORMS" == *ios* && "$(uname -s)" != Darwin ]]; then
  echo "iOS distribution builds require macOS." >&2
  exit 69
fi

release_defines="$(mktemp "${TMPDIR:-/tmp}/workloop-release-defines.XXXXXX")"
release_export_options="$(mktemp "${TMPDIR:-/tmp}/workloop-release-export.XXXXXX")"
trap 'rm -f "$release_defines" "$release_export_options"' EXIT
python3 scripts/release_config.py prepare \
  --source "$RELEASE_DEFINES_FILE" --output "$release_defines" \
  --export-options "$release_export_options" \
  --payments "$RELEASE_PAYMENT_COLLECTION_ENABLED"
export RELEASE_CONFIG_SNAPSHOT="$release_defines"

candidate_artifacts=()
if [[ "$RELEASE_PLATFORMS" == *android* ]]; then
  candidate_artifacts+=(build/app/outputs/bundle/release/app-release.aab)
fi
if [[ "$RELEASE_PLATFORMS" == *ios* ]]; then
  candidate_artifacts+=(build/ios/ipa/Workloop.ipa)
  # Flutter overwrites this archive before export. Protect it even if no IPA exists.
  if [[ -e build/ios/archive/Runner.xcarchive ]]; then
    echo "Existing iOS archive must be preserved; build the candidate in an isolated checkout." >&2
    exit 78
  fi
fi

bash scripts/qa_release_candidate.sh --prepare "${candidate_artifacts[@]}"
release_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -1)"
release_name="${release_version%+*}"
release_number="${release_version##*+}"
release_args=(--release --dart-define-from-file="$release_defines"
  --build-name="$release_name" --build-number="$release_number")

if [[ "$RELEASE_PLATFORMS" == *android* ]]; then
  flutter build appbundle "${release_args[@]}"
fi
if [[ "$RELEASE_PLATFORMS" == *ios* ]]; then
  flutter build ipa "${release_args[@]}" --export-options-plist="$release_export_options"
fi

# The file is a private, normalized snapshot, so edits to the original .env
# during compilation cannot change one platform without changing the other.
bash scripts/qa_release_candidate.sh --record-artifacts "${candidate_artifacts[@]}"
