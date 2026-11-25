import Foundation
import SwiftUI
import UIKit

/// Builds a prompt a coding agent can take from a failure on the phone.
/// The evidence is the text already shown to the person, then scrubbed.
enum FixPrompt {
    /// UserDefaults key. Missing means off.
    static let enabledKey = "fix-prompt-enabled"

    enum Situation: Equatable {
        case connection
        case herdr
        case overlay

        var lead: String {
            switch self {
            case .connection:
                "Mercurio can't connect, and I need you to fix it."
            case .herdr:
                "Mercurio can't talk to herdr, and I need you to fix it."
            case .overlay:
                "A Tailscale, ZeroTier, or EasyTier refresh failed, and I need you to fix it."
            }
        }

        var happened: String {
            switch self {
            case .connection:
                "The connection failed or dropped."
            case .herdr:
                "A herdr session failed or fell out of sync."
            case .overlay:
                "Refreshing the overlay network failed."
            }
        }
    }

    static func connection(_ report: String) -> String {
        text(.connection, report: report)
    }

    static func text(_ situation: Situation, report: String) -> String {
        let evidence = SecretRedactor.redact(report)
        return """
        \(situation.lead)

        Mercurio is the phone console for coding agents that run in herdr. \
        It reaches those machines over SSH.

        What happened: \(situation.happened) The report below \
        comes from the phone.

        Please:
        1. Find the root cause from the evidence below. Say what you checked.
        2. If the fix is on the host or the network, make it there, or give \
        the exact commands.
        3. If the fix is a Mercurio setting on the phone, say which screen \
        and field to change.
        4. If it is a bug in Mercurio, say so and point at the likely code.
        Do not ask for passwords or private keys. None are included.

        ## Evidence (from the phone, secrets removed)

        \(evidence)
        """
    }
}

/// Shown only while Copy fix prompt is on in Settings. Copies the failure
/// already on screen, with secrets removed.
struct CopyFixPromptButton: View {
    let report: String
    var situation: FixPrompt.Situation = .connection
    @AppStorage(FixPrompt.enabledKey) private var isEnabled = false

    var body: some View {
        if isEnabled, !report.isEmpty {
            Button("Copy fix prompt") {
                UIPasteboard.general.string = FixPrompt.text(situation, report: report)
            }
            .frame(minHeight: 44)
        }
    }
}

/// Strips private-key blocks and password-style assignments from text that
/// is about to leave the phone on the clipboard.
enum SecretRedactor {
    static let redacted = "[redacted]"
    static let redactedKey = "[private key redacted]"

    static func redact(_ text: String) -> String {
        let withoutKeys = replacing(
            text,
            pattern: "-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\\z)",
            template: redactedKey)
        return replacingAssignments(withoutKeys)
    }

    private static func replacing(
        _ text: String, pattern: String, template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    /// Keeps the name and the separator (`password=`), replaces the value.
    private static func replacingAssignments(_ text: String) -> String {
        let pattern =
            "(?i)(?<![A-Za-z])(pass(?:word|phrase|wd)?|secret|token|api[_-]?key)([ \\t]*[=:][ \\t]*)(?:\"[^\"\\n]*\"|'[^'\\n]*'|[^\\s'\"]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            guard let span = Range(match.range, in: result),
                let nameSpan = Range(match.range(at: 1), in: result),
                let separatorSpan = Range(match.range(at: 2), in: result)
            else { continue }
            let replacement = String(result[nameSpan]) + String(result[separatorSpan]) + redacted
            result.replaceSubrange(span, with: replacement)
        }
        return result
    }
}
