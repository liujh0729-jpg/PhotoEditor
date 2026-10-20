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
# ⚠️ 公证开关：默认关闭，跑脚本不会向 Apple 提交公证（避免误触发历史堆积）。
#    需要真正出对外分发包时显式开启：NOTARIZE=1 ./scripts/release.sh
NOTARIZE="${NOTARIZE:-0}"
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

if [[ "$NOTARIZE" == "1" ]]; then
  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$APP_PATH" "$WORK/$PRODUCT.zip"
  xcrun notarytool submit "$WORK/$PRODUCT.zip" --keychain-profile "$NOTARY_PROFILE" --verbose --wait
  xcrun stapler staple "$APP_PATH"
  # The ticket is written into Contents/CodeResources, a plain file inside the bundle, so the DMG copy
  # later on can't drop it — but a staple that silently no-ops would ship an unstapled app and nobody
  # would notice until a user hit Gatekeeper. Confirm it actually landed before packaging: --wait can
  # return Accepted a beat before the ticket is fetchable from Apple, so retry a handful of times.
  for attempt in {1..5}; do
    if xcrun stapler validate "$APP_PATH" >/dev/null 2>&1; then
      echo "    app ticket stapled and validated"
      break
    fi
    if (( attempt == 5 )); then
      echo "!! app staple did not take after 5 tries; refusing to ship an unstapled app" >&2
      exit 1
    fi
    echo "    ticket not fetchable yet (try $attempt), waiting…"
    sleep 15
  done
else
  echo "==> Skipping app notarization (NOTARIZE!=1); artifact is local-only"
fi

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
if [[ "$NOTARIZE" == "1" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --verbose --wait
  xcrun stapler staple "$DMG"
else
  echo "==> Skipping DMG notarization (NOTARIZE!=1); DMG is Developer ID signed but not stapled"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  echo "==> Verifying the app inside the finished DMG is stapled too"
  # The outer ticket says nothing about the app the user drags out of the image, which is exactly how
  # 1.5.3 shipped unstapled. Mount the sealed DMG read-only and check the bundle itself, so a packaging
  # regression can't pass the outer DMG while leaving an unstapled app behind. The mount is torn down on
  # every exit path: a leftover read-only volume would wedge the next run's rm -rf of $WORK, and a
  # "Resource busy" detach on a freshly-indexed volume must not fail an otherwise-valid release.
  MOUNT=$(mktemp -d "$WORK/mnt.XXXXXX")
  detach_mount() { [[ -n "${MOUNT:-}" ]] && hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; }
  trap detach_mount EXIT
  hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
  xcrun stapler validate "$MOUNT/$PRODUCT.app"
  codesign --verify --deep --strict "$MOUNT/$PRODUCT.app"
  detach_mount
  trap - EXIT
fi

if [[ "$NOTARIZE" == "1" ]]; then
  echo "==> What Gatekeeper will say on another Mac"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP_PATH"
else
  echo "==> Unnotarized build; skipping Gatekeeper distribution checks (rerun with NOTARIZE=1 to verify)"
fi
echo "==> Done: $DMG"
