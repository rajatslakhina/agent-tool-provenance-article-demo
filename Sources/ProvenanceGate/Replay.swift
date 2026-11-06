/// A supply-chain incident to replay: what each editor's marketplace served during the window,
/// which of those builds were tampered with, and what the payload did to a host.
public struct Incident: Hashable, Sendable {
    public let title: String
    public let windowHours: Int
    public let offerings: [Editor: Artifact]
    /// Ground truth for the replay only. The gate never reads this.
    public let tamperedDigests: Set<String>
    public let payloadEffects: Set<HostEffect>

    public init(title: String, windowHours: Int, offerings: [Editor: Artifact], tamperedDigests: Set<String>, payloadEffects: Set<HostEffect>) {
        self.title = title
        self.windowHours = max(0, windowHours)
        self.offerings = offerings
        self.tamperedDigests = tamperedDigests
        self.payloadEffects = payloadEffects
    }

    public func isTampered(_ artifact: Artifact) -> Bool { tamperedDigests.contains(artifact.sha256) }
}

public enum MachineOutcome: Hashable, Sendable {
    case noOffer
    case installedClean
    case installedTampered(detectedByCanary: Bool)
    case blocked(BlockReason)
    case held(HoldReason)

    public var isCompromised: Bool {
        if case .installedTampered = self { return true }
        return false
    }
}

public enum HoldReason: Hashable, Sendable, CustomStringConvertible {
    case rolloutHalted(byMachine: String)
    case stillSoaking(soakHours: Int, windowHours: Int)

    public var description: String {
        switch self {
        case .rolloutHalted(let machine):
            return "rollout halted: canary \(machine) failed its integrity check"
        case .stillSoaking(let soak, let window):
            return "still in a \(soak)h canary soak when the \(window)h window closed"
        }
    }
}

public struct MachineResult: Hashable, Sendable, Identifiable {
    public let machine: Machine
    public let offered: Artifact?
    public let outcome: MachineOutcome
    public let exposedSecrets: Set<Secret>

    public var id: String { machine.id }
}

public struct ReplayResult: Hashable, Sendable {
    public let policy: InstallPolicy
    public let machines: [MachineResult]

    public var compromisedMachines: Int { machines.filter { $0.outcome.isCompromised }.count }
    public var compromisedKeyHolders: Int { machines.filter { $0.outcome.isCompromised && $0.machine.holdsReleaseKeys }.count }
    public var exposedSecrets: Int { machines.reduce(0) { $0 + $1.exposedSecrets.count } }
    public var blockedWithAlert: Int {
        machines.filter { if case .blocked = $0.outcome { return true } else { return false } }.count
    }
    public var cleanUpdatesDelivered: Int {
        machines.filter { $0.outcome == .installedClean }.count
    }
    public var canaryDetected: Bool {
        machines.contains { $0.outcome == .installedTampered(detectedByCanary: true) }
    }
}

/// Replays an incident across a fleet under one policy.
///
/// Order matters: canary machines are processed first, so a canary that catches the payload
/// can halt every later ring. Without a rollout plan every machine updates at once.
public enum IncidentReplay {
    public static func run(_ incident: Incident, fleet: [Machine], policy: InstallPolicy) -> ReplayResult {
        let ordered = policy.rollout == nil
            ? fleet
            : fleet.sorted { ($0.ring, $0.id) < ($1.ring, $1.id) }

        var haltedBy: String?
        var results: [String: MachineResult] = [:]

        for machine in ordered {
            guard let artifact = incident.offerings[machine.editor] else {
                results[machine.id] = MachineResult(machine: machine, offered: nil, outcome: .noOffer, exposedSecrets: [])
                continue
            }

            // Rings after canary wait for the soak and stop entirely if a canary tripped.
            if let rollout = policy.rollout, machine.ring > .canary {
                let outcome: MachineOutcome
                if let canary = haltedBy {
                    outcome = .held(.rolloutHalted(byMachine: canary))
                } else if rollout.soakHours >= incident.windowHours {
                    outcome = .held(.stillSoaking(soakHours: rollout.soakHours, windowHours: incident.windowHours))
                } else {
                    outcome = install(artifact, on: machine, incident: incident, policy: policy, haltedBy: &haltedBy)
                }
                results[machine.id] = result(machine, artifact, outcome, incident, policy)
                continue
            }

            let outcome = install(artifact, on: machine, incident: incident, policy: policy, haltedBy: &haltedBy)
            results[machine.id] = result(machine, artifact, outcome, incident, policy)
        }

        // Report in the fleet's own order, not rollout order.
        let ordering = fleet.compactMap { results[$0.id] }
        return ReplayResult(policy: policy, machines: ordering)
    }

    private static func install(_ artifact: Artifact, on machine: Machine, incident: Incident, policy: InstallPolicy, haltedBy: inout String?) -> MachineOutcome {
        switch AdmissionGate.evaluate(artifact, against: policy) {
        case .block(let reason):
            return .block(reason)
        case .admit:
            guard incident.isTampered(artifact) else { return .installedClean }
            var detected = false
            if let rollout = policy.rollout, machine.ring == .canary,
               !rollout.integrityChecks.isDisjoint(with: incident.payloadEffects) {
                detected = true
                if haltedBy == nil { haltedBy = machine.id }
            }
            return .installedTampered(detectedByCanary: detected)
        }
    }

    private static func result(_ machine: Machine, _ artifact: Artifact, _ outcome: MachineOutcome, _ incident: Incident, _ policy: InstallPolicy) -> MachineResult {
        let exposed: Set<Secret> = (outcome.isCompromised && policy.secretPlacement == .developerMacs) ? machine.secrets : []
        return MachineResult(machine: machine, offered: artifact, outcome: outcome, exposedSecrets: exposed)
    }
}

private extension MachineOutcome {
    static func block(_ reason: BlockReason) -> MachineOutcome { .blocked(reason) }
}
