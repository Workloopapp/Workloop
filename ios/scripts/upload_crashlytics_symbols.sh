#!/bin/sh
set -eu

# Firebase is resolved through Flutter's Swift Package Manager integration.
# Flutter CLI and Xcode use different BUILD_DIR layouts; support both without
# searching arbitrary caches or uploading symbols from another application.
case "${CONFIGURATION:-}" in
  Release*|Profile*) ;;
  *) exit 0 ;;
esac
case "${PLATFORM_NAME:-}" in
  iphoneos) ;;
  *) exit 0 ;;
esac

# Archive BUILD_DIR can point into Xcode's ArchiveIntermediates even though
# Flutter resolved packages under its own iOS output directory.
flutter_build_dir="${FLUTTER_BUILD_DIR:-build}"
case "$flutter_build_dir" in
  /*) ;;
  *) flutter_build_dir="${FLUTTER_APPLICATION_PATH:-${PROJECT_DIR:-.}/..}/$flutter_build_dir" ;;
esac

for script in \
  "$flutter_build_dir/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run" \
  "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run" \
  "${BUILD_DIR}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run" \
  "${PODS_ROOT:-}/FirebaseCrashlytics/run"; do
  if [ -f "$script" ]; then
    exec /bin/sh "$script"
  fi
done

echo "error: Firebase Crashlytics symbol uploader is missing. Resolve the Firebase Swift package before building a device archive." >&2
exit 1
