#!/usr/bin/env bash
# Archives the app for the App Store and exports the .ipa to dist/, for TestFlight.
# Needs your team in Config/Signing.xcconfig. With --upload, sends it to App Store Connect too
# (the app's record must exist there first; see docs/APP_STORE.md).
# Usage: scripts/archive.sh [--upload]
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(scripts/version.sh); build=$(scripts/version.sh --build)
archive="dist/EQStudio-$version-$build.xcarchive"
rm -rf "$archive" "dist/$version-$build"
xcodegen generate --quiet
xcodebuild archive -project EQStudio.xcodeproj -scheme EQStudio -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates -quiet
options=Config/ExportOptions.plist
if [ "${1:-}" = "--upload" ]; then
    options=$(mktemp -t ExportOptions).plist
    sed 's#<string>export</string>#<string>upload</string>#' Config/ExportOptions.plist > "$options"
fi
xcodebuild -exportArchive -archivePath "$archive" -exportPath "dist/$version-$build" \
    -exportOptionsPlist "$options" -allowProvisioningUpdates -quiet
echo "EQ Studio $version ($build): $( [ "${1:-}" = "--upload" ] && echo "uploaded to App Store Connect" || echo "dist/$version-$build" )"
