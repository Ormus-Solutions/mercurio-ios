import Darwin
import Foundation

/// One direct-tcpip channel, as a local socket the caller reads and writes.
///
/// The SSH session behind it can do nothing else until `close()`. A website
/// preview opens one of these per browser connection, on its own session,
/// and copies bytes between this descriptor and the accepted socket.
public final class SSHTCPTunnel: @unchecked Sendable {
    /// The local end of the tunnel. The caller owns it until `close()`.
    public let fileDescriptor: Int32

    private let transport: DirectTCPIPByteTransport
    private let connection: SSHConnection
    private let lock = NSLock()
    private var closed = false

    init(
        fileDescriptor: Int32,
        transport: DirectTCPIPByteTransport,
        connection: SSHConnection
    ) {
        self.fileDescriptor = fileDescriptor
        self.transport = transport
        self.connection = connection
    }

    /// Shuts the local socket, waits for the SSH pump to finish, then closes
    /// the session. Safe to call more than once.
    public func close() async {
        let shouldClose = lock.withLock { () -> Bool in
            if closed { return false }
            closed = true
            return true
        }
        guard shouldClose else { return }
        Darwin.shutdown(fileDescriptor, SHUT_RDWR)
        Darwin.close(fileDescriptor)
        // The pump owns the session until it sees this socket close. Closing
        // the session first is refused while that pump is still running.
        try? await transport.close(timeout: .seconds(2))
        try? await connection.close(timeout: .seconds(2))
    }
}
