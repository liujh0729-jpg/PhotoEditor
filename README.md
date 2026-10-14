# AIPDD PhotoEditor（base Compositor）

**English** · [简体中文](README.zh-Hans.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [العربية](README.ar.md) · [Tiếng Việt](README.vi.md) · [Español](README.es.md) · [Русский](README.ru.md)

Adobe Photoshop costs too much and tools like GIMP don’t feel familiar enough for me to stay in flow. That’s why I built Compositor.

The goal was to create a full-featured image editor that is completely free and open source. I used to use Photoshop for compositing and post-processing, so Compositor is built around that workflow - with the tools needed to create a pixel-perfect final image.

Because it’s open source, you can download the Xcode project and add, remove, or modify any feature to fit your workflow.

## Installation

### Download
Get Compositor from [robbietilton.com/compositor](https://robbietilton.com/compositor), or download the latest release directly from [GitHub Releases](https://github.com/robbietilton/Compositor/releases/latest).

### Homebrew

```sh
brew install --cask robbietilton-compositor
```

## Features

### Layers
- Layers and folders, with opacity and Photoshop's full set of blend modes in its order — a folder's opacity dims everything inside it
- Layer masks: paint, fill, invert, blur and feather them anywhere on the canvas, past the layer's own pixels; link or unlink them to transform a mask on its own
- Clipping masks and folder masks
- Adjustment layers: Hue/Saturation, Levels, Curves, Exposure, Gradient Map, Grain, Black & White, Color Balance, Invert, Gaussian Blur, Motion Blur and Noise
- Layer effects: Stroke, Drop Shadow, Color Overlay, Inner Shadow, Outer Glow and Inner Glow, rendered on the GPU and editable at any time
- Merge Down, Merge Layers and Merge Group (⌘E)
- Duplicate, rename inline, reorder and nest by drag and drop; Option-drag to duplicate; a right-click menu in the Layers panel
- Copy and paste whole layers and folders (⌘C/⌘V with no selection), within a project or between projects, or drag them between projects

### Transform
- Non-destructive move, scale, rotate and flip — images keep their full resolution however small you make them
- Free distort (⌘-drag a handle), with Shift to lock to an axis
- Transform several layers, or a whole folder, together
- Snapping to canvas and layer edges and centers, with guides
- Exact values for position, size, scale and angle, stepped with the arrow keys
- Flip Layer and Flip Canvas, horizontal and vertical

### Selections
- Rectangle and Ellipse Marquee, Freehand and Polygonal Lasso, and the Magic tool — Wand selects by color, Object traces whatever you click (Tab switches)
- Select Subject, and Expand, Contract and Feather on any selection
- Add to and subtract from selections, move the outline, or move and duplicate the pixels inside
- Load a layer's pixels or a mask as a selection
- Content-Aware Fill, which can also extend an image past its edges

### Painting and retouching
- Brush with size, hardness, opacity and smoothing, in Paint or Erase mode (B and E), and Shift for straight lines
- Spot Healing Brush (content-aware)
- Clone Stamp, aligned or not, sampling one layer or all of them
- Blur tool, on pixels or masks
- Gradient tool and Shape tool (rectangles, rounded rectangles, ellipses and lines), which stay editable rather than being rasterized
- Type tool (T): inline multiline editing in draggable, resizable paragraph boxes; font, size, color, alignment and spacing in the tool header; transform text and use it as a clipping mask
- Eyedropper and a full color picker

### Adjustments and filters
- Camera Raw filter: light, color, curves, color mixer, color grading, detail, optics and geometry, in a panel beside the canvas; each section resets to its defaults from its header
- Levels (with Auto), Curves, Hue/Saturation, Exposure, Gradient Map, Grain, Black & White, Color Balance and Invert
- Gaussian Blur and Motion Blur that spread past a layer's edges
- Add Noise, Vignette, Bloom / Glow, Dither, Scanlines, Tonal Contrast, Lens Correction and Remove Background
- Live previews, limited to the selection when there is one
- Last Filter (⌃⌘F) runs the last filter again with the same settings

### Canvas and files
- Multiple projects in tabs
- Search Commands (⌘F): find every menu command and tool by name, as in Raycast or Obsidian, and run it with Return
- Toggle Fullscreen (F): the canvas alone on black over the whole screen, with every panel put away; F or Esc brings them back
- Rulers (⌘R), guides dragged from them, a layout grid with adjustable spacing and subdivisions, and Snap To for guides, grid, layers and document bounds
- Crop with snapping, ratios including 3:4 and 9:16, and Option for symmetric cropping; with a selection, the crop starts at it
- Canvas Size, Image Size and Trim
- A Navigator minimap in the canvas's corner from 300% zoom: the whole document in small with a box around the view; click or drag to move there (View › Navigator)
- Sharp high-quality downsampling when zoomed out, and a pixel grid when zoomed in
- Import JPEG, PNG, HEIC, TIFF, WebP, SVG, camera RAW (with a develop step first) and Photoshop PSD and PSB (8-bit RGB; not CMYK). Photoshop folders, masks, blend modes, fill rectangles/ellipses, and simple horizontal text stay editable; other vectors and vertical text become pixels. A conversion report is shown before anything is applied.
- Large documents: the memory budget scales with your Mac, and a Photoshop file too big to open has its layers cropped to the canvas instead
- Export PNG (⇧⌘E), Export JPEG (⇧⌥⌘S), and Export As (⇧⌥⌘W) for PNG, JPEG or a one-page PDF at the print size, scaled if you like, with a live preview, JPEG quality and file size; Copy Merged
- Keep working while a project saves
- Photoshop-style keyboard shortcuts throughout, remappable in Edit > Keyboard Shortcuts
- Drag a number's label to scrub its value, as in Photoshop
- Automatic updates, signed and notarized

### AI (bring your own gateway)
- The AI Gateway (⌘,) points every AI feature at any OpenAI-compatible server you trust — a hosted one, a corporate proxy, or a local runner. Channels have priority, weight, timeout, optional HTTP/HTTPS/SOCKS proxy, and per-capability overrides for model, path and channel; API keys live in the macOS Keychain, never in a preferences file. A built-in AIPDD channel is pre-configured so you can start with just a key. Test Connection verifies a channel before you save it
- Capabilities are slots, not hard-coded endpoints: Text Chat, Image Generation, Image Editing, Video, Text-to-Speech, Speech-to-Text, Embeddings and Decision Model each pick their own channel and model, so you can, for example, route image work to one provider and chat to another
- Every AI action is a menu command, so it shows up in Search Commands (⌘F) and can be rebound in Edit › Keyboard Shortcuts
- Generate Image: text-to-image with size, quality, style, count and negative prompt; drop results onto the canvas as new layers, or save to disk
- Image Editing and Inpainting (image-to-image): pass the active layer's pixels to the gateway with a prompt, and either replace the layer in place (undoable, mask preserved) or add the result as a new layer; with a live selection or a layer mask, that mask is sent too, so the model edits only what you marked
- Style Transfer: hand the gateway a reference image and a strength (0–100%), match its tone onto the active layer
- Natural Language Editing: describe an edit in plain English — "boost the saturation", "rename to sky", "deselect the subject", "group these layers" — the chat model returns a structured intent and the editor performs it through the same code paths as clicking a menu, with a keyword parser as an offline fallback. Destructive intents (delete, replace pixels) ask before acting
- Semantic Selection: the mask-to-canvas pipeline is wired up — a segmentation mask off the gateway becomes either a layer mask (white reveals) or a live marching-ants selection traced along exact pixel edges, placed under the layer's own transform. The text-to-mask model itself is still a placeholder; the endpoints are ready for a SAM-compatible service
- Video, Voice and Transcription run through the async task queue: submit → poll with exponential backoff → download. Polling has a deadline and honors cancellation, so a stuck gateway can't wedge the panel; a Cancel button drops a task in place
- Nothing leaves your Mac except to the channel you configured; the app does not phone home, does not bundle an API key, and does not meter usage

### Works with AI agents
- AI agents and scripts can build and edit projects directly: a `.comp` is a folder of PNG layers and a manifest, and an open project updates live as it's written. See [Writing Compositor projects](docs/writing-comp-files.md)

## Requirements

- macOS 26.0 or later on a Mac with Apple silicon
- Xcode 26 or later (to build from source)

## Translations

Compositor ships with eight UI languages — English, Simplified Chinese, French, Japanese, Arabic, Vietnamese, Spanish and Russian — and you can pick one explicitly in AI Gateway Settings › General (or leave it on Follow System to track the language order in System Settings). The interface mirrors the locale: Arabic switches to a right-to-left layout on the next launch.

The string catalog lives in `Compositor/Resources/*.lproj/Localizable.strings`, one file per locale, English literal as the key. Missing keys fall back to the English source, so a half-translated locale is still usable. Native-speaker PRs that fill the gaps or improve existing wording are welcome; if you’re picking up a locale for the first time, start with the visible surfaces (menus, AI sheets, tool headers) before the deeper tooltips.

## Building

Open `Compositor.xcodeproj` and run the **Compositor** scheme.

## Releasing

`scripts/release.sh` builds a Release version, signs it with Developer ID, notarizes and staples it, and packages it into `dist/Compositor-<version>.dmg`.

It needs, all kept outside this repository:

- a **Developer ID Application** certificate in the login keychain
- notarization credentials saved with `xcrun notarytool store-credentials "compositor-notary" …`
- [`create-dmg`](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`)

## Community

Compositor is developed in the open, and the fastest way to shape where it goes next is to join the discussion. I keep a small group on WeChat (ID: **raikkonenlxx**) for users and developers to trade prompts, report bugs, share `.comp` files, and talk about gateway setups and AI features — 想一起研究的朋友，加微信 **raikkonenlxx** 备注 Compositor。Add me with "Compositor" in the note so I know you're not a bot.

<div align="center">
  <img src="./docs/references/canvas-group-qr.png" width="260" alt="WeChat QR code — join the AIPDD-Agent-Claw canvas discussion group"/>
</div>
<br>

For issues that should live in the record — reproducible bugs, feature requests, PRs — please still open them on GitHub so the discussion is searchable.

## License

MIT — see [LICENSE](LICENSE).
