#if DEBUG
import Foundation
import OSLog

/// Writes ONE handover fact from the Mac, through the same call the
/// ContractCard toggle makes, so the Mac→CloudKit→iOS round trip for the
/// Phase 2.9 columns can be proved without synthetic input.
///
/// HOOPWISE_HANDOVER_WRITE="F5269E85,jersey=on"
///   · first field is a contract id PREFIX (any length), matched to exactly one
///   · then one of signed=on|off, jersey=on|off, ball=on|off
///
/// It refuses on an ambiguous prefix and reports rather than guessing. Results
/// go to the unified log (subsystem "hoopwise.demo") because the Mac app is
/// sandboxed and cannot write to the scratchpad.
@MainActor
enum HandoverWriteDebug {

    private static let log = Logger(subsystem: "hoopwise.demo", category: "handover")

    static func runIfRequested(dataManager dm: DataManager) {
        guard let spec = ProcessInfo.processInfo.environment["HOOPWISE_HANDOVER_WRITE"] else { return }

        var prefix = ""
        var field = ""
        var turnOn = true
        for piece in spec.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if piece.contains("=") {
                let parts = piece.split(separator: "=", maxSplits: 1)
                field = parts[0].lowercased()
                turnOn = parts.count > 1 && parts[1].lowercased() == "on"
            } else if prefix.isEmpty {
                prefix = piece.uppercased()
            }
        }
        guard !prefix.isEmpty, !field.isEmpty else {
            log.error("HANDOVER WRITE aborted — spec needs \"<idPrefix>,<field>=on|off\", got \(spec, privacy: .public)")
            return
        }

        let matches = dm.contracts.filter { $0.id.uuidString.uppercased().hasPrefix(prefix) }
        guard matches.count == 1, var contract = matches.first else {
            log.error("HANDOVER WRITE aborted — \(matches.count, privacy: .public) contracts match \(prefix, privacy: .public)")
            return
        }

        let before = "signed=\(contract.isSigned) jersey=\(contract.jerseyGiven) ball=\(contract.ballGiven)"
        switch field {
        case "signed": contract.isSigned = turnOn
        case "jersey": contract.jerseyGiven = turnOn
        case "ball":   contract.ballGiven = turnOn
        default:
            log.error("HANDOVER WRITE aborted — unknown field \(field, privacy: .public)")
            return
        }

        // The same writer the ContractCard toggle uses.
        dm.updateContract(contract)

        let reread = dm.contracts.first { $0.id == contract.id }
        let after = "signed=\(reread?.isSigned ?? false) jersey=\(reread?.jerseyGiven ?? false) ball=\(reread?.ballGiven ?? false)"
        let stamp = reread.flatMap { $0.jerseyGivenDate ?? $0.signedDate ?? $0.ballGivenDate }
        log.notice("""
            HANDOVER WRITE ok — contract \(contract.id.uuidString, privacy: .public) \
            field=\(field, privacy: .public) on=\(turnOn, privacy: .public) \
            BEFORE \(before, privacy: .public) AFTER \(after, privacy: .public) \
            stamp=\(stamp.map { ISO8601DateFormatter().string(from: $0) } ?? "—", privacy: .public)
            """)
    }
}
#endif
