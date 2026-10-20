import Foundation
import Testing
import AppKit
@testable import Compositor

/// Smart Arrange without a window: the content box read off a layer's pixels (and its mask), the pure
/// shifts the commands compute, and a run landing on the document as one history entry.
@MainActor
struct SmartArrangeTests {
    /// A picture with an opaque 4×4 block at pixels x 2…5, y 2…5 (top-left counting), clear around it.
    private func insetSwatch() -> CGImage {
        let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        // Core Graphics counts from the bottom; this rect covers rows 3…6 whichever way you count, and
        // the bitmap's rows read top-down.
        context.fill(CGRect(x: 2, y: 3, width: 4, height: 4))
        return context.makeImage()!
    }

    private func fullSwatch(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A half-width white-on-black mask: the right half of the picture reveals.
    private func rightHalfMask() -> CGImage {
        let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 5, y: 0, width: 5, height: 10))
        return context.makeImage()!
    }

    // MARK: The content reading

    @Test func contentBoundsFindsTheOpaqueBlock() {
        let box = EditorSession.contentBounds(of: insetSwatch(), mask: nil)
        #expect(abs(box.minX - 0.2) < 0.001 && abs(box.maxX - 0.6) < 0.001)
        #expect(abs(box.minY - 0.3) < 0.001 && abs(box.maxY - 0.7) < 0.001, "the unit box counts y from the top")
    }

    @Test func contentBoundsFollowsTheMask() {
        // The block would say x 0.2…0.6; the mask's white (right half) clamps it to 0.5…0.6.
        let box = EditorSession.contentBounds(of: insetSwatch(), mask: rightHalfMask())
        #expect(abs(box.minX - 0.5) < 0.001, "masked-out pixels don't count as content")
        #expect(abs(box.maxX - 0.6) < 0.001)
    }

    @Test func emptyPictureAlignsByItsWholeBox() {
        let clear = CGContext(data: nil, width: 6, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        clear.clear(CGRect(x: 0, y: 0, width: 6, height: 6))
        let box = EditorSession.contentBounds(of: clear.makeImage()!, mask: nil)
        #expect(box == CGRect(x: 0, y: 0, width: 1, height: 1), "nothing to line up: the unit box stands")
    }

    // MARK: The pure math

    private func row(_ id: UUID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     content: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), rotation: CGFloat = 0) -> SmartArrange.Row {
        SmartArrange.Row(id: id,
                         transform: LayerTransform(origin: CGPoint(x: x, y: y), size: CGSize(width: w, height: h), rotation: rotation),
                         content: content)
    }

    @Test func alignLeftPullsContentToTheCanvasEdge() {
        let a = UUID(), b = UUID()
        let shifts = SmartArrange.shifts(for: .alignLeft,
                                         rows: [row(a, 30, 0, 100, 100),
                                                row(b, 10, 5, 40, 20, content: CGRect(x: 0.25, y: 0, width: 0.5, height: 1))],
                                         canvas: CGSize(width: 200, height: 200))
        #expect(shifts[a] == CGSize(width: -30, height: 0), "the frame itself is already content")
        // b's content starts at 10 + 0.25×40 = 20 in the document.
        #expect(shifts[b] == CGSize(width: -20, height: 0), "and comes to zero by its pixels, not its frame")
        #expect(shifts[a]?.height == 0, "a left alignment leaves the vertical place alone")
    }

    @Test func alignCentersSquaresBothAxes() {
        let a = UUID()
        let shifts = SmartArrange.shifts(for: .alignCenters,
                                         rows: [row(a, 0, 0, 100, 50)], canvas: CGSize(width: 200, height: 200))
        #expect(shifts[a] == CGSize(width: 50, height: 75))
    }

    @Test func rotatedRowsAlignByTheirFrame() {
        let a = UUID()
        // A quarter turn: the content rect would no longer mean the same place, so the box stands alone.
        let shifts = SmartArrange.shifts(for: .alignRight,
                                         rows: [row(a, 10, 0, 100, 50, rotation: 90)],
                                         canvas: CGSize(width: 200, height: 200))
        #expect(shifts[a] == CGSize(width: 90, height: 0), "the frame's right edge goes to the canvas's")
    }

    @Test func distributeKeepsTheFirstLayerAndEvenGaps() {
        let a = UUID(), b = UUID(), c = UUID()
        let shifts = SmartArrange.shifts(for: .distributeHorizontally,
                                         rows: [row(a, 0, 10, 20, 20), row(b, 40, 30, 20, 20), row(c, 60, 0, 20, 20)],
                                         canvas: CGSize(width: 200, height: 200))
        #expect(shifts[a] == nil, "the run starts where its first layer sits")
        // Gaps of 20 and 0 even out at ten apiece: a at 0, b at 30, c already at 60.
        #expect(shifts[b] == CGSize(width: -10, height: 0))
        #expect(shifts[c] == nil, "the last layer already sits on the even line")
    }

    // MARK: The run on a document

    @Test func aRunMovesTheSelectedLayersInOneHistoryEntry() async throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)
        session.insert(ImportedImage(image: fullSwatch(100, 50), thumbnail: fullSwatch(20, 10), name: "Wide"))
        session.insert(ImportedImage(image: fullSwatch(20, 20), thumbnail: fullSwatch(10, 10), name: "Small"))
        let ids = (session.document?.layers ?? []).map(\.id)
        #expect(ids.count == 2)
        session.selectedLayerIDs = Set(ids)
        // Both were inserted centered: the wide one sits at x 50, the small at x 90.
        let moved = await session.applySmartArrange(.alignLeft)
        #expect(moved == 2)
        #expect(session.document?.layers[0].transform.origin.x == 0)
        #expect(session.document?.layers[1].transform.origin.x == 0)
        #expect(session.history.undoName == "Smart Arrange")
        session.undo()
        #expect(session.document?.layers[0].transform.origin.x == 50, "one undo takes the whole run back")
    }

    @Test func aLoneLayerIsNotASet() async throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)
        session.insert(ImportedImage(image: fullSwatch(100, 50), thumbnail: fullSwatch(20, 10), name: "Only"))
        session.selectedLayerIDs = []
        #expect(!session.canSmartArrange, "the menu waits for a set")
        #expect(await session.applySmartArrange(.alignLeft) == 0)
        #expect(session.history.undoName != "Smart Arrange")
    }
}

/// The learned habits: tallies per action and parameter, the most-used read the engine falls back to,
/// and the round trip through UserDefaults. Each case tallies under its own made-up action name, so
/// parallel runs never share a row.
@Suite(.serialized)
@MainActor
struct PreferenceStoreTests {
    /// Tallies live in the host's defaults between runs, so each case invents its own action name:
    /// nothing from an earlier run can answer, and no parallel case shares the row.
    private func fresh(_ what: String) -> String { "preference test \(what) \(UUID().uuidString)" }

    @Test func theTallyPicksTheMostUsedValue() {
        let store = PreferenceStore.shared
        let action = fresh("most used")
        #expect(store.mostUsed(action: action, parameter: "opacity") == nil, "an action nobody has run knows nothing")
        store.record(action: action, parameter: "opacity", value: 0.5)
        store.record(action: action, parameter: "opacity", value: 0.5)
        store.record(action: action, parameter: "opacity", value: 0.8)
        #expect(store.mostUsed(action: action, parameter: "opacity") == 0.5, "twice beats once")
        #expect(store.mostUsed(action: action, parameter: "feather") == nil, "another key stays unknown")
    }

    @Test func wholeAndFractionalNamesShareARow() {
        let store = PreferenceStore.shared
        let action = fresh("names")
        store.record(action: action, parameter: "value", value: 50)
        store.record(action: action, parameter: "value", value: 50.0)
        #expect(store.mostUsed(action: action, parameter: "value") == 50, "Int and Double read as one habit")
    }

    @Test func anIntentRecordsEveryNumberItCarries() {
        let store = PreferenceStore.shared
        let intent = EditingIntent(action: .changeOpacity, parameters: [
            "opacity": AnyCodable(0.25),
            "name": AnyCodable("not a number"),
        ])
        store.record(intent)
        #expect(store.mostUsed(action: "changeOpacity", parameter: "opacity") == 0.25)
        #expect(store.mostUsed(action: "changeOpacity", parameter: "name") == nil, "text isn't a habit")
    }

    @Test func theFallbackAnswersWhenTheIntentCarriesNoNumber() {
        let store = PreferenceStore.shared
        let action = fresh("fallback")
        store.record(action: action, parameter: "opacity", value: 0.4)
        // The engine's reader takes the habit where the panel's typing would have been; an action
        // nobody has run stays blank.
        let intent = EditingIntent(action: .unknown)
        #expect(!intent.usedPreference, "nothing tallied under this action's name")
        #expect(store.mostUsed(action: action, parameter: "opacity") == 0.4)
    }

    @Test func talliesSurviveTheDefaultsRoundTrip() throws {
        let store = PreferenceStore.shared
        let action = fresh("round trip")
        store.record(action: action, parameter: "value", value: 12)
        let data = try #require(UserDefaults.standard.data(forKey: "aiParameterPreferences"))
        let decoded = try JSONDecoder().decode([String: [String: [String: Int]]].self, from: data)
        #expect(decoded[action]?["value"]?["12"] == 1)
    }
}
