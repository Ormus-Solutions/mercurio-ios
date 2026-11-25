import UIKit

extension AgentStatus {
    /// The one status palette in the app, in two roles: `tintUIColor` is the
    /// wash (low-opacity capsule fills), `inkUIColor` the foreground (badge
    /// text, the switcher's label). Both read from the Ormus dark tokens.
    /// The app is dark only, so there is no light flavour.
    var tintUIColor: UIColor {
        switch self {
        case .blocked: AgentStatusPalette.gold
        case .done: AgentStatusPalette.ink
        case .working: AgentStatusPalette.inkMuted
        // Idle, Unknown, and anything this build cannot read: not asking for
        // the user, so it stays out of the way.
        default: AgentStatusPalette.idleInk
        }
    }

    /// The legible end of each status colour, for text and small indicators.
    /// Blocked uses goldBright rather than gold: gold on its own wash misses
    /// 4.5:1. Idle text uses a lighter stone than the dim ring, which is too
    /// quiet to read on a card.
    var inkUIColor: UIColor {
        switch self {
        case .blocked: AgentStatusPalette.goldBright
        case .done: AgentStatusPalette.ink
        case .working: AgentStatusPalette.inkMuted
        default: AgentStatusPalette.idleInk
        }
    }

    /// The mark itself. Blocked is a filled gold dot. Working is an ink-muted
    /// ring. Idle and anything unread are a dim hollow ring. Done is a filled
    /// ink dot, so a finished agent is not the same shape as a blocked one.
    var markUIColor: UIColor {
        switch self {
        case .blocked: AgentStatusPalette.gold
        case .done: AgentStatusPalette.ink
        case .working: AgentStatusPalette.inkMuted
        default: AgentStatusPalette.dim
        }
    }

    var markIsFilled: Bool {
        switch self {
        case .blocked, .done: true
        default: false
        }
    }
}

/// Ormus fusion tokens used for agent status. Dark only.
enum AgentStatusPalette {
    static let gold = UIColor(rgb: 0xD29E3D)
    static let goldBright = UIColor(rgb: 0xE0B258)
    static let ink = UIColor(rgb: 0xECEAE3)
    static let inkMuted = UIColor(rgb: 0xA5B0C4)
    static let dim = UIColor(rgb: 0x6D7891)
    /// Legible stand-in for idle text. `dim` is the ring, and it misses 4.5:1
    /// as caption text on a card.
    static let idleInk = UIColor(rgb: 0xBCB09A)
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
