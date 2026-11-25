import Foundation

/// Why two Hosts were not treated as one machine. A fold only proceeds when
/// both have presented the same SSH host key and sign in as the same account.
/// Routes share the Host's account and key, so a mismatch has to stay two Hosts.
enum HostMergeRefusal: Equatable, Error, Sendable {
    case sameHost
    case missingHostKey
    case differentHostKey
    case differentAccount

    var message: String {
        switch self {
        case .sameHost:
            "Choose a different Host."
        case .missingHostKey:
            "Connect both Hosts once so their SSH host keys can be compared, then try Same Machine again."
        case .differentHostKey:
            "These Hosts presented different SSH host keys, so they stay separate."
        case .differentAccount:
            "These Hosts sign in as different accounts. A route uses the Host's account, so they stay separate."
        }
    }
}

/// Folding two catalog Hosts that are one machine, and attaching one more
/// route when a peer presents a key a saved Host already trusts.
enum HostMerge {
    /// True when the two sets share an SSH host-key digest. An empty set
    /// is not a match: a Host that has never connected has nothing to compare.
    static func sharesHostKey(
        _ lhs: [HostKeyFingerprint], _ rhs: [HostKeyFingerprint]
    ) -> Bool {
        let digests = Set(lhs.map(\.digest))
        return rhs.contains { digests.contains($0.digest) }
    }

    /// Saved Hosts whose trusted host key is `presented`.
    static func hosts(
        matching presented: HostKeyFingerprint,
        among hosts: [Host],
        keysByHost: [Host.ID: [HostKeyFingerprint]]
    ) -> [Host] {
        hosts.filter { sharesHostKey(keysByHost[$0.id] ?? [], [presented]) }
    }

    /// `host` plus a route for this hop, or `host` unchanged when that hop
    /// is already one of its routes.
    static func appending(
        address: String,
        port: Int = 22,
        overlayNetworkID: UUID?,
        to host: Host
    ) -> (host: Host, added: Bool) {
        let route = HostRoute(
            address: address.trimmingCharacters(in: .whitespaces),
            port: port,
            overlayNetworkID: overlayNetworkID)
        guard !host.routes.contains(where: { $0.reachesSamePlace(as: route) }) else {
            return (host, false)
        }
        var updated = host
        updated.routes.append(route)
        return (updated, true)
    }

    /// `target` with `source`'s routes added, keeping `target`'s account,
    /// session, and sign-in. Refuses a different host key or account.
    static func merged(
        _ source: Host,
        into target: Host,
        sourceKeys: [HostKeyFingerprint],
        targetKeys: [HostKeyFingerprint]
    ) -> Result<Host, HostMergeRefusal> {
        guard source.id != target.id else { return .failure(.sameHost) }
        guard !sourceKeys.isEmpty, !targetKeys.isEmpty else {
            return .failure(.missingHostKey)
        }
        guard sharesHostKey(sourceKeys, targetKeys) else {
            return .failure(.differentHostKey)
        }
        let sourceAccount = source.username.trimmingCharacters(in: .whitespaces)
        let targetAccount = target.username.trimmingCharacters(in: .whitespaces)
        guard sourceAccount.caseInsensitiveCompare(targetAccount) == .orderedSame else {
            return .failure(.differentAccount)
        }
        var merged = target
        for route in source.routes where !merged.routes.contains(where: { $0.reachesSamePlace(as: route) }) {
            merged.routes.append(route.relocated())
        }
        return .success(merged)
    }
}
