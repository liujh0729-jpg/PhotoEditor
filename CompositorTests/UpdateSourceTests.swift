import Foundation
import Testing
@testable import Compositor

/// Updates have exactly one source — liujh0729-jpg/PhotoEditor on GitHub — and an installed app can't be pointed at
/// another: the feed the updater reads is the one baked in here, not whatever `Info.plist` or defaults hold, and an
/// item whose archive lives elsewhere is turned down. These tests are what keeps the three in step.
struct UpdateSourceTests {
    @Test func feedIsTheBakedSource() {
        #expect(UpdaterDelegate.feedURL == "https://raw.githubusercontent.com/liujh0729-jpg/PhotoEditor/main/appcast.xml")
        // Packaged builds carry the same feed in Info.plist, so a released app and a build from this tree agree.
        let baked = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        #expect(baked == nil || baked == UpdaterDelegate.feedURL)
    }

    @Test func ownReleasesPass() {
        for path in [
            "/liujh0729-jpg/PhotoEditor/releases/download/v1.5.4/PhotoCompositor.dmg",
            "/liujh0729-jpg/PhotoEditor/releases/latest/download/PhotoCompositor.dmg",
            "/liujh0729-jpg/PhotoEditor/refs/tags/v1.5.4",
            "/liujh0729-jpg/PhotoEditor/raw/main/appcast.xml",
        ] {
            #expect(UpdaterDelegate.isFromUpdateSource(host: "github.com", path: path), "\(path)")
        }
        // A GitHub release asset is served off the CDN after a redirect, under the same repo's path.
        let cdn = "https://objects.githubusercontent.com/github-production-release-asset-2e65be/1/liujh0729-jpg/PhotoEditor/x?Expires=1"
        #expect(UpdaterDelegate.isFromUpdateSource(host: URL(string: cdn)?.host, path: URL(string: cdn)?.path ?? ""))
    }

    @Test func anywhereElseIsTurnedAway() {
        for (host, path) in [
            // The repo this fork was made from, and any other owner's.
            ("github.com", "/robbietilton/Compositor/releases/download/v1.9/PhotoCompositor.dmg"),
            ("raw.githubusercontent.com", "/robbietilton/Compositor/main/appcast.xml"),
            ("github.com", "/someone-else/PhotoEditor/releases/download/v9/PhotoCompositor.dmg"),
            // Somewhere that only looks like the source: another host, or the repo's name with someone else's path.
            ("api.github.com", "/liujh0729-jpg/PhotoEditor/releases/latest"),
            ("github.com", "/liujh0729-jpg/PhotoEditorEvil/releases/download/v9/a.dmg"),
            ("example.com", "/liujh0729-jpg/PhotoEditor/PhotoCompositor.dmg"),
            ("http://liujh0729-jpg@PhotoEditor", "/"),
            // Nothing at all: no host to vouch for it.
            (nil, "/liujh0729-jpg/PhotoEditor/releases/download/v1.5.4/PhotoCompositor.dmg"),
        ] {
            #expect(!UpdaterDelegate.isFromUpdateSource(host: host, path: path), "\(host ?? "nil")\(path)")
        }
        // A file URL from a local build, or a share, isn't a source either.
        let file = URL(fileURLWithPath: "/Users/me/Downloads/PhotoCompositor.dmg")
        #expect(!UpdaterDelegate.isFromUpdateSource(host: file.host, path: file.path))
    }

    /// Sparkle only asks the delegate when it finds one with its own old-style signature; if Swift ever stopped
    /// matching it the gate would sit shut off and nothing would notice, so this says it out loud.
    @Test func gateIsWhereSparkleLooks() {
        #expect(UpdaterDelegate().responds(to: Selector(
            "updater:shouldProceedWithUpdate:updateCheck:error:")))
    }

    /// The feed shipped in this repository: every archive and pointer in it must come from the one source.
    @Test func publishedFeedStaysPut() throws {
        // #filePath is the test source's absolute path at compile time: its parent directory is CompositorTests,
        // and the grandparent is the project root where appcast.xml lives.
        let root = ((#filePath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let feed = try String(contentsOfFile: "\(root)/appcast.xml", encoding: .utf8)
        var urls: [String] = []
        var search = feed.startIndex
        while let found = feed.range(of: "url=\"", range: search..<feed.endIndex) {
            let start = found.upperBound
            guard let end = feed.range(of: "\"", range: start..<feed.endIndex) else { break }
            urls.append(String(feed[start..<end.lowerBound]))
            search = end.upperBound
        }
        #expect(!urls.isEmpty)
        for url in urls {
            let item = try #require(URL(string: url))
            #expect(UpdaterDelegate.isFromUpdateSource(host: item.host, path: item.path), "\(url)")
        }
    }
}
