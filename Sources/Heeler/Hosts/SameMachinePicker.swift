import SwiftUI

/// Picks the Host that keeps the account, session, and sign-in. The caller
/// checks the SSH host key before removing the Host that was folded in.
struct SameMachinePicker: View {
    let source: Host
    let others: [Host]
    let isBusy: Bool
    let onSelect: (Host) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(
                    "Fold \(source.displayName) into a Host that is the same Mac. "
                        + "The SSH host key has to match. A different key keeps them separate."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Section("Fold into") {
                if others.isEmpty {
                    Text("No other Host")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(others) { @Sendable host in
                        MainActorContent {
                            Button {
                                onSelect(host)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.displayName)
                                    Text(host.connectionSummary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
        .navigationTitle("Same Machine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isBusy)
            }
        }
        .overlay {
            if isBusy {
                ProgressView("Checking host key")
            }
        }
    }
}
