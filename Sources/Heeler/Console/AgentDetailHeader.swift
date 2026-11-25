import SwiftUI

/// Floating controls over an Agent or terminal. Separate glass pieces float
/// over the terminal: Back at the leading end, any trailing actions in one
/// capsule, and at the far end a fold button that stays put. The room
/// between them is left to the terminal, and it takes touches: the pieces
/// are two overlays, not one bar across the top. Folding hides the trailing
/// actions and leaves Back, so the way out stays one tap away.
///
/// Back is the way out of a detail pushed over the list, on an iPhone or in
/// a compact iPad window, which the edge swipe alone never showed (#396).
/// Beside an iPad's sidebar there is nothing to go back to, so the header
/// keeps only its actions and fold button.
///
/// Trailing actions are plain values rather than views, so a screen can
/// leave out the ones it cannot offer and the capsule goes with the last.
///
/// An Agent that has Chat also shows its Chat and terminal surfaces as a
/// segmented pair, sharing the fold button's capsule in both states, so the
/// surface stays one tap away while the header is folded.
struct AgentDetailHeader {
    static let controlSize: CGFloat = 44
    /// How much of the glass shows, the rest letting output through.
    fileprivate static let glassOpacity: Double = 0.75
    /// Buttons sharing the actions capsule sit closer than standalone ones.
    fileprivate static let capsuleButtonWidth: CGFloat = 36
    fileprivate static let capsuleInset: CGFloat = (controlSize - capsuleButtonWidth) / 2

    /// Where the header's top edge sits. Beside an iPad's sidebar it lines
    /// up with the detail column's bar, level with the sidebar's buttons and
    /// Show Sidebar, even while output starts below the bar; elsewhere it
    /// rides just below the output's top. A bar's buttons fill a control's
    /// height from its top edge, with the bar's remaining height below
    /// them, so the header starts at that edge rather than centering.
    static func top(outputTop: CGFloat, barRow: NavigationBarBand?) -> CGFloat {
        guard let barRow, barRow.bottom - barRow.top >= controlSize else { return outputTop + 4 }
        return barRow.top
    }

    /// Concentric with the capsule, which insets its buttons by the same
    /// amount on every side.
    fileprivate static let selectedSegmentHeight: CGFloat = controlSize - 2 * capsuleInset

    /// The two-bubble glyph draws wider than the terminal's at one size, so
    /// each gets its own to read as a pair beside the fold button.
    fileprivate static func segmentPointSize(_ surface: AgentDetailSurface) -> CGFloat {
        switch surface {
        case .chat: 15
        case .terminal: 17
        }
    }
}

extension View {
    /// Pins Back at the top leading corner and the other controls at the
    /// top trailing corner. Each piece is only as big as its glass, so a
    /// touch on the surface between them reaches the surface.
    func agentDetailHeader(
        palette: TerminalThemePalette,
        isExpanded: Binding<Bool>,
        onBack: (() -> Void)?,
        actions: [AgentDetailHeaderAction] = [],
        surfaceSwitch: AgentDetailSurfaceSwitch? = nil,
        top: CGFloat,
        colorScheme: ColorScheme? = nil
    ) -> some View {
        modifier(
            AgentDetailHeaderModifier(
                palette: palette,
                isExpanded: isExpanded,
                onBack: onBack,
                actions: actions,
                surfaceSwitch: surfaceSwitch,
                top: top,
                colorScheme: colorScheme))
    }
}

private struct AgentDetailHeaderModifier: ViewModifier {
    let palette: TerminalThemePalette
    @Binding var isExpanded: Bool
    let onBack: (() -> Void)?
    let actions: [AgentDetailHeaderAction]
    let surfaceSwitch: AgentDetailSurfaceSwitch?
    let top: CGFloat
    let colorScheme: ColorScheme?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                AgentDetailHeaderLeading(palette: palette, onBack: onBack)
                    .modifier(HeaderColorScheme(scheme: colorScheme))
                    .padding(.top, top)
                    .padding(.leading, 12)
                    .fixedSize()
            }
            .overlay(alignment: .topTrailing) {
                AgentDetailHeaderTrailing(
                    palette: palette,
                    isExpanded: $isExpanded,
                    actions: actions,
                    surfaceSwitch: surfaceSwitch)
                    .modifier(HeaderColorScheme(scheme: colorScheme))
                    .padding(.top, top)
                    .padding(.trailing, 12)
                    .fixedSize()
            }
    }
}

/// Back, only as big as its glass.
private struct AgentDetailHeaderLeading: View {
    let palette: TerminalThemePalette
    let onBack: (() -> Void)?

    var body: some View {
        if let onBack {
            AgentDetailHeaderButton("Back", systemImage: "chevron.left", action: onBack)
                .headerGlass(in: .circle)
                .foregroundStyle(palette.foreground)
        }
    }
}

/// The trailing cluster: expanded actions, then the surface switch and fold.
private struct AgentDetailHeaderTrailing: View {
    let palette: TerminalThemePalette
    @Binding var isExpanded: Bool
    let actions: [AgentDetailHeaderAction]
    let surfaceSwitch: AgentDetailSurfaceSwitch?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 8) {
            if isExpanded, !actions.isEmpty {
                HStack(spacing: 0) {
                    ForEach(actions) { @Sendable action in
                        MainActorContent {
                            AgentDetailHeaderButton(
                                action.title, systemImage: action.systemImage,
                                width: AgentDetailHeader.capsuleButtonWidth, action: action.perform)
                        }
                    }
                }
                .padding(.horizontal, AgentDetailHeader.capsuleInset)
                .fixedSize()
                .headerGlass(in: .capsule)
                .transition(
                    .scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
            if let surfaceSwitch {
                HStack(spacing: 0) {
                    ForEach(AgentDetailSurfaceSwitch.order, id: \.self) { @Sendable surface in
                        MainActorContent { surfaceButton(surface, in: surfaceSwitch) }
                    }
                    Rectangle()
                        .fill(palette.foreground.opacity(0.25))
                        .frame(width: 1 / max(displayScale, 1), height: 20)
                        .padding(.horizontal, 2)
                    foldButton(width: AgentDetailHeader.capsuleButtonWidth)
                }
                .padding(.horizontal, AgentDetailHeader.capsuleInset)
                .fixedSize()
                .headerGlass(in: .capsule)
            } else {
                foldButton(width: AgentDetailHeader.controlSize)
                    .headerGlass(in: .circle)
            }
        }
        .foregroundStyle(palette.foreground)
    }

    /// The current surface reads as selected: filled, its glyph knocked out.
    private func surfaceButton(
        _ surface: AgentDetailSurface, in control: AgentDetailSurfaceSwitch
    ) -> some View {
        let isSelected = surface == control.current
        return Button {
            guard !isSelected else { return }
            control.select(surface)
        } label: {
            Image(systemName: surface.showSystemImage)
                .font(.system(size: AgentDetailHeader.segmentPointSize(surface), weight: .semibold))
                .foregroundStyle(isSelected ? palette.background : palette.foreground)
                .frame(
                    width: AgentDetailHeader.capsuleButtonWidth + 4,
                    height: AgentDetailHeader.selectedSegmentHeight)
                .background {
                    if isSelected {
                        Capsule().fill(palette.foreground)
                    }
                }
                .frame(height: AgentDetailHeader.controlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(surface.segmentTitle)
        .accessibilityHint(isSelected ? "" : surface.showAccessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Stays at the far end in both states.
    private func foldButton(width: CGFloat) -> some View {
        AgentDetailHeaderButton(
            isExpanded ? "Hide Header" : "Show Header",
            // A window's top bar, which is what this shows and hides: put
            // away while it is out, filled in while it is folded.
            systemImage: isExpanded
                ? "menubar.arrow.up.rectangle" : "inset.filled.topthird.rectangle",
            width: width
        ) {
            withAnimation(reduceMotion ? nil : .snappy) {
                isExpanded.toggle()
            }
        }
    }
}

/// The theme's chrome scheme, only on the glass. Absent leaves the piece on
/// the surrounding scheme, which Chat does.
private struct HeaderColorScheme: ViewModifier {
    let scheme: ColorScheme?

    func body(content: Content) -> some View {
        if let scheme {
            content.environment(\.colorScheme, scheme)
        } else {
            content
        }
    }
}

/// The surfaces an Agent detail can show, and how to swap them, for
/// `AgentDetailHeader`'s segmented pair. Main-actor isolated, and so
/// Sendable, for the same reason as `AgentDetailHeaderAction`.
@MainActor
struct AgentDetailSurfaceSwitch {
    static let order: [AgentDetailSurface] = [.chat, .terminal]

    let current: AgentDetailSurface
    let select: (AgentDetailSurface) -> Void
}

/// One of `AgentDetailHeader`'s trailing buttons. Isolated to the main
/// actor, which makes it Sendable: the header's `ForEach` content is
/// `@Sendable` and hands each action to `MainActorContent` (#471).
@MainActor
struct AgentDetailHeaderAction: Identifiable {
    let title: LocalizedStringKey
    let systemImage: String
    let perform: () -> Void

    nonisolated var id: String { systemImage }
}

/// An icon button inside `AgentDetailHeader`. It has no surface of its own:
/// the header puts Back and the fold button on glass circles, and its
/// trailing actions together on one glass capsule.
struct AgentDetailHeaderButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let width: CGFloat
    let action: () -> Void

    init(
        _ title: LocalizedStringKey, systemImage: String,
        width: CGFloat = AgentDetailHeader.controlSize, action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: width, height: AgentDetailHeader.controlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension View {
    /// Liquid Glass where the system has it, a blur before that. The glass
    /// sits behind the icons at part strength, so the output under the
    /// buttons still shows through while the icons stay solid.
    fileprivate func headerGlass(in shape: some Shape) -> some View {
        background {
            Group {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .opacity(AgentDetailHeader.glassOpacity)
        }
        .contentShape(shape)
    }
}
