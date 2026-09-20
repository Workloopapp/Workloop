#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mode="${1:---prepare}"
if [[ "$mode" == "--prepare" || "$mode" == "--record-artifacts" ]]; then
  shift
else
  echo "Usage: $0 [--prepare|--record-artifacts] [build artifact ...]" >&2
  exit 64
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Git is required for release-candidate provenance." >&2
  exit 69
fi

dirty_state="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$dirty_state" ]]; then
  echo "Release-candidate preflight requires a clean worktree." >&2
  echo "Commit, intentionally remove, or otherwise resolve every entry first:" >&2
  echo "$dirty_state" >&2
  exit 78
fi

tracked_signing_files="$(git ls-files \
  'android/key.properties' \
  'android/*.jks' \
  'android/*.keystore' \
  'android/app/*.jks' \
  'android/app/*.keystore')"
if [[ -n "$tracked_signing_files" ]]; then
  echo "Android signing material must never be tracked:" >&2
  echo "$tracked_signing_files" >&2
  exit 78
fi

commit_sha="$(git rev-parse HEAD)"
expected_sha="${RELEASE_EXPECTED_SHA:-}"
if [[ -n "$expected_sha" ]]; then
  resolved_expected_sha="$(git rev-parse "$expected_sha^{commit}")"
  if [[ "$resolved_expected_sha" != "$commit_sha" ]]; then
    echo "Release SHA mismatch." >&2
    echo "Expected: $resolved_expected_sha" >&2
    echo "Current:  $commit_sha" >&2
    exit 78
  fi
fi

branch_name="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$branch_name" ]]; then
  branch_name="DETACHED"
fi
describe_ref="$(git describe --tags --always --dirty 2>/dev/null || git rev-parse --short HEAD)"
pubspec_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -1)"
if [[ -z "$pubspec_version" ]]; then
  echo "Could not read the app version from pubspec.yaml." >&2
  exit 65
fi

release_config_metadata=""
if [[ -n "${RELEASE_CONFIG_SNAPSHOT:-}" ]]; then
  release_config_metadata="$(python3 scripts/release_config.py metadata --source "$RELEASE_CONFIG_SNAPSHOT")"
fi

flutter_version="unavailable"
if command -v flutter >/dev/null 2>&1; then
  flutter_version="$(flutter --version 2>/dev/null | head -1)"
fi

provenance_file="${RELEASE_PROVENANCE_FILE:-build/release/release-provenance.txt}"
case "$provenance_file" in
  build/*|/tmp/*) ;;
  *)
    echo "RELEASE_PROVENANCE_FILE must be under build/ or /tmp/." >&2
    exit 64
    ;;
esac

for artifact_path in "$@"; do
  case "$artifact_path" in
    build/*.aab|build/*.ipa|build/*/*.aab|build/*/*.ipa|build/*/*/*.aab|build/*/*/*.ipa|build/*/*/*/*.aab|build/*/*/*/*.ipa) ;;
    *)
      echo "Release artifacts must be .aab or .ipa files under build/: $artifact_path" >&2
      exit 64
      ;;
  esac
done

if [[ "$mode" == "--prepare" ]]; then
  for artifact_path in "$@"; do
    if [[ -e "$artifact_path" ]]; then
      echo "Refusing to build over a stale release artifact: $artifact_path" >&2
      echo "Move or remove it intentionally, then rerun the preflight." >&2
      exit 78
    fi
  done
fi

mkdir -p "$(dirname "$provenance_file")"

if [[ "$mode" == "--prepare" ]]; then
  {
    echo "workloop_release_candidate"
    echo "verified_at_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "commit_sha=$commit_sha"
    echo "branch=$branch_name"
    echo "describe=$describe_ref"
    echo "pubspec_version=$pubspec_version"
    echo "flutter=$flutter_version"
    echo "worktree=clean"
    if [[ -n "$release_config_metadata" ]]; then
      echo "$release_config_metadata"
    fi
  } >"$provenance_file"

  echo "Release-candidate preflight passed."
else
  if [[ ! -f "$provenance_file" ]] || ! grep -Fxq "commit_sha=$commit_sha" "$provenance_file"; then
    echo "Run --prepare for this exact clean commit before recording artifacts." >&2
    exit 78
  fi
  if [[ "$#" -eq 0 ]]; then
    echo "Pass at least one release artifact to --record-artifacts." >&2
    exit 64
  fi
  if [[ -n "$release_config_metadata" ]]; then
    while IFS= read -r config_line; do
      if ! grep -Fxq "$config_line" "$provenance_file"; then
        echo "Release configuration changed after candidate preparation." >&2
        exit 78
      fi
    done <<<"$release_config_metadata"
  fi
  if command -v shasum >/dev/null 2>&1; then
    hash_command=(shasum -a 256)
  elif command -v sha256sum >/dev/null 2>&1; then
    hash_command=(sha256sum)
  else
    echo "shasum or sha256sum is required to record artifact provenance." >&2
    exit 69
  fi

  for artifact_path in "$@"; do
    if [[ ! -f "$artifact_path" ]]; then
      echo "Missing release artifact: $artifact_path" >&2
      exit 78
    fi
    if [[ "$artifact_path" == *.ipa ]]; then
      python3 scripts/release_config.py verify-ipa \
        --artifact "$artifact_path" --version "$pubspec_version"
    fi
  done

  {
    echo "artifacts_recorded_at_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    for artifact_path in "$@"; do
      artifact_hash="$("${hash_command[@]}" "$artifact_path" | awk '{print $1}')"
      artifact_size="$(wc -c <"$artifact_path" | tr -d '[:space:]')"
      echo "artifact_path=$artifact_path"
      echo "artifact_size_bytes=$artifact_size"
      echo "artifact_sha256=$artifact_hash"
    done
  } >>"$provenance_file"

  echo "Release artifact provenance recorded."
fi

echo "Commit: $commit_sha"
echo "Version: $pubspec_version"
echo "Provenance: $provenance_file"
