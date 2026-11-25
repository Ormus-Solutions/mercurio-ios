import Foundation
import Testing

@testable import Mercurio

@Suite("Host merge")
struct HostMergeTests {
    private let wifi = Host(name: "At home", address: "192.168.1.130", username: "alice")
    private let tailscale = Host(
        name: "Away", address: "100.64.0.16", username: "Alice",
        overlayNetworkID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

    private func key(_ byte: UInt8) -> HostKeyFingerprint {
        HostKeyFingerprint(digest: Data([byte]), algorithm: "ssh-ed25519")
    }

    @Test func aSharedDigestFoldsTheSpareRoutesOntoTheKeptHost() throws {
        let merged = try HostMerge.merged(
            tailscale, into: wifi, sourceKeys: [key(1)], targetKeys: [key(1)]
        ).get()
        #expect(merged.id == wifi.id)
        #expect(merged.username == wifi.username)
        #expect(merged.name == wifi.name)
        #expect(merged.routes.map(\.address) == ["192.168.1.130", "100.64.0.16"])
        #expect(merged.routes[1].overlayNetworkID == tailscale.primaryRoute.overlayNetworkID)
        #expect(merged.routes[1].id != tailscale.primaryRoute.id)
    }

    @Test func aRouteTheKeptHostAlreadyHasIsNotCopied() throws {
        let duplicate = Host(
            address: "192.168.1.130", username: "alice",
            overlayNetworkID: nil)
        let source = Host(
            username: "alice",
            routes: [
                HostRoute(address: "192.168.1.130", port: 22),
                HostRoute(address: "100.64.0.16", port: 22, overlayNetworkID: tailscale.primaryRoute.overlayNetworkID),
            ])
        let merged = try HostMerge.merged(
            source, into: duplicate, sourceKeys: [key(1)], targetKeys: [key(1)]
        ).get()
        #expect(merged.routes.map(\.address) == ["192.168.1.130", "100.64.0.16"])
    }

    @Test func aDifferentHostKeyRefusesTheFold() {
        let result = HostMerge.merged(
            tailscale, into: wifi, sourceKeys: [key(1)], targetKeys: [key(2)])
        #expect(result == .failure(.differentHostKey))
    }

    @Test func aHostThatHasNeverConnectedRefusesTheFold() {
        let result = HostMerge.merged(
            tailscale, into: wifi, sourceKeys: [], targetKeys: [key(1)])
        #expect(result == .failure(.missingHostKey))
    }

    @Test func aDifferentAccountRefusesTheFold() {
        let other = Host(address: "10.0.0.2", username: "other", overlayNetworkID: UUID())
        let result = HostMerge.merged(
            other, into: wifi, sourceKeys: [key(1)], targetKeys: [key(1)])
        #expect(result == .failure(.differentAccount))
    }

    @Test func foldingAHostIntoItselfRefuses() {
        let result = HostMerge.merged(
            wifi, into: wifi, sourceKeys: [key(1)], targetKeys: [key(1)])
        #expect(result == .failure(.sameHost))
    }

    @Test func addMatchesOnlyHostsThatTrustThePresentedKey() {
        let matches = HostMerge.hosts(
            matching: key(7),
            among: [wifi, tailscale],
            keysByHost: [wifi.id: [key(7)], tailscale.id: [key(8)]])
        #expect(matches.map(\.id) == [wifi.id])
    }

    @Test func appendingARouteSkipsTheHopTheHostAlreadyDials() {
        let networkID = UUID()
        let host = Host(address: "100.64.0.16", username: "me", overlayNetworkID: networkID)
        let again = HostMerge.appending(
            address: "100.64.0.16", overlayNetworkID: networkID, to: host)
        #expect(again.added == false)
        #expect(again.host.routes.count == 1)

        let added = HostMerge.appending(
            address: "100.64.0.16", overlayNetworkID: networkID, to: wifi)
        #expect(added.added == true)
        #expect(added.host.routes.map(\.address) == ["192.168.1.130", "100.64.0.16"])
    }
}
