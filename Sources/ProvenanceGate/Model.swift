/// What a marketplace listing claims to be. Every field is a string the uploader typed,
/// which is the whole problem: none of it proves who built the bytes.
public struct ToolIdentity: Hashable, Sendable, CustomStringConvertible {
    public let publisher: String
    public let name: String
    public let version: String

    public init(publisher: String, name: String, version: String) {
        self.publisher = publisher
        self.name = name
        self.version = version
    }

    /// The marketplace ID, e.g. `Anthropic.claude-code`.
    public var id: String { "\(publisher).\(name)" }
    public var description: String { "\(id)@\(version)" }
}

/// Where an artifact was downloaded from.
public enum Channel: Hashable, Sendable, CustomStringConvertible {
    /// A channel the publisher itself operates or uploads to with its own account.
    case publisherOfficial(String)
    /// Someone else's store that lists the publisher's tool. It can be honest, but the
    /// publisher doesn't control what it serves.
    case redistributor(String)
    case sideload

    public var description: String {
        switch self {
        case .publisherOfficial(let name): return "\(name) (publisher)"
        case .redistributor(let name): return "\(name) (redistributor)"
        case .sideload: return "sideload"
        }
    }
}

/// A downloadable build. `sha256` is the only field derived from the bytes themselves.
public struct Artifact: Hashable, Sendable {
    public let identity: ToolIdentity
    public let channel: Channel
    public let sha256: String

    public init(identity: ToolIdentity, channel: Channel, sha256: String) {
        self.identity = identity
        self.channel = channel
        self.sha256 = sha256
    }
}

/// The editor decides which marketplace a machine's extensions come from.
public enum Editor: String, Hashable, Sendable, CaseIterable {
    case vsCode = "VS Code"
    case cursor = "Cursor"
}

/// Rollout rings, in promotion order.
public enum Ring: Int, Hashable, Sendable, CaseIterable, Comparable {
    case canary = 0
    case team = 1

    public static func < (lhs: Ring, rhs: Ring) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Credentials that turn one compromised laptop into a compromised app.
public enum Secret: String, Hashable, Sendable, CaseIterable {
    case distributionSigningIdentity = "Distribution signing identity"
    case appStoreConnectAPIKey = "App Store Connect API key (.p8)"
}

/// Things a payload does to a host that a post-install integrity check can watch for.
public enum HostEffect: String, Hashable, Sendable, CaseIterable {
    case authorizedKeysModified = "~/.ssh/authorized_keys changed"
    case persistenceAdded = "new startup item outside the extension directory"
    case environmentNamesCollected = "names of KEY/TOKEN/SECRET-style env vars collected"
}

public struct Machine: Hashable, Sendable, Identifiable {
    public let id: String
    public let role: String
    public let editor: Editor
    public let ring: Ring
    public let secrets: Set<Secret>

    public init(id: String, role: String, editor: Editor, ring: Ring, secrets: Set<Secret> = []) {
        self.id = id
        self.role = role
        self.editor = editor
        self.ring = ring
        self.secrets = secrets
    }

    public var holdsReleaseKeys: Bool { !secrets.isEmpty }
}
