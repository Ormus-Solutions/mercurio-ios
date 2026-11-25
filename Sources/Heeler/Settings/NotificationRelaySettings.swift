import Foundation
import Observation

/// The app-side custom Push Relay base URL (#76, ADR 0008).
///
/// Empty means push is off. Mercurio does not write Heeler's relay, and a
/// stored Mercurio or retired production URL is cleared. Only an http(s) base
/// URL that is not one of those endpoints is accepted — a malformed entry
/// yields no `URL`, so a typo never lands on a Host.
@MainActor
@Observable
final class NotificationRelaySettings {
    private static let defaultsKey = "notification-relay-url"

    /// The raw text the user typed, persisted verbatim so the field round-trips
    /// (including an in-progress typo the user is still editing).
    var rawValue: String {
        didSet {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: Self.defaultsKey)
            } else {
                defaults.set(trimmed, forKey: Self.defaultsKey)
            }
        }
    }

    @ObservationIgnored private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.defaultsKey) ?? ""
        if NotificationRelayEndpoint.isLegacyProductionBaseURL(stored) {
            rawValue = ""
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            rawValue = stored
        }
    }

    /// A validated custom base URL, or nil when the field is empty, malformed,
    /// or still pointing at Heeler's relay. Nil means registration writes no
    /// relay URL.
    var relayURL: URL? {
        if NotificationRelayEndpoint.isLegacyProductionBaseURL(rawValue) { return nil }
        return Self.validate(rawValue)
    }

    /// Whether the current text is non-empty but not a usable relay URL, so the
    /// settings screen can flag a typo instead of silently ignoring it.
    /// Heeler's relay is rejected separately; it is not a typo.
    var hasInvalidEntry: Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || NotificationRelayEndpoint.isLegacyProductionBaseURL(trimmed) {
            return false
        }
        return Self.validate(rawValue) == nil
    }

    /// HTTP remains available for a relay running on the developer's machine,
    /// but the settings screen must warn before the Host sends a device token
    /// and notification metadata over a cleartext network connection.
    var hasInsecureHTTPEntry: Bool {
        relayURL?.scheme?.lowercased() == "http"
    }

    /// Parses a custom relay base URL: an absolute http(s) URL with a host and
    /// no query or fragment. A path prefix is allowed (the relay may be
    /// deployed under a subpath); the plugin appends `/push` to whatever base
    /// it is given, so a query or fragment would only be a mistake.
    static func validate(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty,
            components.query == nil, components.fragment == nil,
            let url = components.url
        else { return nil }
        return url
    }
}
