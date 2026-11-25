import SwiftUI

/// Status read by shape as well as colour. Blocked is a filled gold dot,
/// working an ink-muted ring, idle a dim hollow ring, done a filled ink dot.
struct AgentStatusMark: View {
    let status: AgentStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.markIsFilled ? Color(status.markUIColor) : .clear)
            .overlay {
                if !status.markIsFilled {
                    Circle().strokeBorder(Color(status.markUIColor), lineWidth: 1.5)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
