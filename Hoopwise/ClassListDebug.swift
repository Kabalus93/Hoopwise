#if DEBUG
import Foundation

/// Headless, READ-ONLY check of a class list against the live store:
/// HOOPWISE_CLASSLIST_PREVIEW=<path to .xlsx> parses it, plans the import
/// with today → +12 weeks, and writes the plan as text to the App Group's
/// Library/Caches/classlist-preview.txt. Nothing is written to the store.
enum ClassListDebug {
    @MainActor
    static func previewIfRequested(dataManager: DataManager) {
        guard let path = ProcessInfo.processInfo.environment["HOOPWISE_CLASSLIST_PREVIEW"],
              let dir = WidgetShared.containerURL?.appendingPathComponent("Library/Caches", isDirectory: true)
        else { return }
        var out = "Class list preview — \(path)\n"
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let sheet = ClassList.parse(try XLSX.read(data)) else {
                out += "NO CLASS LIST FOUND\n"
                try? out.write(to: dir.appendingPathComponent("classlist-preview.txt"), atomically: true, encoding: .utf8)
                return
            }
            let from = Calendar.current.startOfDay(for: Date())
            let plan = ClassList.plan(sheet, students: dataManager.students, contracts: dataManager.contracts,
                                      programs: dataManager.programs, sessions: dataManager.sessionEvents,
                                      coaches: dataManager.staffCoaches,
                                      accountCoach: (dataManager.coach.id, dataManager.coach.name),
                                      options: ClassList.Options(from: from, through: from.addingTimeInterval(84 * 86_400)))
            out += "students \(plan.students.count) (new \(plan.newStudentCount)) · balances \(plan.balanceCount) · classes \(plan.classes.count) (new \(plan.newClassCount)) · sessions \(plan.sessionCount)\n"
            out += "declared total \(sheet.declaredTotal.map(String.init) ?? "—") by \(sheet.totalCoach ?? "—")\n\nISSUES\n"
            for issue in plan.issues { out += "  row \(issue.row.map(String.init) ?? "-"): \(issue.message)\n" }
            for planned in plan.classes {
                let b = planned.block
                out += "\n\(b.canonicalTitle) [\(planned.isNew ? "new" : "existing")] coach=\(b.coach ?? "—") coachId=\(planned.coachId != nil) 人数=\(b.declaredCount.map(String.init) ?? "—") sessions=\(planned.sessionStarts.count)\n"
                for id in planned.studentIds {
                    guard let s = plan.students.first(where: { $0.id == id }) else { continue }
                    let bal = s.balanceSessions.map { "\($0)" } ?? "—"
                    out += "  \(s.name)\t\(bal)\(s.monthsBased ? " (\(s.monthsLeft!.formatted()) mo)" : "")\(s.isNew ? "" : " [existing]")\n"
                }
            }
            out += "\nNO CLASS\n"
            for id in plan.withoutClass {
                if let s = plan.students.first(where: { $0.id == id }) {
                    out += "  \(s.name)\t\(s.balanceSessions.map(String.init) ?? "—")\n"
                }
            }
        } catch {
            out += "ERROR \(error.localizedDescription)\n"
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? out.write(to: dir.appendingPathComponent("classlist-preview.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
