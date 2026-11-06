/// One pinned tool: the exact bytes the team reviewed, taken from the publisher's own channel.
public struct LockEntry: Hashable, Sendable {
    public let identity: ToolIdentity
    public let sha256: String
    public let reviewedFrom: Channel

    public init(identity: ToolIdentity, sha256: String, reviewedFrom: Channel) {
        self.identity = identity
        self.sha256 = sha256
        self.reviewedFrom = reviewedFrom
    }
}

/// A team lockfile for agent tooling, keyed by marketplace ID.
public struct Lockfile: Hashable, Sendable {
    public private(set) var entries: [String: LockEntry]

    public init(_ entries: [LockEntry] = []) {
        var map: [String: LockEntry] = [:]
        for entry in entries { map[entry.identity.id] = entry }
        self.entries = map
    }

    public func entry(for id: String) -> LockEntry? { entries[id] }
}

/// Staged rollout: canary machines take an update first, and later rings wait out the soak.
public struct RolloutPlan: Hashable, Sendable {
    public let soakHours: Int
    /// Host changes the canary watches for after every agent-tool install.
    public let integrityChecks: Set<HostEffect>

    public init(soakHours: Int, integrityChecks: Set<HostEffect>) {
        self.soakHours = max(0, soakHours)
        self.integrityChecks = integrityChecks
    }
}

/// Where the release credentials live.
public enum SecretPlacement: String, Hashable, Sendable {
    case developerMacs = "on developer Macs"
    case ciOnly = "in CI only"
}

/// A complete install policy for agent tooling. Every field is optional on purpose:
/// the presets below are the policies teams actually run, from "none" upwards.
public struct InstallPolicy: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let allowedPublishers: Set<String>?
    public let pinnedVersions: [String: String]?
    public let lockfile: Lockfile?
    public let rollout: RolloutPlan?
    public let secretPlacement: SecretPlacement

    public init(
        id: String,
        title: String,
        allowedPublishers: Set<String>? = nil,
        pinnedVersions: [String: String]? = nil,
        lockfile: Lockfile? = nil,
        rollout: RolloutPlan? = nil,
        secretPlacement: SecretPlacement = .developerMacs
    ) {
        self.id = id
        self.title = title
        self.allowedPublishers = allowedPublishers
        self.pinnedVersions = pinnedVersions
        self.lockfile = lockfile
        self.rollout = rollout
        self.secretPlacement = secretPlacement
    }
}
