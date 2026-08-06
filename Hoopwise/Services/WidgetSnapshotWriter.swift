import Foundation
#if os(iOS)
import WidgetKit
import ImageIO
import CryptoKit
#endif

// MARK: - Snapshot writer for the widget suite (schema v2)
//
// The app-side half: builds the compact snapshot from the shared caches and
// writes it to the App Group whenever relevant data changes (hooked into the
// data manager's refresh paths) — the widgets are dumb renderers.
// Compiled into both apps; inert on the Mac, whose target has no App Group.
//
// Photos: the widget process cannot reliably read the app's container or
// SwiftData external storage, so athlete thumbnails are EXPORTED into
// AppGroup/WidgetPhotos/<id>.jpg — downsampled via CGImageSource (~360px,
// square center crop), re-encoded only when the source bytes change
// (content hash manifest), orphans pruned every write.

@MainActor
enum WidgetSnapshotWriter {
    private static var pendingWrite: Task<Void, Never>?

    /// Debounced: refresh storms (bulk edits, roll call) collapse to one
    /// write, and the widgets reload once.
    static func scheduleWrite(dataManager: DataManager) {
        #if os(iOS)
        pendingWrite?.cancel()
        pendingWrite = Task { @MainActor [weak dataManager] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let dataManager else { return }
            writeNow(dataManager: dataManager)
        }
        #endif
    }

    #if os(iOS)
    static func writeNow(dataManager: DataManager) {
        let now = Date()
        let calendar = Calendar.current
        let horizon = now.addingTimeInterval(48 * 3600)

        func snap(_ session: SessionEvent) -> NextUpSession {
            var programLine: String?
            var ageBand: String?
            var category: String?
            if let programId = session.programId,
               let program = dataManager.programs.first(where: { $0.id == programId }) {
                programLine = program.name
                ageBand = program.ageGroup.rawValue
                // Category from the record, never parsed from titles. Strip a
                // leading age band from the name so "U14 intermediate"
                // doesn't render "U14 · U14 intermediate".
                var name = program.name
                if name.uppercased().hasPrefix(program.ageGroup.rawValue.uppercased()) {
                    name = String(name.dropFirst(program.ageGroup.rawValue.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: " -–·"))
                }
                category = name.isEmpty ? program.programType.rawValue : name
            }
            return NextUpSession(id: session.id, title: session.title,
                                 start: session.startTime, end: session.endTime,
                                 location: session.location,
                                 rosterCount: session.attendeeIds.count,
                                 programLine: programLine,
                                 ageBand: ageBand, category: category)
        }

        let active = dataManager.sessionEvents.filter { $0.status != .cancelled }

        let upcoming = active
            .filter { $0.endTime > now && $0.startTime < horizon }
            .sorted { $0.startTime < $1.startTime }
            .prefix(8).map(snap)

        let today = active
            .filter { calendar.isDateInToday($0.date) }
            .sorted { $0.startTime < $1.startTime }
            .prefix(10).map(snap)

        let tomorrow = active
            .filter { calendar.isDateInTomorrow($0.date) }
            .sorted { $0.startTime < $1.startTime }
            .prefix(10).map(snap)

        // Week map: current week, first-weekday-first.
        let dayStart = calendar.startOfDay(for: now)
        let weekdayOffset = (calendar.component(.weekday, from: dayStart)
            - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: dayStart)!
        let weekMap: [WeekCell] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart)
            else { return nil }
            let count = active.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            return WeekCell(date: day, count: count)
        }

        let attention = attentionStudents(dataManager: dataManager, calendar: calendar)

        // ---- Timeline windows: featured session AND highlight per window,
        // so relevance rolls over at boundaries without the app waking.
        var boundaries: Set<Date> = [now]
        for session in upcoming {
            if session.start > now { boundaries.insert(session.start) }
            if session.end > now { boundaries.insert(session.end) }
        }
        let sortedBounds = boundaries.sorted()
        let horizonEnd = horizon
        var windows: [NextUpWindow] = []
        for (index, windowStart) in sortedBounds.enumerated() {
            let windowEnd = index + 1 < sortedBounds.count ? sortedBounds[index + 1] : horizonEnd
            guard windowEnd > windowStart else { continue }
            let featured = upcoming.first { $0.start <= windowStart && windowStart < $0.end }
                ?? upcoming.first { $0.start > windowStart }
            let roster: Set<UUID> = featured.flatMap { feature in
                dataManager.sessionEvents.first { $0.id == feature.id }
                    .map { Set($0.attendeeIds) }
            } ?? []
            let windowHighlight = windowHighlight(
                at: windowStart, attention: attention, roster: roster,
                horizon: Array(upcoming), dataManager: dataManager)
            windows.append(NextUpWindow(
                start: windowStart, end: windowEnd,
                session: featured,
                highlight: windowHighlight,
                roster: featured.flatMap {
                    rosterCluster(for: $0, attention: attention, dataManager: dataManager)
                },
                rosterTotal: featured?.rosterCount))
        }
        let highlight = windows.first?.highlight

        // Photo export: everyone the snapshot references (highlights,
        // attention list, every window's roster).
        var referencedIds = attention.map(\.id)
        for window in windows {
            if let student = window.highlight { referencedIds.append(student.id) }
            for member in window.roster ?? [] { referencedIds.append(member.id) }
        }
        let photoNames = exportPhotos(for: referencedIds, dataManager: dataManager)
        func withPhoto(_ student: NextUpStudent) -> NextUpStudent {
            var copy = student
            copy.photoFilename = photoNames[copy.id]
            copy.avatarJPEG = nil
            return copy
        }
        for index in windows.indices {
            windows[index].highlight = windows[index].highlight.map(withPhoto)
            windows[index].roster = windows[index].roster.map { members in
                members.map { member in
                    var copy = member
                    copy.photoFilename = photoNames[copy.id]
                    return copy
                }
            }
        }

        let snapshot = NextUpSnapshot(
            generatedAt: now,
            sessions: Array(upcoming),
            highlight: highlight,
            version: 2,
            todaySessions: Array(today),
            tomorrowSessions: Array(tomorrow),
            attention: attention.map(withPhoto),
            weekMap: weekMap,
            weeklyAttendancePercent: weeklyAttendance(dataManager: dataManager,
                                                      calendar: calendar),
            windows: windows)
        WidgetShared.saveSnapshot(snapshot)
        for kind in WidgetShared.allKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        scheduleRolloverWrite(dataManager: dataManager, boundaries: sortedBounds, now: now)
    }

    /// While the app happens to be running, rewrite at the next session
    /// boundary too — fresher than the precomputed windows alone.
    private static var rolloverTask: Task<Void, Never>?
    private static func scheduleRolloverWrite(dataManager: DataManager,
                                              boundaries: [Date], now: Date) {
        rolloverTask?.cancel()
        guard let next = boundaries.first(where: { $0 > now.addingTimeInterval(5) }) else { return }
        let delay = next.timeIntervalSince(now) + 2
        rolloverTask = Task { @MainActor [weak dataManager] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let dataManager else { return }
            writeNow(dataManager: dataManager)
        }
    }

    /// Highlight for one window. Relevance rule: a Noted student who is
    /// tied to horizon sessions is only eligible while one of their
    /// sessions has not yet ended; afterwards selection recomputes from
    /// what's upcoming (attention/streak, next-roster preferred).
    private static func windowHighlight(at windowStart: Date,
                                        attention: [NextUpStudent],
                                        roster: Set<UUID>,
                                        horizon: [NextUpSession],
                                        dataManager: DataManager) -> NextUpStudent? {
        func stillRelevant(_ student: NextUpStudent) -> Bool {
            guard student.reason == .noted else { return true }
            let tied = dataManager.sessionEvents.filter { session in
                session.status != .cancelled
                    && horizon.contains { $0.id == session.id }
                    && (session.attendeeIds.contains(student.id)
                        || session.actualAttendeeIds.contains(student.id))
            }
            guard !tied.isEmpty else { return true }   // pure note, no session tie
            return tied.contains { $0.endTime > windowStart }
        }
        let eligible = attention.filter(stillRelevant)
        // Prefer a candidate in this window's roster when the rule ties.
        if let inRoster = eligible.first(where: { roster.contains($0.id) }) { return inRoster }
        if let first = eligible.first { return first }
        return topAttender(dataManager: dataManager, roster: roster)
    }

    /// The featured session's roster as tiered cluster members, capped at 8.
    /// Tier 0 = attention fires, 2 = steady, 1 = neutral — shared scoring.
    private static func rosterCluster(for session: NextUpSession,
                                      attention: [NextUpStudent],
                                      dataManager: DataManager) -> [NextUpRosterMember]? {
        guard let event = dataManager.sessionEvents.first(where: { $0.id == session.id }),
              !event.attendeeIds.isEmpty else { return nil }
        let attentionById = Dictionary(uniqueKeysWithValues: attention.map { ($0.id, $0) })
        var members: [NextUpRosterMember] = []
        for id in event.attendeeIds {
            guard let student = dataManager.students.first(where: { $0.id == id }) else { continue }
            let tier: Int
            var reason: NextUpStudent.Reason?
            if let hit = attentionById[id] {
                tier = 0
                reason = hit.reason
            } else {
                let rate = attendanceRate(of: student, dataManager: dataManager)
                tier = (rate.of >= AttentionRules.attendanceMinSessions
                        && rate.percent >= AttentionRules.steadyPercent) ? 2 : 1
            }
            members.append(NextUpRosterMember(id: id, name: student.name,
                                              initials: student.initials,
                                              photoFilename: nil,
                                              tier: tier, reason: reason))
        }
        // Deterministic: tier first, then stable id order — no reshuffling.
        members.sort {
            $0.tier != $1.tier ? $0.tier < $1.tier : $0.id.uuidString < $1.id.uuidString
        }
        return Array(members.prefix(8))
    }

    // MARK: Attention — shared rules, deterministic order.

    /// Noted (most recent first) → bundle low → attendance drop (worst
    /// first). Deduplicated, max 3 — the same list every attention surface
    /// should show.
    private static func attentionStudents(dataManager: DataManager,
                                          calendar: Calendar) -> [NextUpStudent] {
        var picked: [NextUpStudent] = []
        var seen: Set<UUID> = []

        let notedCutoff = calendar.date(byAdding: .day, value: -AttentionRules.notedWindowDays,
                                        to: Date()) ?? Date()
        let noted = dataManager.students.compactMap { student -> (Student, Date)? in
            guard let latest = student.parentalTouchpoints.map(\.date).max(),
                  latest >= notedCutoff else { return nil }
            return (student, latest)
        }.sorted { $0.1 > $1.1 }
        for (student, _) in noted where !seen.contains(student.id) {
            picked.append(makeStudent(student, reason: .noted))
            seen.insert(student.id)
        }

        for contract in dataManager.cachedContracts
        where contract.kind == .privateBundle && contract.status == .active
            && (contract.bundleRedemptionsRemaining ?? .max) <= AttentionRules.bundleLowRemaining {
            guard let student = dataManager.students.first(where: { $0.id == contract.studentId }),
                  !seen.contains(student.id) else { continue }
            picked.append(makeStudent(student, reason: .bundle))
            seen.insert(student.id)
        }

        let risky = dataManager.students
            .map { ($0, attendanceRate(of: $0, dataManager: dataManager)) }
            .filter { $0.1.of >= AttentionRules.attendanceMinSessions
                && $0.1.percent < AttentionRules.attendanceRiskPercent }
            .sorted { $0.1.percent < $1.1.percent }
        for (student, _) in risky where !seen.contains(student.id) {
            picked.append(makeStudent(student, reason: .attention))
            seen.insert(student.id)
        }
        return Array(picked.prefix(3))
    }

    private static func topAttender(dataManager: DataManager,
                                    roster: Set<UUID>) -> NextUpStudent? {
        dataManager.students
            .map { ($0, attendanceRate(of: $0, dataManager: dataManager)) }
            .filter { $0.1.of >= AttentionRules.attendanceMinSessions }
            .sorted { lhs, rhs in
                if lhs.1.percent != rhs.1.percent { return lhs.1.percent > rhs.1.percent }
                let lhsRoster = roster.contains(lhs.0.id), rhsRoster = roster.contains(rhs.0.id)
                if lhsRoster != rhsRoster { return lhsRoster }
                return lhs.0.name < rhs.0.name
            }
            .first.map { makeStudent($0.0, reason: .streak) }
    }

    private static func attendanceRate(of student: Student,
                                       dataManager: DataManager) -> (percent: Int, of: Int) {
        let relevant = dataManager.sessionEvents.filter {
            $0.date <= Date()
                && ($0.attendeeIds.contains(student.id)
                    || $0.actualAttendeeIds.contains(student.id))
        }
        guard !relevant.isEmpty else { return (100, 0) }
        let attended = relevant.filter { $0.actualAttendeeIds.contains(student.id) }.count
        return (Int(Double(attended) / Double(relevant.count) * 100), relevant.count)
    }

    /// Roster-wide attendance over the trailing 7 days — the quiet positive.
    private static func weeklyAttendance(dataManager: DataManager,
                                         calendar: Calendar) -> Int? {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = dataManager.sessionEvents.filter {
            $0.date >= cutoff && $0.date <= Date() && $0.status != .cancelled
        }
        var attended = 0, expected = 0
        for session in recent {
            expected += Set(session.attendeeIds).union(session.actualAttendeeIds).count
            attended += session.actualAttendeeIds.count
        }
        guard expected > 0 else { return nil }
        return Int(Double(attended) / Double(expected) * 100)
    }

    private static func makeStudent(_ student: Student,
                                    reason: NextUpStudent.Reason) -> NextUpStudent {
        NextUpStudent(id: student.id, name: student.name,
                      chineseName: student.chineseName,
                      initials: student.initials, reason: reason)
    }

    // MARK: - Photo export (App Group files, hash-gated, orphan-pruned)

    private static let manifestFilename = "manifest.json"

    private static func exportPhotos(for ids: [UUID],
                                     dataManager: DataManager) -> [UUID: String] {
        guard let directory = WidgetShared.photosDirectory else { return [:] }
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let manifestURL = directory.appendingPathComponent(manifestFilename)
        var manifest: [String: String] = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]

        var result: [UUID: String] = [:]
        var kept: Set<String> = [manifestFilename]

        for id in Set(ids) {
            guard let student = dataManager.students.first(where: { $0.id == id }),
                  let source = student.profileImageData ?? student.thumbnailImageData
            else { continue }
            let filename = "\(id.uuidString).jpg"
            let fileURL = directory.appendingPathComponent(filename)
            let hash = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()

            // Re-encode only when missing or the source photo changed.
            if manifest[id.uuidString] != hash
                || !FileManager.default.fileExists(atPath: fileURL.path) {
                guard let jpeg = downsampledSquareJPEG(from: source, side: 360) else { continue }
                try? jpeg.write(to: fileURL, options: .atomic)
                manifest[id.uuidString] = hash
            }
            result[id] = filename
            kept.insert(filename)
        }

        // Prune orphans so the container doesn't grow forever.
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            for file in contents where !kept.contains(file) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
                manifest.removeValue(forKey: (file as NSString).deletingPathExtension)
            }
        }
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
        return result
    }

    /// CGImageSource thumbnailing — the full-res photo never gets decoded
    /// at size, and never reaches the widget process.
    private static func downsampledSquareJPEG(from data: Data, side: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        // Aspect-fill center crop to square.
        let width = thumb.width, height = thumb.height
        let squareSide = min(width, height)
        let cropRect = CGRect(x: (width - squareSide) / 2, y: (height - squareSide) / 2,
                              width: squareSide, height: squareSide)
        let squared = thumb.cropping(to: cropRect) ?? thumb

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, squared,
                                   [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
    #endif
}
