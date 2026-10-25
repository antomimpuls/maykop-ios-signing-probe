#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
command -v xcodegen >/dev/null
command -v xcodebuild >/dev/null
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/maykop-signing-probe.XXXXXX")"
mkdir -p build "$work_dir/Payload"

xcodegen generate --spec project.yml
xcodebuild \
  -project MaykopSigningProbe.xcodeproj \
  -scheme MaykopSigningProbe \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$work_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

app_path="$work_dir/Payload/MaykopSigningProbe.app"
ditto "$work_dir/DerivedData/Build/Products/Release-iphoneos/MaykopSigningProbe.app" "$app_path"

# Embed the requested capability for a re-signer to preserve. Ad-hoc signing
# needs no Apple account and does NOT authorize installation on an iPhone.
codesign --force --sign - --generate-entitlement-der \
  --entitlements Signing/PacketTunnel.entitlements \
  "$app_path/PlugIns/ProbeTunnel.appex"
codesign --force --sign - --generate-entitlement-der \
  --entitlements Signing/PacketTunnel.entitlements "$app_path"
codesign --verify --deep --strict "$app_path"

archive_path="$project_dir/build/MaykopSigningProbe-$(date -u +%Y%m%dT%H%M%SZ).ipa"
(cd "$work_dir" && zip -qry "$archive_path" Payload)
shasum -a 256 "$archive_path"
printf 'IPA prepared for external signing; not yet installable or device-verified.\n'
