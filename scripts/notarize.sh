#!/usr/bin/env bash
# Archive, export Developer ID Flowa, notarize, and staple.
#
# Usage:
#   ./scripts/notarize.sh
#   NOTARY_PROFILE=YourKeychainProfile ./scripts/notarize.sh
#
# Credentials (first time only):
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#     --apple-id "you@example.com" --team-id 6LZ2DS9JPD --password "app-specific-password"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Flowa"
TEAM_ID="6LZ2DS9JPD"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ARCHIVE_DIR/Flowa-$STAMP.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT/build/export}"
DIST_DIR="${DIST_DIR:-$HOME/Desktop/Mapper/AI development/Notorized Distributions}"
EXPORT_OPTIONS="$ROOT/ExportOptions.plist"

cd "$ROOT"

echo "==> Verifying bundled speech model…"
MODEL="$ROOT/Flowa/Models/openai_whisper-large-v3-v20240930_turbo"
if [[ ! -d "$MODEL/AudioEncoder.mlmodelc" || ! -f "$MODEL/config.json" ]]; then
  echo "ERROR: Bundled model missing at $MODEL" >&2
  echo "Copy the CoreML weights there before notarizing." >&2
  exit 1
fi
du -sh "$MODEL"

mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR" "$DIST_DIR"

echo "==> Archiving Release → $ARCHIVE_PATH"
# Archive with Automatic/Development; export re-signs with Developer ID.
xcodebuild archive \
  -project "$ROOT/Flowa.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic

echo "==> Exporting Developer ID app (re-sign for distribution)…"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

APP="$EXPORT_DIR/Flowa.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: export did not produce Flowa.app" >&2
  ls -la "$EXPORT_DIR" >&2
  exit 1
fi

echo "==> Codesign check…"
codesign -dv --verbose=4 "$APP" 2>&1 | head -30
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vv "$APP" 2>&1 || true

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
echo "==> Version $VERSION ($BUILD)  size $(du -sh "$APP" | awk '{print $1}')"

ZIP="$EXPORT_DIR/Flowa-$VERSION.zip"
echo "==> Zipping for notarytool…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo ""
  echo "No notarytool keychain profile named \"$NOTARY_PROFILE\"."
  echo "Archive + signed export are ready at:"
  echo "  App: $APP"
  echo "  Zip: $ZIP"
  echo "  Archive: $ARCHIVE_PATH"
  echo ""
  echo "Store credentials, then re-run this script (or notarize the zip):"
  echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
  echo "    --apple-id \"you@icloud.com\" --team-id $TEAM_ID --password \"app-specific-password\""
  echo "  xcrun notarytool submit \"$ZIP\" --keychain-profile \"$NOTARY_PROFILE\" --wait"
  echo "  xcrun stapler staple \"$APP\""
  # Still copy signed (pre-notarized) app for convenience
  DEST_APP="$DIST_DIR/Flowa.app"
  rm -rf "$DEST_APP"
  ditto "$APP" "$DEST_APP"
  ditto -c -k --keepParent "$APP" "$DIST_DIR/Flowa-$VERSION-build$BUILD-signed-not-notarized.zip"
  echo "Copied signed app to: $DEST_APP"
  exit 2
fi

echo "==> Submitting to Apple notarization…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"

echo "==> Copying to distribution folder…"
DEST_APP="$DIST_DIR/Flowa.app"
rm -rf "$DEST_APP"
ditto "$APP" "$DEST_APP"
ditto -c -k --keepParent "$APP" "$DIST_DIR/Flowa-$VERSION-build$BUILD.zip"

echo ""
echo "Done. Notarized Flowa $VERSION ($BUILD):"
echo "  $DEST_APP"
echo "  $DIST_DIR/Flowa-$VERSION-build$BUILD.zip"
