import Darwin
import Foundation
import Testing

@testable import Mercurio

@Suite("Website preview")
struct DevPreviewTests {
    @Test func listeningPortsPreferLoopbackAndDropPrivileged() {
        let text = """
            #ss
            LISTEN 0 5 127.0.0.1:8000 0.0.0.0:* users:(("python3",pid=1,fd=3))
            LISTEN 0 5 0.0.0.0:8000 0.0.0.0:* users:(("python3",pid=1,fd=4))
            LISTEN 0 5 *:22 0.0.0.0:* users:(("sshd",pid=2,fd=3))
            LISTEN 0 5 [::1]:5173 [::]:* users:(("node",pid=3,fd=5))
            LISTEN 0 5 [::ffff:127.0.0.1]:9000 [::]:*
            """
        let targets = DevPreview.parseListening(text)
        #expect(targets.map(\.port) == [5173, 8000, 9000])
        #expect(targets[0].host == "::1")
        #expect(targets[0].process == "node")
        #expect(targets[1].host == "127.0.0.1")
        #expect(targets[1].process == "python3")
        #expect(targets[2].host == "127.0.0.1")
    }

    @Test func lsofLinesKeepTheProcessName() {
        let text = """
            #lsof
            python3 1 user 3u IPv4 0x1 0t0 TCP 127.0.0.1:8000 (LISTEN)
            sshd 2 user 3u IPv4 0x2 0t0 TCP *:22 (LISTEN)
            node 3 user 5u IPv6 0x3 0t0 TCP [::1]:5173 (LISTEN)
            """
        let targets = DevPreview.parseListening(text)
        #expect(targets.map(\.port) == [5173, 8000])
        #expect(targets[0].host == "::1")
        #expect(targets[0].process == "node")
        #expect(targets[1].process == "python3")
    }

    @Test func printedUrlsComeFirstAndKeepTheirPath() {
        let printed = DevPreview.printed(
            in: "see http://localhost:3000/ then http://127.0.0.1:5173/app.")
        #expect(printed.map(\.port) == [5173, 3000])
        #expect(printed[0].path == "/app")
        #expect(printed[1].path == "/")
        let listening = [
            DevPreview.Target(host: "127.0.0.1", port: 5173, path: "/", process: "node"),
            DevPreview.Target(host: "127.0.0.1", port: 8080, path: "/", process: "python3"),
        ]
        let merged = DevPreview.targets(printed: printed, listening: listening)
        #expect(merged.map(\.port) == [5173, 3000, 8080])
        #expect(merged[0].process == "node")
        #expect(merged[0].path == "/app")
        #expect(merged[2].process == "python3")
    }

    @Test func aLocalLinkBecomesAPreviewTarget() {
        let target = DevPreview.target(from: URL(string: "http://localhost:3000/")!)
        #expect(target?.host == "127.0.0.1")
        #expect(target?.port == 3000)
        #expect(target?.path == "/")
        #expect(target?.announced == true)
        #expect(DevPreview.target(from: URL(string: "https://example.com/")!) == nil)
    }

    @Test func previewKeepsOnlyLinksFromTheSession() {
        let seen = [
            DevPreview.Target(host: "127.0.0.1", port: 3100, path: "/", process: "node"),
            DevPreview.Target(host: "127.0.0.1", port: 3000, path: "/", process: "node", announced: true),
        ]
        #expect(DevPreview.websites(seen).map(\.port) == [3000])
        let links = DevPreview.localLinks(
            in: "Open Preview and tap localhost:3000. Also https://example.com and 127.0.0.1:3100")
        #expect(links.map(\.port) == [3100, 3000])
    }

    @Test func aMissingToolAndAFailedReadStayDistinct() {
        #expect(DevPreview.readListening(stdout: "", stderr: "", exitCode: 5, recentOutput: "") == .noTool)
        #expect(
            DevPreview.readListening(
                stdout: "", stderr: "permission denied\n", exitCode: 1, recentOutput: "")
                == .failed("permission denied"))
    }

    @Test func spliceCopiesBytesBothWaysUntilEachSideCloses() {
        let left = socketPair()
        let right = socketPair()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            SocketBridge.splice(left[1], right[0])
            finished.signal()
        }
        let hello = Data("hello".utf8)
        hello.withUnsafeBytes { raw in
            _ = Darwin.write(left[0], raw.baseAddress!, raw.count)
        }
        Darwin.shutdown(left[0], SHUT_WR)
        var buffer = [UInt8](repeating: 0, count: 16)
        let readCount = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(right[1], raw.baseAddress!, raw.count)
        }
        #expect(readCount == hello.count)
        #expect(Data(buffer.prefix(readCount)) == hello)
        Darwin.shutdown(right[1], SHUT_WR)
        #expect(finished.wait(timeout: .now() + 2) == .success)
        Darwin.close(left[0])
        Darwin.close(left[1])
        Darwin.close(right[0])
        Darwin.close(right[1])
    }

    @Test func spliceWaitsWhenTheTunnelIsNotReadyYet() {
        let browser = socketPair()
        let tunnel = socketPair()
        let flags = fcntl(tunnel[0], F_GETFL)
        _ = fcntl(tunnel[0], F_SETFL, flags | O_NONBLOCK)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            SocketBridge.splice(browser[1], tunnel[0])
            finished.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)
        let hello = Data("hello".utf8)
        hello.withUnsafeBytes { raw in
            _ = Darwin.write(browser[0], raw.baseAddress!, raw.count)
        }
        Darwin.shutdown(browser[0], SHUT_WR)
        var buffer = [UInt8](repeating: 0, count: 16)
        let readCount = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(tunnel[1], raw.baseAddress!, raw.count)
        }
        #expect(readCount == hello.count)
        #expect(Data(buffer.prefix(readCount)) == hello)
        Darwin.shutdown(tunnel[1], SHUT_WR)
        #expect(finished.wait(timeout: .now() + 2) == .success)
        Darwin.close(browser[0])
        Darwin.close(browser[1])
        Darwin.close(tunnel[0])
        Darwin.close(tunnel[1])
    }

    private func socketPair() -> [Int32] {
        var descriptors: [Int32] = [-1, -1]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        return descriptors
    }
}
