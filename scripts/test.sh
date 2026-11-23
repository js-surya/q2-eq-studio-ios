#!/usr/bin/env bash
# Runs the EQ logic's tests, then builds the app for the iOS Simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --package-path Packages/EQCore
xcodegen generate --quiet
xcodebuild -scheme EQStudio -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -quiet
echo "All green."
