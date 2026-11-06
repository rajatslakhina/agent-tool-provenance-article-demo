import SwiftUI
import ProvenanceGate

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Launch arguments let the screenshot script open a specific screen:
/// `-tab fleet|compare` and `-policy auto|publisher|version|digest|canary|ci-keys|layered`.
struct RootView: View {
    @State private var tab: String = UserDefaults.standard.string(forKey: "tab") ?? "fleet"

    var body: some View {
        TabView(selection: $tab) {
            FleetView()
                .tabItem { Label("Replay", systemImage: "desktopcomputer") }
                .tag("fleet")
            CompareView()
                .tabItem { Label("Compare", systemImage: "tablecells") }
                .tag("compare")
        }
    }
}

struct FleetView: View {
    private let results = Sample.replayAll()
    @State private var policyID: String = UserDefaults.standard.string(forKey: "policy") ?? "auto"
    @State private var selectedMachine: MachineResult?

    private var current: ReplayResult? {
        results.first { $0.policy.id == policyID } ?? results.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("A tampered Anthropic.claude-code@2.1.312 is live on Cursor's marketplace for 11 hours. VS Code Macs get the real 2.1.312.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Policy", selection: $policyID) {
                        ForEach(results, id: \.policy.id) { r in
                            Text(r.policy.title).tag(r.policy.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("policyPicker")

                    if let r = current {
                        SummaryRow(result: r)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(r.machines) { m in
                                MachineTile(result: m)
                                    .onTapGesture { selectedMachine = m }
                            }
                        }
                        Legend()
                    }
                }
                .padding()
            }
            .navigationTitle("ProvenanceGate")
            .sheet(item: $selectedMachine) { m in
                MachineDetail(result: m).presentationDetents([.medium])
            }
        }
    }
}

struct SummaryRow: View {
    let result: ReplayResult

    var body: some View {
        HStack(spacing: 8) {
            Stat(value: result.compromisedMachines, label: "Macs\nbackdoored", tint: result.compromisedMachines > 0 ? .red : .green)
            Stat(value: result.exposedSecrets, label: "release keys\nexposed", tint: result.exposedSecrets > 0 ? .red : .green)
            Stat(value: result.blockedWithAlert, label: "blocked\nwith alert", tint: .blue)
            Stat(value: result.cleanUpdatesDelivered, label: "real update\ndelivered", tint: .secondary)
        }
    }
}

struct Stat: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title.bold().monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

extension MachineOutcome {
    var color: Color {
        switch self {
        case .installedTampered: return .red
        case .blocked: return .blue
        case .held: return .orange
        case .installedClean: return .green
        case .noOffer: return .gray
        }
    }

    var shortLabel: String {
        switch self {
        case .installedTampered(let detected): return detected ? "Backdoored · caught" : "Backdoored"
        case .blocked: return "Blocked"
        case .held: return "Held"
        case .installedClean: return "Real update"
        case .noOffer: return "No offer"
        }
    }

    var explanation: String {
        switch self {
        case .installedTampered(let detected):
            return detected ? "Installed the tampered build. The canary's integrity check saw the change and halted the rollout."
                            : "Installed the tampered build. The payload runs on extension load."
        case .blocked(let reason): return "Blocked: \(reason)."
        case .held(let reason): return "Held: \(reason)."
        case .installedClean: return "Installed the publisher's real 2.1.312."
        case .noOffer: return "Nothing offered."
        }
    }
}

struct MachineTile: View {
    let result: MachineResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(result.machine.id).font(.caption.bold().monospaced())
                Spacer(minLength: 0)
                if result.machine.holdsReleaseKeys {
                    Image(systemName: result.exposedSecrets.isEmpty ? "key" : "key.fill")
                        .font(.caption2)
                        .foregroundStyle(result.exposedSecrets.isEmpty ? Color.primary : Color.red)
                }
            }
            Text(result.machine.editor.rawValue).font(.caption2).foregroundStyle(.secondary)
            Text(result.outcome.shortLabel).font(.caption2.bold()).foregroundStyle(result.outcome.color)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(result.outcome.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(result.outcome.color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows why")
    }
}

struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Holds release keys (red when exposed)", systemImage: "key")
            Text("Tap a Mac to see which check fired.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct MachineDetail: View {
    let result: MachineResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(result.machine.id) · \(result.machine.role)").font(.headline)
            Text("\(result.machine.editor.rawValue) · \(result.machine.ring == .canary ? "canary ring" : "team ring")")
                .foregroundStyle(.secondary)
            if let offered = result.offered {
                Text("Offered: \(offered.identity.description)\nfrom \(offered.channel.description)")
                    .font(.callout.monospaced())
            }
            Text(result.outcome.explanation)
            if !result.exposedSecrets.isEmpty {
                Text("Exposed: " + result.exposedSecrets.map(\.rawValue).sorted().joined(separator: ", "))
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
    }
}

struct CompareView: View {
    private let results = Sample.replayAll()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results, id: \.policy.id) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(r.policy.title).font(.subheadline.bold())
                            HStack(spacing: 14) {
                                Metric(symbol: "exclamationmark.triangle.fill", value: r.compromisedMachines, tint: r.compromisedMachines > 0 ? .red : .green, label: "backdoored")
                                Metric(symbol: "key.fill", value: r.exposedSecrets, tint: r.exposedSecrets > 0 ? .red : .green, label: "keys exposed")
                                Metric(symbol: "bell.fill", value: r.blockedWithAlert, tint: .blue, label: "alerts")
                                Metric(symbol: "arrow.down.circle.fill", value: r.cleanUpdatesDelivered, tint: .secondary, label: "real update")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("12 Macs, 5 on Cursor, 3 holding release keys. Same tampered build, seven policies.")
                }
            }
            .navigationTitle("Seven policies")
        }
    }
}

struct Metric: View {
    let symbol: String
    let value: Int
    let tint: Color
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text("\(value)").monospacedDigit().bold()
        }
        .font(.caption)
        .accessibilityLabel("\(value) \(label)")
    }
}
