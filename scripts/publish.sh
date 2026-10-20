#!/bin/zsh
# Publishes the DMG that release.sh built: a GitHub Release (v<version>) holding PhotoCompositor.dmg, then the Sparkle
# update feed (appcast.xml, committed to main) pointing at it.
#
# Run release.sh first. Needs the Sparkle signing key in the login keychain and `gh` signed in.
# The release and the feed land on the repo the built app's SUFeedURL points at; override with PUBLISH_REPO=owner/name.
# Release notes, a change a line: RELEASE_NOTES=$'First change\nSecond change' ./scripts/publish.sh
# They're listed on the GitHub Release and in the update alert (the feed item's <changes>).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP=Compositor
PRODUCT=PhotoCompositor
WORK="$HOME/Library/Caches/CompositorRelease"
SIGN_UPDATE="$WORK/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
GENERATE_KEYS="${SIGN_UPDATE%/*}/generate_keys"
APP_PLIST="$WORK/export/$PRODUCT.app/Contents/Info.plist"

settings=$(xcodebuild -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
MINIMUM=$(print -r -- "$settings" | awk -F' = ' '/ MACOSX_DEPLOYMENT_TARGET = /{print $2; exit}')
TAG="v$VERSION"
SOURCE="$PROJECT_DIR/dist/$PRODUCT-$VERSION.dmg"
[[ -f "$SOURCE" ]] || { echo "No $SOURCE — run scripts/release.sh first."; exit 1; }
# Never publish an unstapled DMG: release.sh's notarization is opt-in (NOTARIZE defaults off), so a run
# that forgot it yields a valid-looking local DMG that Gatekeeper blocks on other Macs. Refuse here.
xcrun stapler validate "$SOURCE" >/dev/null 2>&1 \
  || { echo "$SOURCE isn't notarized/stapled — rerun with NOTARIZE=1 ./scripts/release.sh before publishing."; exit 1; }
# Publish wherever the built updater actually reads from: pull the owner/name out of the SUFeedURL release.sh
# baked into the exported app, so the release and the feed land exactly where clients will look. PUBLISH_REPO
# overrides that when you build from a different fork than the one the feed points at.
[[ -r "$APP_PLIST" ]] || { echo "$APP_PLIST is missing — run scripts/release.sh first."; exit 1; }
[[ -x "$SIGN_UPDATE" ]] || { echo "Sparkle's sign_update isn't built — run scripts/release.sh first."; exit 1; }
feed="$(plutil -extract SUFeedURL raw "$APP_PLIST" 2>/dev/null || true)"
feed_repo="$(print -r -- "$feed" | sed -nE 's#^[a-z]+://(raw\.)?github(usercontent)?\.com/([^/]+/[^/]+)(/|$).*#\3#p' || true)"
REPO="${PUBLISH_REPO:-$feed_repo}"
[[ -n "$REPO" ]] || { echo "Can't tell which repo to publish to (SUFeedURL was '$feed'). Set PUBLISH_REPO=owner/name."; exit 1; }
# Refuse to publish a feed the app can't trust: an update signed with the keychain private key only verifies if
# the built app embeds the matching public key. generate_keys -p reads that key back from the keychain, so the
# two are compared before anything is uploaded.
expected="$(plutil -extract SUPublicEDKey raw "$APP_PLIST" 2>/dev/null || true)"
actual=""
[[ -x "$GENERATE_KEYS" ]] && actual="$("$GENERATE_KEYS" -p 2>/dev/null | tail -1 || true)"
[[ -z "$expected" || -z "$actual" || "$expected" == "$actual" ]] \
  || { echo "The app's SUPublicEDKey ($expected) isn't the public key that would sign this update ($actual) — clients would reject it. Fix Info.plist or the keychain key."; exit 1; }
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Raise the version (and build number) first."
  exit 1
fi

echo "==> $PRODUCT $VERSION ($BUILD)"
# Every release names its file PhotoCompositor.dmg, so …/releases/latest/download/PhotoCompositor.dmg always works.
mkdir -p "$WORK/publish"
DMG="$WORK/publish/$PRODUCT.dmg"
cp "$SOURCE" "$DMG"

echo "==> Signing the update for Sparkle"
signature=$("$SIGN_UPDATE" "$DMG")

changes=("${(@f)${RELEASE_NOTES:-}}")
changes=(${changes:#})
[[ "${RELEASE_NOTES:-}" != *']]>'* ]] || { echo "RELEASE_NOTES can't contain ]]>."; exit 1; }
notes="$PRODUCT $VERSION"
(( ${#changes} )) && notes=$(printf -- '- %s\n' "${changes[@]}")
changes_xml=""
(( ${#changes} )) && changes_xml="
      <changes><![CDATA[${(pj:\n:)changes}]]></changes>"

echo "==> Creating GitHub Release $TAG"
gh release create "$TAG" "$DMG" --repo "$REPO" --title "$PRODUCT $VERSION" --notes "$notes"

echo "==> Publishing the update feed"
cat > "$PROJECT_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$PRODUCT</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/$TAG</link>$changes_xml
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$PRODUCT.dmg" $signature type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
git -C "$PROJECT_DIR" add appcast.xml
git -C "$PROJECT_DIR" commit -q -m "Publish update feed for $PRODUCT $VERSION"
# Push the feed to the remote that mirrors the repo the updater reads — the branch's default tracking remote is
# usually the upstream, and a fork's feed shouldn't land there.
remote=""
for r in $(git -C "$PROJECT_DIR" remote); do
  [[ "$(git -C "$PROJECT_DIR" remote get-url "$r")" == *"$REPO"* ]] && { remote="$r"; break; }
done
[[ -n "$remote" ]] || { echo "No git remote mirrors $REPO; add one so the feed lands where the updater reads it."; exit 1; }
git -C "$PROJECT_DIR" push -q "$remote" "HEAD:refs/heads/main"
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
