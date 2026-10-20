# Releasing a new version

PhotoCompositor ships as a Developer ID–signed, notarized DMG, published as a GitHub Release plus a Sparkle update
feed (`appcast.xml`). The whole path is two scripts, run in order:

1. [`scripts/release.sh`](../scripts/release.sh) — builds, signs, notarizes and staples the app and the DMG.
2. [`scripts/publish.sh`](../scripts/publish.sh) — signs the update, opens the GitHub Release, writes and pushes the feed.

## One-time setup (none of this belongs in the repository)

- A **Developer ID Application** certificate in your login keychain (Team `3W42B7G26D`).
- Notarization credentials, saved once into a keychain profile:

  ```sh
  xcrun notarytool store-credentials "compositor-notary" --apple-id "<Apple ID>" --team-id 3W42B7G26D
  ```

  Use an app-specific password, or an App Store Connect API key. The profile can vanish from the keychain after an
  account or machine reset — if notarization dies with `No Keychain password item found for profile:
  compositor-notary`, run this again. Confirm the account without burning a submission: `xcrun notarytool history
  --keychain-profile compositor-notary`.
- The **Sparkle signing key** in the login keychain (see [Update feed](#update-feed-self-hosted-sparkle)), plus a backup.
- `create-dmg`: `brew install create-dmg`.
- `gh` signed in, or `GH_TOKEN` set, with push access to the repo the app's updater reads.

## Bump the version first

In `Compositor.xcodeproj` raise `MARKETING_VERSION` (e.g. `1.5.5`) **and** `CURRENT_PROJECT_VERSION` — the build
number, e.g. `53` — across the targets. Sparkle compares the build number, so it has to increase or installed clients
won't see the update. `release.sh` and `publish.sh` read both straight from the project.

## Step 1 — build a notarized DMG

```sh
NOTARIZE=1 ./scripts/release.sh
```

`NOTARIZE` defaults to **off** so a routine run never queues junk submissions at Apple; set it explicitly for anything
you distribute. The script archives and exports with Developer ID, notarizes and staples the app (retrying until the
ticket validates), builds the DMG, then signs/notarizes/staples the DMG. It finally mounts the finished image and
re-checks the app **inside** it — the check that catches the "outer DMG stapled but the app wasn't" failure — before
printing what Gatekeeper will say. Output: `dist/PhotoCompositor-<version>.dmg`.

## Step 2 — publish the release and the feed

```sh
RELEASE_NOTES=$'Fix the first thing\nFix the second thing' ./scripts/publish.sh
```

One change per line in `RELEASE_NOTES`; those lines become both the Release body and the in-app update alert. The
script:

- derives the publish target from the **`SUFeedURL` baked into the app `release.sh` just exported**, so the release and
  the feed land exactly where installed clients look (`PUBLISH_REPO=owner/name` overrides it);
- **refuses to publish** unless the app's `SUPublicEDKey` equals the public half of the key that will sign the update —
  a feed clients can't verify is worse than no feed;
- `sign_update`s the DMG, opens GitHub Release `v<version>` holding the asset named `PhotoCompositor.dmg` (so
  `…/releases/latest/download/PhotoCompositor.dmg` stays a stable link), rewrites `appcast.xml`, then commits and pushes
  it to whichever remote mirrors that repo.

If it reports `Release v<version> already exists`, raise the version and build number before retrying.

## Update feed (self-hosted Sparkle)

`Config/Info.plist` carries the keys that decide where updates come from and what vouches for them:

- `SUFeedURL` — the appcast this fork serves.
- `SUPublicEDKey` — the public half of the EdDSA pair that must match the key `publish.sh` signs with.

The private key lives in your login keychain (the "Private key for signing Sparkle updates" item, service
`https://sparkle-project.org`, default account `ed25519`). The `generate_keys` binary that manages it ships in the
Sparkle build artifacts, under `…/SourcePackages/artifacts/sparkle/Sparkle/bin/`. Back it up and verify it:

```sh
generate_keys -p                                   # prints the public key; must equal SUPublicEDKey
generate_keys -x <backup>/sparkle-private-key.b64  # export. The file is the UNPROTECTED private key — store it like a password.
generate_keys -f <backup>/sparkle-private-key.b64  # restore it into the keychain on a new machine
```

Lose this key and you can no longer sign updates anyone's installed app will accept: you'd generate a fresh pair, swap
`SUPublicEDKey`, rebuild, and every existing install would have to be reinstalled once to trust the new key.

**Scope:** only builds installed from this fork — with the fork's `SUPublicEDKey` and `SUFeedURL` baked in — can see or
accept these updates. Installs carrying an earlier publisher's key never will; they must be reinstalled once to move
onto this track.

## Checklist

1. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
2. `NOTARIZE=1 ./scripts/release.sh` → Gatekeeper ends with `accepted` / `source=Notarized Developer ID`.
3. `RELEASE_NOTES=$'…' ./scripts/publish.sh`.
4. Download the release asset, check its SHA-256 against the DMG you built, and confirm the raw `appcast.xml` now lists
   the new version.
