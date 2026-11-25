import Darwin
import Foundation
import HeelerSSH
import Synchronization

/// Opens a fresh SSH tunnel for one browser connection.
final class DevPreviewTunnelOpener: @unchecked Sendable {
    private let open: @MainActor (String, Int) async throws -> SSHTCPTunnel

    init(open: @escaping @MainActor (String, Int) async throws -> SSHTCPTunnel) {
        self.open = open
    }

    func call(host: String, port: Int) async throws -> SSHTCPTunnel {
        try await open(host, port)
    }
}

/// A loopback port on the phone. Each accepted connection is copied, byte for
/// byte, to `host:port` on the computer through its own SSH tunnel.
final class DevPreviewForwarder: @unchecked Sendable {
    static let maxConnections = 6

    let localPort: UInt16

    private let listenFD: Int32
    private let host: String
    private let port: Int
    private let opener: DevPreviewTunnelOpener
    private let slots = PreviewSlots(limit: DevPreviewForwarder.maxConnections)
    private let lock = NSLock()
    private var stopped = false
    private var clients: [Int32] = []

    private init(
        listenFD: Int32,
        localPort: UInt16,
        host: String,
        port: Int,
        opener: DevPreviewTunnelOpener
    ) {
        self.listenFD = listenFD
        self.localPort = localPort
        self.host = host
        self.port = port
        self.opener = opener
    }

    static func start(
        host: String,
        port: Int,
        opener: DevPreviewTunnelOpener
    ) throws -> DevPreviewForwarder {
        let (fd, localPort) = try bindLoopback()
        let forwarder = DevPreviewForwarder(
            listenFD: fd, localPort: localPort, host: host, port: port, opener: opener)
        forwarder.acceptLoop()
        return forwarder
    }

    func stop() {
        let clients: [Int32]? = lock.withLock {
            if stopped { return nil }
            stopped = true
            return self.clients
        }
        guard let clients else { return }
        Darwin.shutdown(listenFD, SHUT_RDWR)
        Darwin.close(listenFD)
        for client in clients {
            Darwin.shutdown(client, SHUT_RDWR)
        }
        slots.stop()
    }

    private func acceptLoop() {
        let fd = listenFD
        Thread.detachNewThread { [weak self] in
            while let self, !self.isStopped() {
                var address = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let client = withUnsafeMutablePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.accept(fd, $0, &length)
                    }
                }
                if client < 0 { break }
                Self.ignorePipeSignal(client)
                Task { await self.serve(client) }
            }
        }
    }

    private func serve(_ client: Int32) async {
        guard await slots.acquire() else {
            Darwin.close(client)
            return
        }
        guard !isStopped() else {
            Darwin.close(client)
            slots.release()
            return
        }
        track(client)
        let tunnel: SSHTCPTunnel
        do {
            tunnel = try await opener.call(host: host, port: port)
        } catch {
            untrack(client)
            Darwin.close(client)
            slots.release()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                SocketBridge.splice(client, tunnel.fileDescriptor)
                continuation.resume()
            }
        }
        untrack(client)
        Darwin.close(client)
        await tunnel.close()
        slots.release()
    }

    private func isStopped() -> Bool {
        lock.withLock { stopped }
    }

    private func track(_ client: Int32) {
        lock.withLock { clients.append(client) }
    }

    private func untrack(_ client: Int32) {
        lock.withLock { clients.removeAll { $0 == client } }
    }

    private static func bindLoopback() throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DevPreviewForwardError.unavailable }
        ignorePipeSignal(fd)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw DevPreviewForwardError.unavailable
        }
        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            Darwin.close(fd)
            throw DevPreviewForwardError.unavailable
        }
        return (fd, UInt16(bigEndian: boundAddress.sin_port))
    }

    private static func ignorePipeSignal(_ fd: Int32) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    }
}

enum DevPreviewForwardError: Error {
    case unavailable
}

enum SocketBridge {
    /// Copies bytes both ways until each side closes. The SSH tunnel end is
    /// non-blocking, so a read that is not ready yet must wait, not end the
    /// page. Does not close either descriptor.
    static func splice(_ left: Int32, _ right: Int32) {
        var toRight = Data()
        var toLeft = Data()
        var leftDone = false
        var rightDone = false
        var leftWriteClosed = false
        var rightWriteClosed = false
        while !leftDone || !rightDone || !toRight.isEmpty || !toLeft.isEmpty {
            var polls: [pollfd] = []
            var leftIndex: Int?
            var rightIndex: Int?
            if !leftDone || !toLeft.isEmpty {
                var events: Int16 = 0
                if !leftDone, toRight.count < 65_536 { events |= Int16(POLLIN) }
                if !toLeft.isEmpty { events |= Int16(POLLOUT) }
                if events != 0 {
                    leftIndex = polls.count
                    polls.append(pollfd(fd: left, events: events, revents: 0))
                }
            }
            if !rightDone || !toRight.isEmpty {
                var events: Int16 = 0
                if !rightDone, toLeft.count < 65_536 { events |= Int16(POLLIN) }
                if !toRight.isEmpty { events |= Int16(POLLOUT) }
                if events != 0 {
                    rightIndex = polls.count
                    polls.append(pollfd(fd: right, events: events, revents: 0))
                }
            }
            if polls.isEmpty { return }
            let ready = polls.withUnsafeMutableBufferPointer { buffer -> Int32 in
                guard let base = buffer.baseAddress else { return -1 }
                return poll(base, nfds_t(buffer.count), 1_000)
            }
            if ready < 0 {
                if errno == EINTR { continue }
                return
            }
            if ready == 0 { continue }
            if let leftIndex {
                let events = polls[leftIndex].revents
                if events & Int16(POLLIN | POLLHUP) != 0 {
                    switch readChunk(left) {
                    case .bytes(let data): toRight.append(data)
                    case .end: leftDone = true
                    case .again: break
                    }
                }
                if events & Int16(POLLOUT) != 0, !toLeft.isEmpty {
                    if let sent = writeChunk(toLeft, to: left) {
                        toLeft.removeFirst(sent)
                    }
                }
                if events & Int16(POLLERR | POLLNVAL) != 0 { return }
            }
            if let rightIndex {
                let events = polls[rightIndex].revents
                if events & Int16(POLLIN | POLLHUP) != 0 {
                    switch readChunk(right) {
                    case .bytes(let data): toLeft.append(data)
                    case .end: rightDone = true
                    case .again: break
                    }
                }
                if events & Int16(POLLOUT) != 0, !toRight.isEmpty {
                    if let sent = writeChunk(toRight, to: right) {
                        toRight.removeFirst(sent)
                    }
                }
                if events & Int16(POLLERR | POLLNVAL) != 0 { return }
            }
            if leftDone, toRight.isEmpty, !rightWriteClosed {
                Darwin.shutdown(right, SHUT_WR)
                rightWriteClosed = true
            }
            if rightDone, toLeft.isEmpty, !leftWriteClosed {
                Darwin.shutdown(left, SHUT_WR)
                leftWriteClosed = true
            }
        }
    }

    private enum Chunk {
        case bytes(Data)
        case end
        case again
    }

    private static func readChunk(_ fd: Int32) -> Chunk {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let count = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.read(fd, base, raw.count)
        }
        if count > 0 { return .bytes(Data(buffer.prefix(count))) }
        if count == 0 { return .end }
        if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return .again }
        return .end
    }

    /// Nil means this write has to wait. Zero is not returned.
    private static func writeChunk(_ data: Data, to fd: Int32) -> Int? {
        let count = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.write(fd, base, raw.count)
        }
        if count > 0 { return count }
        return nil
    }
}

private final class PreviewSlots: Sendable {
    private struct State: Sendable {
        var used = 0
        var stopped = false
    }

    private let limit: Int
    private let state: Mutex<State>

    init(limit: Int) {
        self.limit = limit
        state = Mutex(State())
    }

    func acquire() async -> Bool {
        while true {
            let decision = state.withLock { state -> Int in
                if state.stopped { return -1 }
                if state.used < limit {
                    state.used += 1
                    return 1
                }
                return 0
            }
            if decision < 0 { return false }
            if decision > 0 { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    func release() {
        state.withLock { state in
            state.used = max(0, state.used - 1)
        }
    }

    func stop() {
        state.withLock { state in
            state.stopped = true
        }
    }
}
