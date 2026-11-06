/// Why the gate refused an artifact. Each case names the check that fired.
public enum BlockReason: Hashable, Sendable, CustomStringConvertible {
    case publisherNotAllowed(String)
    case versionNotPinned(expected: String, offered: String)
    case notInLockfile(String)
    case digestMismatch(expected: String, offered: String, channel: Channel)

    public var description: String {
        switch self {
        case .publisherNotAllowed(let publisher):
            return "publisher \(publisher) is not on the allowlist"
        case .versionNotPinned(let expected, let offered):
            return "version \(offered) is not the pinned \(expected)"
        case .notInLockfile(let id):
            return "\(id) is not in the lockfile"
        case .digestMismatch(let expected, let offered, let channel):
            return "sha256 \(Self.short(offered)) from \(channel) does not match the reviewed \(Self.short(expected))"
        }
    }

    static func short(_ digest: String) -> String { String(digest.prefix(8)) }
}

public enum GateDecision: Hashable, Sendable {
    case admit
    case block(BlockReason)
}

/// Checks one artifact against one policy. It only sees what an installer can see:
/// the listing's claimed identity, the channel and the hash of the downloaded bytes.
public enum AdmissionGate {
    public static func evaluate(_ artifact: Artifact, against policy: InstallPolicy) -> GateDecision {
        let identity = artifact.identity

        if let allowed = policy.allowedPublishers, !allowed.contains(identity.publisher) {
            return .block(.publisherNotAllowed(identity.publisher))
        }

        if let pins = policy.pinnedVersions, let expected = pins[identity.id], expected != identity.version {
            return .block(.versionNotPinned(expected: expected, offered: identity.version))
        }

        if let lockfile = policy.lockfile {
            guard let entry = lockfile.entry(for: identity.id) else {
                return .block(.notInLockfile(identity.id))
            }
            // The version check is redundant with the hash, but it gives a clearer message
            // when someone simply forgot to bump the lockfile.
            if entry.identity.version != identity.version {
                return .block(.versionNotPinned(expected: entry.identity.version, offered: identity.version))
            }
            if entry.sha256.lowercased() != artifact.sha256.lowercased() {
                return .block(.digestMismatch(expected: entry.sha256, offered: artifact.sha256, channel: artifact.channel))
            }
        }

        return .admit
    }
}
