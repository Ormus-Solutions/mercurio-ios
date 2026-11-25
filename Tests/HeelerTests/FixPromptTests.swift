import Foundation
import Testing

@testable import Mercurio

@Suite("Copy fix prompt")
struct FixPromptTests {
    @Test func aMissingSettingIsOff() {
        let name = "fix-prompt-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(defaults.bool(forKey: FixPrompt.enabledKey) == false)
    }

    @Test func connectionPromptDropsAPasswordAndAPrivateKey() {
        let report = """
        SSH unavailable: password=hunter2
        -----BEGIN OPENSSH PRIVATE KEY-----
        abcdef
        -----END OPENSSH PRIVATE KEY-----
        """
        let prompt = FixPrompt.connection(report)

        #expect(prompt.contains("Do not ask for passwords or private keys"))
        #expect(prompt.contains("secrets removed"))
        #expect(!prompt.contains("hunter2"))
        #expect(!prompt.contains("abcdef"))
        #expect(prompt.contains("password=[redacted]"))
        #expect(prompt.contains("[private key redacted]"))
        #expect(prompt.contains("SSH unavailable"))
    }

    @Test func herdrAndOverlayNameTheFailure() {
        let herdr = FixPrompt.text(.herdr, report: "session sync failed")
        let overlay = FixPrompt.text(.overlay, report: "tailnet refresh timed out")
        #expect(herdr.contains("can't talk to herdr"))
        #expect(herdr.contains("session sync failed"))
        #expect(overlay.contains("Tailscale, ZeroTier, or EasyTier"))
        #expect(overlay.contains("tailnet refresh timed out"))
        #expect(FixPrompt.connection("SSH unavailable").contains("can't connect"))
    }
}

@Suite("Needs you")
struct NeedsYouTests {
    @Test func onlyBlockedAgentsCount() {
        let waiting = NeedsYou.waiting(
            in: [
                (id: "a", isBlocked: false),
                (id: "b", isBlocked: true),
                (id: "c", isBlocked: true),
            ])
        #expect(waiting == ["b", "c"])
    }

    @Test func aTapWalksToTheNextWaitingAgentAndWraps() {
        let waiting = ["b", "c"]
        #expect(NeedsYou.next(after: nil, in: waiting) == "b")
        #expect(NeedsYou.next(after: "b", in: waiting) == "c")
        #expect(NeedsYou.next(after: "c", in: waiting) == "b")
        #expect(NeedsYou.next(after: "gone", in: waiting) == "b")
        #expect(NeedsYou.next(after: "b", in: []) == nil)
    }
}
