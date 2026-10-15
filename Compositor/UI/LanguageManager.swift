import AppKit
import Combine
import SwiftUI

/// Owns the app's UI language preference. The user picks one of the eight
/// shipped languages (or "Follow System"); the choice is stored in this app's
/// preference domain under the standard `AppleLanguages` key, which macOS
/// reads on next launch to decide which `.lproj` bundle to serve.
///
/// Because a SwiftUI view hierarchy captures `Bundle.main` at load time, we
/// can't hot-swap the language — changing the setting writes the preference,
/// then offers a "Restart now" button that reopens the app after `terminate`.
@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    enum AppLanguage: String, CaseIterable, Identifiable {
        case system
        case en
        case zhHans = "zh-Hans"
        case fr
        case ja
        case ar
        case vi
        case es
        case ru

        var id: String { rawValue }

        /// Shown in the picker in each language's own script, regardless of
        /// the currently active UI language — matches what System Settings
        /// does for per-app language lists.
        var nativeName: String {
            switch self {
            case .system: return "Follow System"
            case .en: return "English"
            case .zhHans: return "简体中文"
            case .fr: return "Français"
            case .ja: return "日本語"
            case .ar: return "العربية"
            case .vi: return "Tiếng Việt"
            case .es: return "Español"
            case .ru: return "Русский"
            }
        }

        /// The tag written to `AppleLanguages`. `nil` means "defer to the
        /// system's ordered language list".
        var appleLanguagesEntry: String? {
            self == .system ? nil : rawValue
        }

        /// True for Arabic, which lays out right-to-left. SwiftUI picks up
        /// the direction from the active locale on next launch, so we only
        /// need this to gate a hint in the picker.
        var isRightToLeft: Bool { self == .ar }
    }

    @Published var selection: AppLanguage

    private static let appleLanguagesKey = "AppleLanguages"
    private static let selectionKey = "compositor.uiLanguage"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.selectionKey),
           let lang = AppLanguage(rawValue: raw) {
            selection = lang
        } else {
            selection = .system
        }
    }

    /// Writes the new preference. Callers should follow up with `relaunch()`
    /// (or ask the user to quit and reopen) so the change actually takes
    /// effect on the string catalog.
    func apply(_ language: AppLanguage) {
        selection = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.selectionKey)
        if let code = language.appleLanguagesEntry {
            UserDefaults.standard.set([code], forKey: Self.appleLanguagesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
        }
        UserDefaults.standard.synchronize()
    }

    /// Reopens the app and terminates the current process. We launch the
    /// fresh copy first, so if `openApplication` fails the user still has a
    /// running window in front of them.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // The language is read once, at launch, from `AppleLanguages`. Without a
        // new instance, `openApplication` just brings the already-running copy
        // forward, so the language never reloads and it looks like nothing happened.
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { application, error in
            DispatchQueue.main.async {
                // Only quit this copy once a fresh one is actually up; if the re-open
                // failed (a translocated or read-only bundle, say), leave the running
                // window so the user isn't suddenly left with nothing.
                if error == nil, application != nil { NSApp.terminate(nil) }
            }
        }
    }
}
