import Foundation

/// Where Notification Registration sends a Host's relay base URL.
///
/// Mercurio does not ship Heeler's relay. Push stays off until someone enters
/// an Ormus relay URL. The herdr plugin still carries Mercurio's default until
/// that plugin is forked; this app must not write it.
enum NotificationRelayEndpoint {
    /// Empty: this build has no production relay.
    static let productionBaseURLString = ""

    /// Endpoints that used to be treated as the production default, including
    /// Heeler's relay. They are not a custom Ormus override. Registration
    /// leaves them unset rather than copying them onto a Host.
    static let legacyProductionBaseURLStrings = [
        "https://herdr-push-relay.69709991236.workers.dev",
        "https://herdr-apns.bybee.dev",
        "https://heeler-apns.bybee.dev",
    ]

    static var productionBaseURL: URL? { nil }

    static func resolve(customBaseURL: URL?) -> URL? {
        guard let customBaseURL else { return nil }
        if isLegacyProductionBaseURL(customBaseURL.absoluteString) { return nil }
        guard let scheme = customBaseURL.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else { return nil }
        return customBaseURL
    }

    static func isLegacyProductionBaseURL(_ value: String) -> Bool {
        legacyProductionBaseURLStrings.contains(normalized(value))
    }

    private static func normalized(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
