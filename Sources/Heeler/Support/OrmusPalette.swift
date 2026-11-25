import SwiftUI
import UIKit

/// Ormus fusion tokens (ormus-brand v0.2.0). Dark only. The accent is gold;
/// surfaces that still use the system dark chrome pick it up through tint.
enum OrmusPalette {
    static let deep = Color(red: 14.0 / 255, green: 24.0 / 255, blue: 48.0 / 255)
    static let midnight = Color(red: 20.0 / 255, green: 33.0 / 255, blue: 61.0 / 255)
    static let gold = Color(red: 210.0 / 255, green: 158.0 / 255, blue: 61.0 / 255)
    static let goldBright = Color(red: 224.0 / 255, green: 178.0 / 255, blue: 88.0 / 255)
    static let ink = Color(red: 236.0 / 255, green: 234.0 / 255, blue: 227.0 / 255)
    static let inkMuted = Color(red: 165.0 / 255, green: 176.0 / 255, blue: 196.0 / 255)
    static let dim = Color(red: 109.0 / 255, green: 120.0 / 255, blue: 145.0 / 255)
    static let codeBg = Color(red: 11.0 / 255, green: 18.0 / 255, blue: 38.0 / 255)
    static let danger = Color(red: 212.0 / 255, green: 79.0 / 255, blue: 79.0 / 255)

    static let deepUIColor = UIColor(red: 14.0 / 255, green: 24.0 / 255, blue: 48.0 / 255, alpha: 1)
    static let midnightUIColor = UIColor(red: 20.0 / 255, green: 33.0 / 255, blue: 61.0 / 255, alpha: 1)
}

extension View {
    /// Fills the page, including under a floating tab bar. Lists still need
    /// their own scroll background hidden or they paint system black on top.
    func ormusCanvas() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OrmusPalette.deep.ignoresSafeArea())
    }
}

/// Phone lists use one side margin, the same inset as the search field.
struct PhoneListMargins: ViewModifier {
    let isPhone: Bool

    func body(content: Content) -> some View {
        if isPhone {
            content.contentMargins(.horizontal, 16, for: .scrollContent)
        } else {
            content
        }
    }
}

/// On the phone, the Agents and Terminals bar is the same navy as the page,
/// so it does not sit as a separate rounded slab over black.
struct OrmusPhoneBar: ViewModifier {
    let isPhone: Bool

    func body(content: Content) -> some View {
        if isPhone {
            content
                .toolbarBackground(OrmusPalette.deep, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .containerBackground(OrmusPalette.deep, for: .navigation)
        } else {
            content
        }
    }
}

/// One phone row. Midnight, the same card as Hosts, on the navy page.
struct OrmusLiftedCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(OrmusPalette.midnight)
    }
}

/// The same card while an Agent is blocked and waiting on the user.
struct OrmusNeedsYouCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(OrmusPalette.midnight)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                OrmusPalette.gold.opacity(0.62),
                                OrmusPalette.gold.opacity(0.16),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OrmusPalette.goldBright, lineWidth: 1.5)
            }
            .shadow(color: OrmusPalette.gold.opacity(0.85), radius: 10)
    }
}

/// Agents waiting on the person, in the Console's order. A tap walks to the
/// next one and wraps. A long press returns to the Agents list.
enum NeedsYou {
    static func waiting<ID: Hashable>(in agents: [(id: ID, isBlocked: Bool)]) -> [ID] {
        agents.compactMap { $0.isBlocked ? $0.id : nil }
    }

    /// The agent after `current` in `waiting`. With no current match, the
    /// first waiting agent. Empty means there is nowhere to go.
    static func next<ID: Equatable>(after current: ID?, in waiting: [ID]) -> ID? {
        guard !waiting.isEmpty else { return nil }
        guard let current, let index = waiting.firstIndex(of: current) else {
            return waiting[0]
        }
        return waiting[(index + 1) % waiting.count]
    }
}

/// The clear bubble, as a control. Tap walks. Press and hold opens the list.
struct NeedsYouControl: View {
    let count: Int
    let jump: () -> Void
    let showBoard: () -> Void

    var body: some View {
        NeedsYouOrb(count: count)
            .contentShape(Circle())
            .onTapGesture(perform: jump)
            .onLongPressGesture(minimumDuration: 0.45, perform: showBoard)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(
                "Opens the next waiting agent. Press and hold for the Agents list.")
    }
}

/// Count of Agents waiting on the user. A clear bubble, gold when some are waiting.
/// One waiting agent stays an empty gold bubble. Two or more put the count inside.
struct NeedsYouOrb: View {
    let count: Int

    private var needsYou: Bool { count > 0 }

    var body: some View {
        ZStack {
            SoapBubble(needsYou: needsYou)
            if count > 1 {
                Text(count > 99 ? "99" : "\(count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 0.5)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel(needsYouLabel)
    }

    private var needsYouLabel: String {
        switch count {
        case 0: "No agents need you"
        case 1: "1 agent needs you"
        default: "\(count) agents need you"
        }
    }
}

/// A glass bubble. The center stays clear. The film reflects the navy page
/// and a little gold. While someone is waiting, that reflection turns gold
/// and the bubble glows.
private struct SoapBubble: View {
    let needsYou: Bool

    var body: some View {
        ZStack {
            if needsYou {
                Circle()
                    .fill(OrmusPalette.gold.opacity(0.75))
                    .blur(radius: 6)
                    .scaleEffect(1.08)
            }

            Circle()
                .fill(bodyShade)

            Circle()
                .strokeBorder(film, lineWidth: 5)
                .blur(radius: 1.15)
                .mask(Circle())

            Circle()
                .strokeBorder(rim, lineWidth: 1.15)

            specular
        }
        .frame(width: 36, height: 36)
    }

    /// Clear through the middle, denser only where the glass turns.
    private var bodyShade: RadialGradient {
        let edge = needsYou ? OrmusPalette.gold.opacity(0.22) : OrmusPalette.inkMuted.opacity(0.1)
        return RadialGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.62),
                .init(color: edge, location: 0.9),
                .init(color: Color.white.opacity(needsYou ? 0.16 : 0.08), location: 1),
            ],
            center: UnitPoint(x: 0.42, y: 0.4),
            startRadius: 1,
            endRadius: 18)
    }

    /// Interference in the film. Navy and ink while it rests, gold while it glows.
    private var film: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: needsYou ? goldFilm : restingFilm),
            center: .center,
            startAngle: .degrees(-24),
            endAngle: .degrees(336))
    }

    private var restingFilm: [Color] {
        [
            Color.white.opacity(0.08),
            OrmusPalette.inkMuted.opacity(0.7),
            OrmusPalette.dim.opacity(0.4),
            OrmusPalette.gold.opacity(0.28),
            Color.white.opacity(0.2),
            OrmusPalette.ink.opacity(0.55),
            OrmusPalette.midnight.opacity(0.15),
            OrmusPalette.inkMuted.opacity(0.55),
            Color.white.opacity(0.08),
        ]
    }

    private var goldFilm: [Color] {
        [
            OrmusPalette.goldBright.opacity(0.2),
            OrmusPalette.gold,
            Color.white.opacity(0.45),
            OrmusPalette.goldBright,
            Color(red: 1, green: 0.78, blue: 0.42).opacity(0.75),
            OrmusPalette.gold.opacity(0.5),
            Color.white.opacity(0.3),
            OrmusPalette.gold,
            OrmusPalette.goldBright.opacity(0.2),
        ]
    }

    private var rim: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: needsYou ? goldRim : restingRim),
            center: .center,
            startAngle: .degrees(-40),
            endAngle: .degrees(320))
    }

    private var restingRim: [Color] {
        [
            Color.white.opacity(0.95),
            Color.white.opacity(0.4),
            OrmusPalette.inkMuted.opacity(0.55),
            Color.white.opacity(0.22),
            Color.white.opacity(0.9),
            OrmusPalette.ink.opacity(0.75),
            Color.white.opacity(0.3),
            Color.white.opacity(0.95),
        ]
    }

    private var goldRim: [Color] {
        [
            Color.white,
            OrmusPalette.goldBright,
            OrmusPalette.gold.opacity(0.7),
            Color.white.opacity(0.4),
            OrmusPalette.goldBright,
            Color.white,
            OrmusPalette.gold,
            Color.white,
        ]
    }

    /// The window in the glass, and the small catchlight on the lower rim.
    private var specular: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing))
                .frame(width: 15, height: 5.5)
                .rotationEffect(.degrees(-36))
                .offset(x: -6, y: -10)
                .blur(radius: 0.45)

            Circle()
                .fill(Color.white)
                .frame(width: 2.6, height: 2.6)
                .offset(x: -6.5, y: -7)
                .blur(radius: 0.15)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(needsYou ? 0.95 : 0.8),
                            Color.white.opacity(0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing))
                .frame(width: 14, height: 3.5)
                .rotationEffect(.degrees(24))
                .offset(x: 5, y: 11)
                .blur(radius: 0.4)

            Circle()
                .fill(needsYou ? OrmusPalette.goldBright : Color.white)
                .frame(width: 2.2, height: 2.2)
                .offset(x: 1, y: 9.5)
                .blur(radius: 0.2)
        }
        .mask(Circle())
    }
}

/// A tab icon and title. Gold, with a glow, while that tab is waiting on the user.
struct NeedsYouTabLabel: View {
    let title: String
    let systemImage: String
    let needsYou: Bool
    var outlined = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .environment(\.symbolVariants, outlined ? .none : .fill)
            .foregroundStyle(needsYou ? OrmusPalette.gold : Color.primary)
            .shadow(color: needsYou ? OrmusPalette.gold.opacity(0.9) : .clear, radius: 6)
    }
}
