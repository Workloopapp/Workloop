#!/usr/bin/env python3
"""Validate public mobile build configuration without printing credential values."""

import argparse
import base64
import hashlib
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path


PROJECT_REF = "imtbyrvsonzvtddswbtb"
ALLOWED_KEYS = {
    "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY",
    "PAYMENT_COLLECTION_ENABLED",
    "APNS_ENVIRONMENT",
    "TAP_TO_PAY_ENABLED",
    "WORKLOOP_CRASH_REPORTING_ENABLED",
    "WORKLOOP_SUBSCRIPTIONS_ENABLED",
}


class ReleaseValidationError(ValueError):
    """An error with a fixed, safe-to-display explanation."""


def fail(message):
    raise ReleaseValidationError(message)


def load_defines(path):
    raw = Path(path).read_text(encoding="utf-8")
    if raw.lstrip().startswith("{"):
        data = json.loads(raw)
        if not isinstance(data, dict):
            fail("Release JSON must contain an object.")
        return data
    data = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)\s*=\s*(.*)", line)
        if not match:
            fail("Release .env contains an unsupported line; use simple KEY=value or JSON.")
        key, value = match.groups()
        if key in data:
            fail("Release .env contains duplicate keys.")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        data[key] = value
    return data


def validate(data, payments):
    if payments not in ("true", "false"):
        fail("RELEASE_PAYMENT_COLLECTION_ENABLED must be true or false.")
    if set(data) - ALLOWED_KEYS:
        fail("Release defines contain unsupported keys; only public mobile configuration is allowed.")
    if data.get("SUPABASE_URL") != f"https://{PROJECT_REF}.supabase.co":
        fail("Store builds require the exact Workloop production Supabase URL.")
    if not (data.get("SUPABASE_PUBLISHABLE_KEY") or data.get("SUPABASE_ANON_KEY")):
        fail("A production Supabase public key is required.")
    for key_name in ("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"):
        key = data.get(key_name)
        if not key:
            continue
        if not isinstance(key, str):
            fail("Supabase public keys must be strings.")
        if key.startswith("sb_publishable_") and re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{20,}", key):
            continue
        try:
            parts = key.split(".")
            if len(parts) != 3:
                fail("invalid")
            payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
        except (ValueError, TypeError, UnicodeDecodeError):
            fail("Supabase key must be a publishable key or a production legacy anon JWT.")
        if not isinstance(payload, dict) or payload.get("role") != "anon" or payload.get("ref") != PROJECT_REF:
            fail("Legacy Supabase key must have the anon role for the production project.")
    if "PAYMENT_COLLECTION_ENABLED" in data:
        configured = str(data["PAYMENT_COLLECTION_ENABLED"]).lower()
        if configured != payments:
            fail("Payment capability conflicts with the explicit release choice.")
    if data.get("APNS_ENVIRONMENT", "production") != "production":
        fail("Store builds require the production APNs environment.")
    if str(data.get("TAP_TO_PAY_ENABLED", False)).lower() != "false":
        fail("This release keeps Tap to Pay disabled until its device and entitlement gates pass.")
    crash_reporting = data.get("WORKLOOP_CRASH_REPORTING_ENABLED", True)
    if not isinstance(crash_reporting, (bool, str)) or str(crash_reporting).lower() not in ("true", "false"):
        fail("WORKLOOP_CRASH_REPORTING_ENABLED must be true or false.")
    subscriptions = data.get("WORKLOOP_SUBSCRIPTIONS_ENABLED", True)
    if not isinstance(subscriptions, (bool, str)) or str(subscriptions).lower() not in ("true", "false"):
        fail("WORKLOOP_SUBSCRIPTIONS_ENABLED must be true or false.")
    return {**data, "PAYMENT_COLLECTION_ENABLED": payments == "true", "APNS_ENVIRONMENT": "production", "TAP_TO_PAY_ENABLED": False,
            "WORKLOOP_CRASH_REPORTING_ENABLED": str(crash_reporting).lower() == "true",
            "WORKLOOP_SUBSCRIPTIONS_ENABLED": str(subscriptions).lower() == "true"}


def version_parts(version):
    match = re.fullmatch(r"(\d+\.\d+\.\d+)\+([1-9]\d*)", version)
    if not match:
        fail("Store version must use x.y.z+positive-build-number.")
    return match.groups()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prepare = sub.add_parser("prepare")
    prepare.add_argument("--source", required=True)
    prepare.add_argument("--output", required=True)
    prepare.add_argument("--export-options", required=True)
    prepare.add_argument("--payments", required=True)
    verify = sub.add_parser("verify-ipa")
    verify.add_argument("--artifact", required=True)
    verify.add_argument("--version", required=True)
    metadata = sub.add_parser("metadata")
    metadata.add_argument("--source", required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        data = validate(load_defines(args.source), args.payments)
        text = Path("pubspec.yaml").read_text(encoding="utf-8")
        match = re.search(r"^version:\s*(\S+)", text, re.MULTILINE)
        version_parts(match.group(1) if match else "")
        Path(args.output).write_text(json.dumps(data), encoding="utf-8")
        Path(args.output).chmod(0o600)
        with open(args.export_options, "wb") as handle:
            plistlib.dump({
                "method": "app-store-connect", "destination": "export",
                "signingStyle": "automatic", "teamID": "6RH526FD7B",
                "manageAppVersionAndBuildNumber": False,
                "stripSwiftSymbols": True, "uploadSymbols": True,
                "testFlightInternalTestingOnly": False,
            }, handle)
        print("Validated production mobile configuration and explicit payment capability.")
    elif args.command == "verify-ipa":
        name, number = version_parts(args.version)
        with zipfile.ZipFile(args.artifact) as archive:
            paths = [p for p in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info.plist", p)]
            if len(paths) != 1:
                fail("Expected exactly one main app in the IPA.")
            info = plistlib.loads(archive.read(paths[0]))
        if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), str(info.get("CFBundleVersion"))) != ("com.ismaeel.workloop", name, number):
            fail("IPA identity does not match the reviewed source version.")
        # geolocator's Swift Package links the Always authorization API even
        # though Workloop asks only for foreground weather permission.
        for permission in ("NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"):
            if not isinstance(info.get(permission), str) or not info[permission].strip():
                fail("IPA is missing a required location purpose string.")
        if "location" in info.get("UIBackgroundModes", []):
            fail("Workloop does not support background location tracking.")
        print("IPA bundle and version match the reviewed source.")
    else:
        data = load_defines(args.source)
        payments = str(data.get("PAYMENT_COLLECTION_ENABLED", "")).lower()
        data = validate(data, payments)
        print(f"supabase_project_ref={PROJECT_REF}")
        print(f"payment_collection_enabled={payments}")
        print("apns_environment=production")
        print("tap_to_pay_enabled=false")
        print(f"crash_reporting_enabled={str(data['WORKLOOP_CRASH_REPORTING_ENABLED']).lower()}")
        print(f"subscriptions_enabled={str(data['WORKLOOP_SUBSCRIPTIONS_ENABLED']).lower()}")
        fingerprint = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
        print(f"public_build_config_sha256={fingerprint}")


if __name__ == "__main__":
    try:
        main()
    except ReleaseValidationError as error:
        print(str(error), file=sys.stderr)
        sys.exit(65)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException):
        # Parser/library exceptions can contain source content. Never echo them.
        print("Release configuration/artifact validation failed; check production public defines, explicit payment choice and artifact version.", file=sys.stderr)
        sys.exit(65)
