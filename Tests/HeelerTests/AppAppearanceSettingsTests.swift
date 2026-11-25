import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Mercurio

@MainActor
@Suite("App appearance settings")
struct AppAppearanceSettingsTests {
    private func makeDefaults() throws -> (UserDefaults, cleanup: () -> Void) {
        let suiteName = "hm-app-appearance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    @Test func defaultsToDark() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppAppearanceSettings(defaults: defaults)

        #expect(settings.selection == .dark)
        #expect(settings.preferredColorScheme == .dark)
    }

    @Test func selectionPersistsAcrossStoreInstances() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppAppearanceSettings(defaults: defaults)

        settings.select(.dark)

        #expect(AppAppearanceSettings(defaults: defaults).selection == .dark)
    }

    /// A newer build's option name must not brick an older one. Mercurio is
    /// dark, so an unreadable stored value falls back to dark.
    @Test func unknownStoredOptionFallsBackToDark() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        defaults.set("solar-flare", forKey: "app-appearance")

        #expect(AppAppearanceSettings(defaults: defaults).selection == .dark)
        #expect(AppAppearanceSettings(defaults: defaults).preferredColorScheme == .dark)
    }

    @Test(arguments: [AppAppearanceOption.system, .light, .dark])
    func everyStoredChoiceRendersDark(option: AppAppearanceOption) throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppAppearanceSettings(defaults: defaults)

        settings.select(option)

        #expect(settings.selection == .dark)
        #expect(settings.preferredColorScheme == .dark)
    }

    @Test func storedChoicesStillDecodeAndThePickerOffersDarkOnly() {
        #expect(AppAppearanceOption.allCases == [.system, .light, .dark])
        #expect(AppAppearanceOption.offered == [.dark])
    }

    @Test func bundledFacesRegister() {
        OrmusType.register()
        #expect(UIFont(name: OrmusType.titleName, size: 17) != nil)
        #expect(UIFont(name: OrmusType.bodyName, size: 17) != nil)
        #expect(UIFont(name: OrmusType.monoName, size: 13) != nil)
    }
}
