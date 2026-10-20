# Notes for AI agents

PhotoCompositor is a macOS image editor for compositing and photo work, written in Swift (SwiftUI and AppKit, with some C for pixel work).

## Naming

The product is **PhotoCompositor**: use it for everything a user sees or downloads — the window title, the app menu ("Hide PhotoCompositor"), the about box, the DMG and the GitHub Release asset, the Sparkle feed, and the document type labels in `Config/Info.plist`.

These stay **Compositor** on purpose, so existing installs, file associations and update feeds keep working — do not rename them:

- The Xcode project and scheme (`Compositor.xcodeproj`, scheme `Compositor`) and the `Compositor/` source folder.
- The bundle id `com.wonderassembly.compositor` and the type identifiers `com.compositor.*`.
- The GitHub repo path (`robbietilton/Compositor`) and the `SUFeedURL` that points at it.

## Designing or editing a Compositor project

If you've been asked to make or change an image in a `.comp` project, you don't need the app's source code. Read [docs/writing-comp-files.md](docs/writing-comp-files.md): it covers the file format, the rules that make a project load, and how to write it safely while it's open, so the person can watch the canvas update as you work.

## Working on the app itself

- Build: open `Compositor.xcodeproj` and run the **Compositor** scheme, or `xcodebuild -project Compositor.xcodeproj -scheme Compositor -destination 'platform=macOS' build`.
- Tests: the `CompositorTests` target (`xcodebuild ... test -only-testing:CompositorTests`). CI runs these on every push.
- Releasing a signed, notarized build and updating the Sparkle feed is described in [docs/releasing.md](docs/releasing.md).
- Match the surrounding code: its naming, its comment style and density.
- American spelling in code, comments and UI ("color", not "colour").
- The project file format is described in [docs/project-format.md](docs/project-format.md). A change to what's saved means a format version bump there and in `ProjectManifest.current`.
