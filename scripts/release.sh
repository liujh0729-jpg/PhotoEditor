#!/bin/zsh
# Builds a signed, notarized PhotoCompositor DMG that opens without warnings on any Mac.
#
# Needs, all kept out of this repository:
#   - a "Developer ID Application" certificate in the login keychain
#   - notarization credentials saved once with:
#       xcrun notarytool store-credentials "compositor-notary" --apple-id "…" --team-id 3W42B7G26D
#   - create-dmg (brew install create-dmg)
# The DMG window background is scripts/dmg/dmg-bg.jpg (600 × 380, the window's exact size) plus
# dmg-bg-retina.jpg (1200 × 760) for Retina displays.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP=Compositor
PRODUCT=PhotoCompositor
TEAM=3W42B7G26D
IDENTITY="Developer ID Application"
NOTARY_PROFILE=compositor-notary
# Built outside Dropbox: the extended attributes it adds to files make code signing fail.
WORK="$HOME/Library/Caches/CompositorRelease"
DIST="$PROJECT_DIR/dist"

settings=$(xcodebuild -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
echo "==> $PRODUCT $VERSION ($BUILD)"

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"

echo "==> Archiving a Release build"
xcodebuild archive -quiet \
  -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$WORK/$APP.xcarchive" -derivedDataPath "$WORK/DerivedData" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM"

echo "==> Exporting, signed with Developer ID"
xcodebuild -exportArchive -quiet \
  -archivePath "$WORK/$APP.xcarchive" \
  -exportOptionsPlist "$PROJECT_DIR/scripts/ExportOptions.plist" \
  -exportPath "$WORK/export"
APP_PATH="$WORK/export/$PRODUCT.app"
echo "==> Local preflight: strict signature checks"
codesign --verify --deep --strict -vvv "$APP_PATH"
# Run the Gatekeeper assessment for visibility only: the notarization ticket isn't stapled yet, so a
# rejection here flags packaging trouble, not a reason to stop the release; the post-staple checks below decide.
spctl --assess --type execute -vv "$APP_PATH" || echo "note: pre-notarization assessment; the real verdict is checked after stapling"

echo "==> Notarizing the app"
ditto -c -k --keepParent "$APP_PATH" "$WORK/$PRODUCT.zip"
xcrun notarytool submit "$WORK/$PRODUCT.zip" --keychain-profile "$NOTARY_PROFILE" --verbose --wait
xcrun stapler staple "$APP_PATH"

echo "==> Building the DMG window"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
DMG="$DIST/$PRODUCT-$VERSION.dmg"
rm -f "$DMG"
# Icon centers in the DMG window, in points from its top-left.
APP_X=160
APPLICATIONS_X=440
ICON_Y=180
background=()
LOW="$PROJECT_DIR/scripts/dmg/dmg-bg.jpg"
HIGH="$PROJECT_DIR/scripts/dmg/dmg-bg-retina.jpg"
if [[ -f "$LOW" && -f "$HIGH" ]]; then
  # Finder takes one background file; a TIFF holding both sizes stays sharp on Retina displays.
  sips -s format png -s dpiWidth 72 -s dpiHeight 72 "$LOW" --out "$WORK/background.png" >/dev/null
  sips -s format png -s dpiWidth 144 -s dpiHeight 144 "$HIGH" --out "$WORK/background@2x.png" >/dev/null
  tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null
  background=(--background "$WORK/background.tiff")
elif [[ -f "$LOW" ]]; then
  background=(--background "$LOW")
fi
# Pinned to HFS+ UDZO (zlib) on purpose: the tool's default drifts with version and host, and an
# HFS+ image mounts everywhere back to the oldest installers, with none of the APFS-in-a-DMG
# notarization flakiness seen on this pipeline.
create-dmg \
  --filesystem HFS+ \
  --format UDZO \
  --volname "$PRODUCT" \
  --window-pos 200 120 --window-size 600 380 \
  --icon-size 128 --text-size 13 \
  --icon "$PRODUCT.app" "$APP_X" "$ICON_Y" --hide-extension "$PRODUCT.app" \
  --app-drop-link "$APPLICATIONS_X" "$ICON_Y" \
  "${background[@]}" \
  "$DMG" "$STAGE"

echo "==> Signing and notarizing the DMG"
codesign --sign "$IDENTITY" --timestamp --options runtime "$DMG"
# Preflight the image itself before submitting: the outer signature must verify strict. The
# Gatekeeper look is visibility only — before the ticket is stapled it reports "Unnotarized Developer ID"
# even for a correctly packaged DMG — so it must not stop the run; the post-staple checks below decide.
codesign --verify --strict -vvv "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG" || echo "note: pre-notarization assessment; the real verdict is checked after stapling"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --verbose --wait
xcrun stapler staple "$DMG"

echo "==> What Gatekeeper will say on another Mac"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
spctl --assess --type execute --verbose=2 "$APP_PATH"
echo "==> Done: $DMG"
