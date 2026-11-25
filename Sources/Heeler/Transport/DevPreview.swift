import Foundation

/// A website a computer is serving, and how the phone reaches it.
///
/// The list comes from the same read as Android Mercurio: ports listening on
/// the computer, plus local URLs the agent printed. The page itself is a
/// separate SSH connection per browser socket, because one direct-tcpip
/// tunnel owns its session until it closes.
enum DevPreview {
    /// `ss` where the computer has it, otherwise `lsof`. Exit 5 means neither.
    static let noToolExit = 5

    static let listenCommand =
        "sh -c 'command -v ss >/dev/null 2>&1 || command -v lsof >/dev/null 2>&1 || exit 5; "
        + "if command -v ss >/dev/null 2>&1; then echo \"#ss\"; ss -ltnpH 2>/dev/null; "
        + "else echo \"#lsof\"; lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null; fi | head -c 65536'"

    struct Target: Equatable, Identifiable, Sendable {
        var host: String
        var port: Int
        var path: String
        var process: String?
        /// True when an agent printed this URL. Those stay even if the
        /// process name is not one we recognize as a dev server.
        var announced: Bool = false

        var id: String { "\(host):\(port)\(path)" }

        var title: String {
            if let process, !process.isEmpty { return process }
            return "localhost:\(port)"
        }

        var address: String { "\(host):\(port)\(path)" }
    }

    enum Listing: Equatable, Sendable {
        case ports([Target])
        case noTool
        case failed(String)
    }

    static func readListening(
        stdout: String,
        stderr: String,
        exitCode: Int,
        recentOutput: String
    ) -> Listing {
        if exitCode == noToolExit { return .noTool }
        if exitCode != 0 {
            let line = stderr.split(whereSeparator: \.isNewline).first {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
            let message = line.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "exit \(exitCode)"
            return .failed(message)
        }
        let listening = parseListening(stdout)
        let merged = targets(printed: printed(in: recentOutput), listening: listening)
        return .ports(websites(merged))
    }

    /// Only addresses that showed up in the session. A process that is
    /// merely listening, such as another node server, is not a link.
    static func websites(_ targets: [Target]) -> [Target] {
        targets.filter(\.announced)
    }

    /// Local links written in the session, newest first, one row per port.
    /// `localhost:3000` counts, not only `http://localhost:3000`.
    static func localLinks(in text: String) -> [Target] {
        let pattern =
            #"(?i)(?<![A-Za-z0-9])(?:https?://)?(?:localhost|127\.0\.0\.1|0\.0\.0\.0):([0-9]{2,5})([^\s<>"'`()\[\]{}]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var seen = Set<Int>()
        var found: [Target] = []
        for match in matches.reversed() {
            guard let portSpan = Range(match.range(at: 1), in: text),
                let port = Int(text[portSpan]),
                (1024...65535).contains(port),
                seen.insert(port).inserted
            else { continue }
            var path = "/"
            if let pathSpan = Range(match.range(at: 2), in: text) {
                var raw = String(text[pathSpan]).trimmingCharacters(
                    in: CharacterSet(charactersIn: ".,;:!?"))
                if raw == "/" || raw.isEmpty {
                    path = "/"
                } else if raw.hasPrefix("/") || raw.hasPrefix("?") || raw.hasPrefix("#") {
                    if raw.hasPrefix("?") || raw.hasPrefix("#") { raw = "/" + raw }
                    path = raw
                }
            }
            found.append(
                Target(host: loopback, port: port, path: path, process: nil, announced: true))
        }
        return found
    }

    /// A local website address, or nil when the URL is some other site.
    /// The tunnel always dials 127.0.0.1 on the computer, which is where
    /// `localhost` listens.
    static func target(from url: URL) -> Target? {
        guard let host = url.host?.lowercased(), localHosts.contains(host) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        guard (1024...65535).contains(port) else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        return Target(
            host: loopback, port: port, path: path + query, process: nil, announced: true)
    }

    static func message(for error: Error) -> String {
        if let transport = error as? TransportError {
            return transport.presentation.explanation
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "The computer did not answer." : description
    }

    static func parseListening(_ text: String) -> [Target] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let body = lines.dropFirst()
        let parsed: [Target]
        switch lines.first?.trimmingCharacters(in: .whitespaces) {
        case "#ss":
            parsed = body.compactMap(parseSs)
        case "#lsof":
            parsed = body.compactMap(parseLsof)
        default:
            parsed = []
        }
        let usable = parsed.filter { $0.port >= 1024 }
        let grouped = Dictionary(grouping: usable, by: \.port)
        return grouped.keys.sorted().compactMap { port in
            let same = grouped[port] ?? []
            return same.first { $0.host == loopback } ?? same.first
        }
    }

    static func printed(in text: String) -> [Target] {
        var seen = Set<Int>()
        var found: [Target] = []
        for url in webAddresses(in: text).reversed() {
            guard let target = printedTarget(url), seen.insert(target.port).inserted else { continue }
            found.append(target)
        }
        return found
    }

    static func targets(printed: [Target], listening: [Target]) -> [Target] {
        let byPort = Dictionary(listening.map { ($0.port, $0) }, uniquingKeysWith: { first, _ in first })
        let withProcess = printed.map { item in
            Target(
                host: item.host,
                port: item.port,
                path: item.path,
                process: byPort[item.port]?.process ?? item.process,
                announced: true)
        }
        let rest = listening.filter { listen in !printed.contains { $0.port == listen.port } }
        return withProcess + rest
    }

    private static let loopback = "127.0.0.1"
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0"]

    private static func parseSs(_ line: String) -> Target? {
        let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard columns.count >= 4 else { return nil }
        return target(address: columns[3], process: ssProcess(line))
    }

    private static func ssProcess(_ line: String) -> String? {
        let pattern = #"users:\(\("([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range])
    }

    private static func parseLsof(_ line: String) -> Target? {
        let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard columns.count >= 10, columns.last == "(LISTEN)" else { return nil }
        return target(address: columns[columns.count - 2], process: columns[0])
    }

    private static func target(address: String, process: String?) -> Target? {
        guard let port = Int(address.split(separator: ":").last.map(String.init) ?? ""),
            (1...65535).contains(port)
        else { return nil }
        var bound = address
        if let colon = bound.range(of: ":", options: .backwards) {
            bound = String(bound[..<colon.lowerBound])
        }
        if bound.hasPrefix("["), bound.hasSuffix("]") {
            bound = String(bound.dropFirst().dropLast())
        }
        bound = bound.split(separator: "%").first.map(String.init) ?? bound
        if bound.hasPrefix("::ffff:") { bound.removeFirst("::ffff:".count) }
        guard let host = reach(bound) else { return nil }
        return Target(host: host, port: port, path: "/", process: process)
    }

    private static func reach(_ address: String) -> String? {
        switch address {
        case "*", "0.0.0.0", "::", "localhost":
            return loopback
        case "::1":
            return "::1"
        default:
            return address.isEmpty ? nil : address
        }
    }

    private static func webAddresses(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'`()\[\]{}]+"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let span = Range(match.range, in: text) else { return nil }
            return String(text[span]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        }
    }

    private static func printedTarget(_ url: String) -> Target? {
        guard let scheme = url.range(of: "://") else { return nil }
        let rest = url[scheme.upperBound...]
        let authority = rest.prefix { $0 != "/" }
        let pathStart = rest[authority.endIndex...]
        let path = pathStart.isEmpty ? "/" : String(pathStart)
        let host = authority.prefix { $0 != ":" }
        guard localHosts.contains(String(host)) else { return nil }
        let portText = authority[host.endIndex...].dropFirst()
        guard let port = Int(portText), (1...65535).contains(port) else { return nil }
        return Target(host: loopback, port: port, path: path, process: nil, announced: true)
    }
}
