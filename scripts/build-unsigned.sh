#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
mkdir -p build "$work/Payload"
xcodegen generate --spec project.yml
xcodebuild -project MaykopTest.xcodeproj -scheme MaykopTest -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$work/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
ditto "$work/DerivedData/Build/Products/Release-iphoneos/MaykopTest.app" "$work/Payload/MaykopTest.app"
python3 scripts/inspect-app.py "$work/Payload/MaykopTest.app" > build/entitlements-report.json
(cd "$work" && zip -qry "$OLDPWD/build/MaykopTest.ipa" Payload)
shasum -a 256 build/MaykopTest.ipa > build/SHA256SUMS
