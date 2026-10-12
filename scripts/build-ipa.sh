#!/usr/bin/env bash
# Builds an unsigned GymApp.ipa for sideloading with Sideloadly or AltStore.
# Entitlements (HealthKit, App Group) are embedded with ldid so the sideloading
# tool keeps them when it re-signs with your Apple ID.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

xcodebuild build \
  -project GymApp.xcodeproj \
  -scheme GymApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | tee build/build.log

APP=build/dd/Build/Products/Release-iphoneos/GymApp.app
ldid -SWidgets/GymWidgets.entitlements "$APP/PlugIns/GymWidgets.appex/GymWidgets"
ldid -SApp/GymApp.entitlements "$APP/GymApp"

rm -rf build/Payload build/GymApp.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry GymApp.ipa Payload)
echo "Built build/GymApp.ipa"
