import Foundation
import HeelerSSH

/// Reads the SSH host key a hop presents, without signing in. Add uses it
/// to see whether a peer is a machine a saved Host already trusts.
protocol HostKeyReading: Sendable {
    func fingerprint(
        address: String, port: Int, overlay: OverlayRoute?
    ) async throws -> HostKeyFingerprint
}

/// One handshake over the device's own network, or over an Overlay Network
/// when the hop is on one. The connection is closed before the key is returned.
struct SSHHostKeyReader: HostKeyReading {
    var timeout: Duration = .seconds(20)

    func fingerprint(
        address: String, port: Int, overlay: OverlayRoute?
    ) async throws -> HostKeyFingerprint {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard let port = UInt16(exactly: port), !trimmed.isEmpty else {
            throw TransportError.sshUnreachable(detail: "Invalid SSH endpoint.")
        }
        let endpoint = SSHEndpoint(host: trimmed, port: port)
        let connection: SSHConnection
        if let overlay {
            connection = try await SSHConnection.connect(
                to: endpoint,
                timeout: timeout,
                transportLabel: "overlay \(overlay.networkName)"
            ) { remaining in
                let dialed = try await overlay.dial(endpoint.host, endpoint.port, remaining)
                return try SSHExternalStream(descriptor: dialed.descriptor, release: dialed.release)
            }
        } else {
            connection = try await SSHConnection.connect(to: endpoint, timeout: timeout)
        }
        let fingerprint = HostKeyFingerprint(publicKeyBlob: connection.hostKey.key)
        try? await connection.close(timeout: .seconds(2))
        return fingerprint
    }
}
