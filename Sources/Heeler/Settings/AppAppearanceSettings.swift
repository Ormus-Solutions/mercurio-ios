import Foundation
import Observation
import SwiftUI

/// How the app itself should be lit. Separate from the terminal theme slots
/// (`TerminalThemeSettings`), which pick a palette *per* appearance — this
/// picks which appearance is in force in the first place.
enum AppAppearanceOption: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What this case would mean on its own. Mercurio ignores it: the app
    /// is dark, and `AppAppearanceSettings.preferredColorScheme` is always dark.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The settings screen offers Dark only. System and Light stay in
    /// `allCases` so a value stored by an earlier build still decodes.
    static let offered: [AppAppearanceOption] = [.dark]
}

/// The app-wide light/dark override, applied once at the root view. Everything
/// downstream — including the terminal surfaces, which resolve their theme
/// against `\.colorScheme` — follows from that single `preferredColorScheme`.
@MainActor
@Observable
final class AppAppearanceSettings {
    private static let defaultsKey = "app-appearance"

    private(set) var selection: AppAppearanceOption
    @ObservationIgnored private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppAppearanceOption.init(rawValue:))
        // Mercurio is dark. An unknown or older System/Light value decodes
        // and is rewritten so the next launch does not keep it.
        selection = .dark
        if stored != .dark {
            defaults.set(AppAppearanceOption.dark.rawValue, forKey: Self.defaultsKey)
        }
    }

    var preferredColorScheme: ColorScheme? { .dark }

    func select(_: AppAppearanceOption) {
        selection = .dark
        defaults.set(AppAppearanceOption.dark.rawValue, forKey: Self.defaultsKey)
    }
}
