#!/usr/bin/env bash
# Offline iOS build for uni-app x (DCloud iOS Vapor SDK).
# Runs on macOS only. See docs/ios-github-actions.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/build"
CACHE="$BUILD/cache"
SDK_ZIP="$CACHE/UniAppXSDK-iOS-Vapor.zip"
RES_ZIP="$CACHE/app-ios-resources.zip"
SDK_ROOT="$BUILD/sdk"
RES_ROOT="$BUILD/resources"
HOST="$BUILD/host"
PLUGIN_OUT="$BUILD/plugins"
PLUGIN_BUILD="$BUILD/plugin-build"
LOGS="$BUILD/logs"

APP_ID="${APP_ID:-__UNI__607FC4F}"
BUNDLE_ID="${BUNDLE_ID:-com.zhaiwo.my}"
VERSION_NAME="${VERSION_NAME:-1.1.01}"
VERSION_CODE="${VERSION_CODE:-1101}"
TEAM_ID="${TEAM_ID:-3Q57K52TU5}"
PROFILE_NAME="${PROFILE_NAME:-pingguopro}"
RUN_PLUGINS="${RUN_PLUGINS:-true}"

mkdir -p "$SDK_ROOT" "$RES_ROOT" "$PLUGIN_OUT" "$PLUGIN_BUILD" "$LOGS"

step() { printf '\n=== %s ===\n' "$*"; }

step "Extracting DCloud iOS SDK"
if [ ! -d "$SDK_ROOT/UniAppXVaporDemo" ]; then
  ditto -x -k "$SDK_ZIP" "$SDK_ROOT"
fi

step "Extracting exported app-ios resources"
rm -rf "$RES_ROOT"
mkdir -p "$RES_ROOT"
ditto -x -k "$RES_ZIP" "$RES_ROOT"

if [ -d "$RES_ROOT/app-ios" ]; then
  RES_APP_ROOT="$RES_ROOT/app-ios"
elif [ -d "$RES_ROOT/$APP_ID" ]; then
  RES_APP_ROOT="$RES_ROOT"
else
  echo "resources zip must contain app-ios/ or $APP_ID/ at the root" >&2
  exit 1
fi

[ -d "$RES_APP_ROOT/$APP_ID/www" ] || { echo "missing $RES_APP_ROOT/$APP_ID/www" >&2; exit 1; }
[ -d "$RES_APP_ROOT/uni_modules" ] || { echo "missing $RES_APP_ROOT/uni_modules" >&2; exit 1; }

step "Preparing host project from UniAppXVaporDemo"
rm -rf "$HOST"
cp -R "$SDK_ROOT/UniAppXVaporDemo" "$HOST"
rm -rf "$HOST/UniAppXVaporDemo/uni-app-x/apps"
mkdir -p "$HOST/UniAppXVaporDemo/uni-app-x/apps"
cp -R "$RES_APP_ROOT/$APP_ID" "$HOST/UniAppXVaporDemo/uni-app-x/apps/"
cp "$ROOT/scripts/ios/ViewController.swift" "$HOST/UniAppXVaporDemo/ViewController.swift"
ICON_DIR="$HOST/UniAppXVaporDemo/Assets.xcassets/AppIcon.appiconset"
cp "$ROOT/scripts/ios/AppIcon-1024.png" "$ICON_DIR/AppIcon-1024.png"
cp "$ROOT/scripts/ios/AppIcon-Contents.json" "$ICON_DIR/Contents.json"

HOST_PROJECT="$HOST/UniAppXVaporDemo.xcodeproj"
INFO_PLIST="$HOST/UniAppXVaporDemo/Info.plist"
PB=/usr/libexec/PlistBuddy

step "Configuring Info.plist"
set_plist() {
  local key="$1" type="$2" value="$3"
  if "$PB" -c "Print $key" "$INFO_PLIST" >/dev/null 2>&1; then
    "$PB" -c "Set $key $value" "$INFO_PLIST"
  else
    "$PB" -c "Add $key $type $value" "$INFO_PLIST"
  fi
}

set_plist ":CFBundleDisplayName" string "苹果地产"
set_plist ":CFBundleShortVersionString" string "$VERSION_NAME"
set_plist ":CFBundleVersion" string "$VERSION_CODE"
set_plist ":LSRequiresIPhoneOS" bool true
set_plist ":UIFileSharingEnabled" bool true
set_plist ":NSAppTransportSecurity:NSAllowsArbitraryLoads" bool true
set_plist ":uniapp-x:appid" string "$APP_ID"
set_plist ":uniapp-x:ipatype" integer 2
set_plist ":uniapp-x:uniRuntimeVersion" string "5.26"
set_plist ":uniapp-x:channel" string "appstore"
set_plist ":uniapp-x:initPrivacyAuthorization" bool true

set_plist ":NSCameraUsageDescription" string "用于拍摄房源、证件和办公照片"
set_plist ":NSPhotoLibraryUsageDescription" string "用于选择房源、证件和办公照片"
set_plist ":NSPhotoLibraryAddUsageDescription" string "用于保存图片到相册"
set_plist ":NSMicrophoneUsageDescription" string "用于语音消息、录音和视频拍摄"
set_plist ":NSContactsUsageDescription" string "用于选择联系人并办理业务"
set_plist ":NSLocationWhenInUseUsageDescription" string "用于考勤打卡、带看和附近房源"
set_plist ":NSLocationAlwaysAndWhenInUseUsageDescription" string "用于考勤打卡、带看和附近房源"
set_plist ":NSBluetoothAlwaysUsageDescription" string "用于连接智能门锁"
set_plist ":NSBluetoothPeripheralUsageDescription" string "用于连接智能门锁"
set_plist ":NSLocalNetworkUsageDescription" string "用于连接局域网设备和调试服务"
set_plist ":NSFaceIDUsageDescription" string "用于身份核验和密码解锁"

set_plist ":CFBundleURLTypes" array
"$PB" -c "Add :CFBundleURLTypes:0 dict" "$INFO_PLIST"
set_plist ":CFBundleURLTypes:0:CFBundleURLName" string "$BUNDLE_ID"
"$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$INFO_PLIST"
"$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string tcwangAgent" "$INFO_PLIST"
"$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string cxrl" "$INFO_PLIST"

set_plist ":LSApplicationQueriesSchemes" array
query_index=0
for scheme in tcwangAgent tcwangagent rokidai alipay alipays alipayqr alipayshare alipayauth apmqpdispatch mqpdispatch iosamap baidumap; do
  "$PB" -c "Add :LSApplicationQueriesSchemes:$query_index string $scheme" "$INFO_PLIST"
  query_index=$((query_index + 1))
done

step "Merging plugin Info.plist entries"
for plugin_info in "$RES_APP_ROOT"/uni_modules/*/utssdk/app-ios/Info.plist; do
  [ -f "$plugin_info" ] || continue
  python3 "$ROOT/scripts/ios/merge-plist.py" "$INFO_PLIST" "$plugin_info" "$BUNDLE_ID"
done

step "Configuring host project"
ruby "$ROOT/scripts/ios/configure-host.rb" \
  "$HOST_PROJECT" "$PLUGIN_OUT" "$RES_APP_ROOT/uni_modules" "$INFO_PLIST" \
  "$BUNDLE_ID" "$TEAM_ID" "$PROFILE_NAME" "$VERSION_NAME" "$VERSION_CODE" "$RUN_PLUGINS" \
  | tee "$LOGS/configure-host.log"

if [ "$RUN_PLUGINS" = "true" ]; then
  step "Building UTS plugin xcframeworks"
  SDK_ROOT="$SDK_ROOT" \
  PLUGINS_ROOT="$RES_APP_ROOT/uni_modules" \
  PLUGIN_OUT="$PLUGIN_OUT" \
  PLUGIN_BUILD="$PLUGIN_BUILD" \
  LOGS="$LOGS" \
  ruby "$ROOT/scripts/ios/build-plugins.rb" | tee "$LOGS/build-plugins.log"

  step "Adding plugin xcframeworks to host project"
  ruby "$ROOT/scripts/ios/configure-host.rb" \
    "$HOST_PROJECT" "$PLUGIN_OUT" "$RES_APP_ROOT/uni_modules" "$INFO_PLIST" \
    "$BUNDLE_ID" "$TEAM_ID" "$PROFILE_NAME" "$VERSION_NAME" "$VERSION_CODE" "true" \
    | tee -a "$LOGS/configure-host.log"
fi

step "Archiving app"
ARCHIVE="$BUILD/app.xcarchive"
rm -rf "$ARCHIVE" "$BUILD/export"
set -o pipefail
xcodebuild \
  -project "$HOST_PROJECT" \
  -scheme UniAppXVaporDemo \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  MARKETING_VERSION="$VERSION_NAME" \
  CURRENT_PROJECT_VERSION="$VERSION_CODE" \
  archive 2>&1 | tee "$LOGS/archive.log"

step "Exporting IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/scripts/ios/ExportOptions.plist" \
  -exportPath "$BUILD/export" \
  2>&1 | tee "$LOGS/export.log"

step "Done"
find "$BUILD/export" -name '*.ipa' -maxdepth 2 -print
