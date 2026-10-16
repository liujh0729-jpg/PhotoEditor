#!/bin/zsh
# Publishes the DMG that release.sh built: a GitHub Release (v<version>) holding PhotoCompositor.dmg, then the Sparkle
# update feed (appcast.xml, committed to main) pointing at it.
#
# Run release.sh first. Needs the Sparkle signing key in the login keychain and `gh` signed in.
# Release notes, a change a line: RELEASE_NOTES=$'First change\nSecond change' ./scripts/publish.sh
# They're listed on the GitHub Release and in the update alert (the feed item's <changes>).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP=Compositor
PRODUCT=PhotoCompositor
REPO=robbietilton/Compositor
WORK="$HOME/Library/Caches/CompositorRelease"
SIGN_UPDATE="$WORK/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

settings=$(xcodebuild -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
MINIMUM=$(print -r -- "$settings" | awk -F' = ' '/ MACOSX_DEPLOYMENT_TARGET = /{print $2; exit}')
TAG="v$VERSION"
SOURCE="$PROJECT_DIR/dist/$PRODUCT-$VERSION.dmg"
[[ -f "$SOURCE" ]] || { echo "No $SOURCE — run scripts/release.sh first."; exit 1; }
[[ -x "$SIGN_UPDATE" ]] || { echo "Sparkle's sign_update isn't built — run scripts/release.sh first."; exit 1; }
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
git -C "$PROJECT_DIR" push -q
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
