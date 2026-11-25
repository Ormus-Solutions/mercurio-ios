import CoreText
import SwiftUI
import UIKit

/// Cormorant Garamond for titles, Inter for body, JetBrains Mono for labels
/// and keys. The terminal already draws JetBrains Mono through Ghostty.
enum OrmusType {
    static let titleName = "CormorantGaramond-Regular"
    static let bodyName = "Inter-Regular"
    static let monoName = "JetBrainsMono-Regular"

    private static let files = [
        "CormorantGaramond-Variable",
        "Inter-Regular",
        "JetBrainsMono-Regular",
    ]

    /// Registers the bundled faces. Safe to call more than once. Looks in the
    /// app bundle and the test bundle, since a unit test does not always see
    /// the app's resources as `Bundle.main`.
    static func register() {
        let bundles = [Bundle.main, Bundle(for: AppAppearanceSettings.self)]
        var seen: Set<String> = []
        for bundle in bundles {
            for name in files {
                guard let url = bundle.url(forResource: name, withExtension: "ttf"),
                    seen.insert(url.path).inserted
                else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    static func title(_ size: CGFloat) -> Font {
        .custom(titleName, size: size, relativeTo: .title)
    }

    static func body(_ size: CGFloat = 17) -> Font {
        .custom(bodyName, size: size, relativeTo: .body)
    }

    static func mono(_ size: CGFloat) -> Font {
        .custom(monoName, size: size, relativeTo: .caption)
    }

    static func uiFont(named name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }
}

/// Dark chrome for the bars. Applied once at launch, after the fonts register.
enum OrmusChrome {
    static func apply() {
        let deep = UIColor(red: 14 / 255, green: 24 / 255, blue: 48 / 255, alpha: 1)
        let ink = UIColor(red: 236 / 255, green: 234 / 255, blue: 227 / 255, alpha: 1)
        let title = OrmusType.uiFont(named: OrmusType.titleName, size: 17)
        let large = OrmusType.uiFont(named: OrmusType.titleName, size: 34)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = deep
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: ink,
            .font: title,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: large,
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 20 / 255, green: 33 / 255, blue: 61 / 255, alpha: 1)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // The page under the bars. A list that hides its scroll background
        // shows this instead of system black.
        UIWindow.appearance().backgroundColor = OrmusPalette.deepUIColor
        UITableView.appearance().backgroundColor = OrmusPalette.deepUIColor
        UICollectionView.appearance().backgroundColor = OrmusPalette.deepUIColor

        let search = UISearchBar.appearance()
        search.barTintColor = OrmusPalette.deepUIColor
        search.tintColor = UIColor(red: 210 / 255, green: 158 / 255, blue: 61 / 255, alpha: 1)
        search.searchTextField.backgroundColor = OrmusPalette.midnightUIColor
        search.searchTextField.textColor = UIColor(
            red: 236 / 255, green: 234 / 255, blue: 227 / 255, alpha: 1)
    }
}
