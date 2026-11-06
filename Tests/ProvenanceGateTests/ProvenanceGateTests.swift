import XCTest
@testable import ProvenanceGate

final class AdmissionGateTests: XCTestCase {
    func testNoPolicyAdmitsEverything() {
        let open = InstallPolicy(id: "open", title: "open")
        XCTAssertEqual(AdmissionGate.evaluate(Sample.tamperedUpdate, against: open), .admit)
    }

    func testPublisherAllowlistCannotTellTheTamperedBuildApart() {
        let policy = InstallPolicy(id: "p", title: "p", allowedPublishers: ["Anthropic"])
        XCTAssertEqual(AdmissionGate.evaluate(Sample.tamperedUpdate, against: policy), .admit)
        XCTAssertEqual(AdmissionGate.evaluate(Sample.officialUpdate, against: policy), .admit)
    }

    func testPublisherAllowlistBlocksAnUnknownPublisher() {
        let policy = InstallPolicy(id: "p", title: "p", allowedPublishers: ["Anthropic"])
        let impostor = Artifact(identity: ToolIdentity(publisher: "Anthrop1c", name: "claude-code", version: "2.1.312"),
                                channel: .sideload, sha256: "aa")
        XCTAssertEqual(AdmissionGate.evaluate(impostor, against: policy), .block(.publisherNotAllowed("Anthrop1c")))
    }

    func testVersionPinTrustsALabelTheUploaderTyped() {
        let pinned = InstallPolicy(id: "v", title: "v", pinnedVersions: [Sample.toolID: "2.1.312"])
        XCTAssertEqual(AdmissionGate.evaluate(Sample.tamperedUpdate, against: pinned), .admit)
    }

    func testAnOldVersionPinBlocksTheAttackAndTheRealUpdateAlike() {
        let stale = InstallPolicy(id: "v", title: "v", pinnedVersions: [Sample.toolID: "2.1.311"])
        let expected = GateDecision.block(.versionNotPinned(expected: "2.1.311", offered: "2.1.312"))
        XCTAssertEqual(AdmissionGate.evaluate(Sample.tamperedUpdate, against: stale), expected)
        XCTAssertEqual(AdmissionGate.evaluate(Sample.officialUpdate, against: stale), expected)
    }

    func testDigestLockfileAdmitsTheReviewedBytesFromAnyChannel() {
        let mirroredHonestly = Artifact(identity: Sample.officialUpdate.identity,
                                        channel: Sample.cursorChannel,
                                        sha256: Sample.officialUpdate.sha256.uppercased())
        let policy = InstallPolicy(id: "d", title: "d", lockfile: Sample.lockfile)
        XCTAssertEqual(AdmissionGate.evaluate(mirroredHonestly, against: policy), .admit)
    }

    func testDigestLockfileBlocksTheTamperedBuildWithAnActionableReason() {
        let policy = InstallPolicy(id: "d", title: "d", lockfile: Sample.lockfile)
        guard case .block(.digestMismatch(let expected, let offered, let channel)) =
                AdmissionGate.evaluate(Sample.tamperedUpdate, against: policy) else {
            return XCTFail("expected a digest mismatch")
        }
        XCTAssertEqual(expected, Sample.officialUpdate.sha256)
        XCTAssertEqual(offered, Sample.tamperedUpdate.sha256)
        XCTAssertEqual(channel, Sample.cursorChannel)
    }

    func testLockfileBlocksToolsItHasNeverSeen() {
        let policy = InstallPolicy(id: "d", title: "d", lockfile: Lockfile())
        XCTAssertEqual(AdmissionGate.evaluate(Sample.officialUpdate, against: policy), .block(.notInLockfile(Sample.toolID)))
    }

    func testBlockReasonsReadAsSentences() {
        let reason = BlockReason.digestMismatch(expected: Sample.officialUpdate.sha256,
                                                offered: Sample.tamperedUpdate.sha256,
                                                channel: Sample.cursorChannel)
        XCTAssertEqual(reason.description,
                       "sha256 d41b7e09 from Cursor extension marketplace (redistributor) does not match the reviewed 8c2e5f71")
    }
}

final class IncidentReplayTests: XCTestCase {
    private func result(_ id: String) throws -> ReplayResult {
        try XCTUnwrap(Sample.replayAll().first { $0.policy.id == id })
    }

    func testFleetShape() {
        XCTAssertEqual(Sample.fleet.count, 12)
        XCTAssertEqual(Sample.fleet.filter { $0.editor == .cursor }.count, 5)
        XCTAssertEqual(Sample.fleet.filter(\.holdsReleaseKeys).count, 3)
        XCTAssertEqual(Set(Sample.fleet.map(\.id)).count, 12)
    }

    func testEveryCellOfThePublishedTable() throws {
        // policy: (backdoored, key holders hit, secrets exposed, blocked + alert, real update delivered)
        let expected: [String: [Int]] = [
            "auto": [5, 2, 4, 0, 7],
            "publisher": [5, 2, 4, 0, 7],
            "version": [5, 2, 4, 0, 7],
            "digest": [0, 0, 0, 5, 7],
            "canary": [1, 0, 0, 0, 1],
            "ci-keys": [5, 2, 0, 0, 7],
            "layered": [0, 0, 0, 1, 1],
        ]
        let results = Sample.replayAll()
        XCTAssertEqual(results.map(\.policy.id), ["auto", "publisher", "version", "digest", "canary", "ci-keys", "layered"])
        for r in results {
            let row = [r.compromisedMachines, r.compromisedKeyHolders, r.exposedSecrets, r.blockedWithAlert, r.cleanUpdatesDelivered]
            XCTAssertEqual(row, try XCTUnwrap(expected[r.policy.id]), r.policy.id)
        }
    }

    func testIdentityChecksLetTheTamperedBuildOntoEveryCursorMac() throws {
        for id in ["auto", "publisher", "version"] {
            let r = try result(id)
            XCTAssertEqual(r.compromisedMachines, 5, id)
            XCTAssertEqual(r.compromisedKeyHolders, 2, id)
            XCTAssertEqual(r.exposedSecrets, 4, id)
            XCTAssertEqual(r.blockedWithAlert, 0, id)
            XCTAssertEqual(r.cleanUpdatesDelivered, 7, id)
        }
    }

    func testDigestLockfileStopsItEverywhereAndKeepsTheRealUpdateFlowing() throws {
        let r = try result("digest")
        XCTAssertEqual(r.compromisedMachines, 0)
        XCTAssertEqual(r.blockedWithAlert, 5)
        XCTAssertEqual(r.cleanUpdatesDelivered, 7)
    }

    func testCanaryCatchesItOnOneMacAndFreezesEveryoneElse() throws {
        let r = try result("canary")
        XCTAssertEqual(r.compromisedMachines, 1)
        XCTAssertEqual(r.compromisedKeyHolders, 0)
        XCTAssertTrue(r.canaryDetected)
        XCTAssertEqual(r.cleanUpdatesDelivered, 1)
        let mac01 = try XCTUnwrap(r.machines.first { $0.id == "mac-01" })
        XCTAssertEqual(mac01.outcome, .held(.rolloutHalted(byMachine: "mac-03")))
    }

    func testCanaryWithoutAMatchingCheckOnlyBuysTime() {
        let blind = InstallPolicy(id: "blind", title: "blind",
                                  rollout: RolloutPlan(soakHours: 6, integrityChecks: []))
        let r = IncidentReplay.run(Sample.incident, fleet: Sample.fleet, policy: blind)
        XCTAssertFalse(r.canaryDetected)
        // A 6h soak is shorter than the 11h window, so the team ring receives it too.
        XCTAssertEqual(r.compromisedMachines, 5)
    }

    func testKeysInCIShrinksTheBlastRadiusButNotTheInfection() throws {
        let r = try result("ci-keys")
        XCTAssertEqual(r.compromisedMachines, 5)
        XCTAssertEqual(r.compromisedKeyHolders, 2)
        XCTAssertEqual(r.exposedSecrets, 0)
    }

    func testLayeredPolicyHasNoCompromiseAndAnHonestFreshnessCost() throws {
        let r = try result("layered")
        XCTAssertEqual(r.compromisedMachines, 0)
        XCTAssertEqual(r.exposedSecrets, 0)
        XCTAssertEqual(r.blockedWithAlert, 1)
        XCTAssertEqual(r.cleanUpdatesDelivered, 1)
        let mac08 = try XCTUnwrap(r.machines.first { $0.id == "mac-08" })
        XCTAssertEqual(mac08.outcome, .held(.stillSoaking(soakHours: 72, windowHours: 11)))
    }

    func testMachineWithNoOfferIsUntouched() {
        let incident = Incident(title: "VS Code only", windowHours: 1,
                                offerings: [.vsCode: Sample.officialUpdate],
                                tamperedDigests: [], payloadEffects: [])
        let r = IncidentReplay.run(incident, fleet: Sample.fleet, policy: Sample.policies[0])
        XCTAssertEqual(r.machines.filter { $0.outcome == .noOffer }.count, 5)
        XCTAssertEqual(r.machines.map(\.id), Sample.fleet.map(\.id))
    }

    func testEmptyFleet() {
        let r = IncidentReplay.run(Sample.incident, fleet: [], policy: Sample.policies[0])
        XCTAssertTrue(r.machines.isEmpty)
        XCTAssertEqual(r.compromisedMachines, 0)
    }

    func testNegativeInputsAreClamped() {
        XCTAssertEqual(RolloutPlan(soakHours: -5, integrityChecks: []).soakHours, 0)
        let incident = Incident(title: "x", windowHours: -1, offerings: [:], tamperedDigests: [], payloadEffects: [])
        XCTAssertEqual(incident.windowHours, 0)
    }
}
