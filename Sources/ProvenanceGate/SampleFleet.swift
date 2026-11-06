/// A constructed 12-Mac iOS team and a replay of the October 2026 incident in which a
/// maliciously modified Claude Code extension was served by Cursor's extension marketplace
/// for about 11 hours. The fleet, digests and policies are invented for the replay; the
/// incident's shape (publisher ID, version labels, window, payload) follows the public reports.
public enum Sample {
    public static let toolID = "Anthropic.claude-code"

    public static let officialChannel = Channel.publisherOfficial("Visual Studio Marketplace")
    public static let cursorChannel = Channel.redistributor("Cursor extension marketplace")

    /// The last build the team reviewed and pinned before the incident.
    public static let reviewed = Artifact(
        identity: ToolIdentity(publisher: "Anthropic", name: "claude-code", version: "2.1.311"),
        channel: officialChannel,
        sha256: "3f9a1c0e7b52d8a4c61e09f2b7d3a85e14c0f6b9a2d7e3c18b5f04a96e2d7c31"
    )

    /// In this replay the publisher's own channel ships 2.1.312 the same day, so a team
    /// that tracks the changelog bumps its pin to that label.
    public static let officialUpdate = Artifact(
        identity: ToolIdentity(publisher: "Anthropic", name: "claude-code", version: "2.1.312"),
        channel: officialChannel,
        sha256: "8c2e5f71a0d94b36e7f1c28a5d0b93e64f7a1c25d8e09b3a6f42c71e5d8a0b96"
    )

    /// Same publisher ID, same version label, different bytes, different store.
    public static let tamperedUpdate = Artifact(
        identity: ToolIdentity(publisher: "Anthropic", name: "claude-code", version: "2.1.312"),
        channel: cursorChannel,
        sha256: "d41b7e09c3a5f28e61d0b4c97a2e5f1308c6d9b2e7a4f10c35b8e2d6a9f07c41"
    )

    public static let incident = Incident(
        title: "Tampered Anthropic.claude-code@2.1.312 on a redistributor marketplace",
        windowHours: 11,
        offerings: [.vsCode: officialUpdate, .cursor: tamperedUpdate],
        tamperedDigests: [tamperedUpdate.sha256],
        payloadEffects: [.authorizedKeysModified, .persistenceAdded, .environmentNamesCollected]
    )

    public static let fleet: [Machine] = [
        Machine(id: "mac-01", role: "Release lead", editor: .cursor, ring: .team,
                secrets: [.distributionSigningIdentity, .appStoreConnectAPIKey]),
        Machine(id: "mac-02", role: "Release engineer", editor: .cursor, ring: .team,
                secrets: [.distributionSigningIdentity, .appStoreConnectAPIKey]),
        Machine(id: "mac-03", role: "iOS engineer", editor: .cursor, ring: .canary),
        Machine(id: "mac-04", role: "iOS engineer", editor: .cursor, ring: .team),
        Machine(id: "mac-05", role: "iOS engineer", editor: .cursor, ring: .team),
        Machine(id: "mac-06", role: "Platform engineer", editor: .vsCode, ring: .canary),
        Machine(id: "mac-07", role: "Release backup", editor: .vsCode, ring: .team,
                secrets: [.appStoreConnectAPIKey]),
        Machine(id: "mac-08", role: "iOS engineer", editor: .vsCode, ring: .team),
        Machine(id: "mac-09", role: "iOS engineer", editor: .vsCode, ring: .team),
        Machine(id: "mac-10", role: "iOS engineer", editor: .vsCode, ring: .team),
        Machine(id: "mac-11", role: "QA engineer", editor: .vsCode, ring: .team),
        Machine(id: "mac-12", role: "Designer-engineer", editor: .vsCode, ring: .team),
    ]

    static let canaryPlan = RolloutPlan(soakHours: 72, integrityChecks: [.authorizedKeysModified, .persistenceAdded])

    /// The lockfile after the team reviewed 2.1.312 from the publisher's channel.
    static let lockfile = Lockfile([
        LockEntry(identity: officialUpdate.identity, sha256: officialUpdate.sha256, reviewedFrom: officialChannel),
    ])

    public static let policies: [InstallPolicy] = [
        InstallPolicy(id: "auto", title: "Auto-update from the editor's marketplace"),
        InstallPolicy(id: "publisher", title: "Publisher allowlist", allowedPublishers: ["Anthropic"]),
        InstallPolicy(id: "version", title: "Version pin (bumped to 2.1.312)", pinnedVersions: [toolID: "2.1.312"]),
        InstallPolicy(id: "digest", title: "Digest lockfile", lockfile: lockfile),
        InstallPolicy(id: "canary", title: "Canary ring + integrity check", rollout: canaryPlan),
        InstallPolicy(id: "ci-keys", title: "Release keys in CI only", secretPlacement: .ciOnly),
        InstallPolicy(id: "layered", title: "Digest lockfile + canary + keys in CI",
                      lockfile: lockfile, rollout: canaryPlan, secretPlacement: .ciOnly),
    ]

    public static func replayAll() -> [ReplayResult] {
        policies.map { IncidentReplay.run(incident, fleet: fleet, policy: $0) }
    }
}
