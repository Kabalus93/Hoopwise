import XCTest
@testable import Hoopwise

/// Guards the whole-record write path for sessions.
///
/// Why this exists: `updateSessionEvent` hand-listed 19 of SessionEvent's 23
/// content properties and silently dropped `unexcusedAbsences` (the field the
/// model comments call revenue-critical), `developmentFocus`, `headerImageURL`
/// and `createdByCoachId` on EVERY save. Nothing failed; the data just went
/// missing. Both write paths now funnel through `SDSessionEvent.apply(_:)`,
/// and these tests make a future drop loud.
@MainActor
final class SessionRoundTripTests: XCTestCase {

    // MARK: - Coverage guard

    /// Every stored property of `SessionEvent` as reviewed on 2026-08-09.
    ///
    /// This list is the point of the test. `testFixtureCoversEveryProperty`
    /// reflects over a live instance and fails when the model gains, loses or
    /// renames a property — which forces whoever adds a field to decide,
    /// deliberately, whether `apply(_:)` must carry it. Without the guard a
    /// new field would simply never be persisted on update and no test would
    /// notice, which is exactly how the four fields above were lost.
    private static let reviewedProperties: Set<String> = [
        "id", "microCycleId", "programId", "sessionType", "title", "date",
        "startTime", "endTime", "location", "status", "curriculum",
        "attendeeIds", "actualAttendeeIds", "excusedAbsences",
        "unexcusedAbsences", "attendancePhotoPath", "notes", "coachNotes",
        "developmentFocus", "manOfTheMatchId", "drillsCompleted", "rating",
        "createdByCoachId", "games", "headerImageURL", "createdAt", "updatedAt",
    ]

    /// Identity, not content: `apply` deliberately does not overwrite these.
    private static let identityProperties: Set<String> = ["id", "createdAt"]

    func testFixtureCoversEveryProperty() {
        let live = Set(Mirror(reflecting: Self.populated()).children.compactMap(\.label))

        let added = live.subtracting(Self.reviewedProperties)
        let removed = Self.reviewedProperties.subtracting(live)

        XCTAssertTrue(added.isEmpty, """
            SessionEvent gained \(added.sorted().joined(separator: ", ")).
            Decide whether SDSessionEvent.apply(_:) must persist it, give it a \
            distinct value in SessionRoundTripTests.populated(), then add it to \
            reviewedProperties. A property that reaches neither place is a \
            field that will be dropped on every save.
            """)
        XCTAssertTrue(removed.isEmpty, """
            SessionEvent no longer has \(removed.sorted().joined(separator: ", ")). \
            Remove it from reviewedProperties and from populated().
            """)
    }

    // MARK: - The drop guard

    /// The regression itself: write a fully-populated event over a blank one
    /// and require every content property to survive the round trip through
    /// SwiftData's model object.
    func testApplyPersistsEveryProperty() {
        let populated = Self.populated()
        let sd = SDSessionEvent.from(Self.blank(id: populated.id))

        sd.apply(populated)
        let readBack = sd.toStruct()

        let expected = Dictionary(uniqueKeysWithValues:
            Mirror(reflecting: populated).children.compactMap { child -> (String, String)? in
                guard let label = child.label else { return nil }
                return (label, String(describing: child.value))
            })
        let actual = Dictionary(uniqueKeysWithValues:
            Mirror(reflecting: readBack).children.compactMap { child -> (String, String)? in
                guard let label = child.label else { return nil }
                return (label, String(describing: child.value))
            })

        var dropped: [String] = []
        for (property, want) in expected where !Self.identityProperties.contains(property) {
            if actual[property] != want { dropped.append(property) }
        }

        XCTAssertTrue(dropped.isEmpty, """
            SDSessionEvent.apply(_:) did not persist: \(dropped.sorted().joined(separator: ", ")).
            Every content property must be copied in apply(_:) — it is the one \
            whole-record writer for both create and update.
            """)
    }

    /// `from(_:)` and `apply(_:)` must agree, since creation and update are
    /// the same write expressed twice.
    func testCreateAndUpdateProduceTheSameRecord() {
        let populated = Self.populated()

        let created = SDSessionEvent.from(populated).toStruct()
        let updated: SessionEvent = {
            let sd = SDSessionEvent.from(Self.blank(id: populated.id))
            sd.apply(populated)
            return sd.toStruct()
        }()

        // createdAt is identity: `from` carries the struct's value, `apply`
        // leaves the existing record's alone. Everything else must match.
        let differing = Self.contentProperties(of: created)
            .filter { Self.contentProperties(of: updated)[$0.key] != $0.value }
            .keys.sorted()

        XCTAssertTrue(differing.isEmpty, """
            A session created from a struct differs from the same struct applied \
            to an existing record, in: \(differing.joined(separator: ", ")).
            """)
    }

    /// A session with no header image has none. The initializer used to mint a
    /// random Unsplash URL, so every session carried a stock photo nobody
    /// chose — and before the field was persisted, a different one per read.
    func testNoHeaderImageIsInventedOnInit() {
        let event = Self.blank(id: UUID())
        XCTAssertNil(event.headerImageURL,
                     "SessionEvent.init invented a headerImageURL that no caller supplied.")
    }

    /// Property name → rendered value, excluding the identity columns.
    private static func contentProperties(of event: SessionEvent) -> [String: String] {
        Dictionary(uniqueKeysWithValues:
            Mirror(reflecting: event).children.compactMap { child -> (String, String)? in
                guard let label = child.label,
                      !identityProperties.contains(label) else { return nil }
                return (label, String(describing: child.value))
            })
    }

    // MARK: - Fixtures

    private static func blank(id: UUID) -> SessionEvent {
        SessionEvent(id: id,
                     title: "",
                     date: Date(timeIntervalSince1970: 0),
                     startTime: Date(timeIntervalSince1970: 0),
                     endTime: Date(timeIntervalSince1970: 0))
    }

    /// Every content property set to something distinguishable from `blank`,
    /// so a dropped field shows up as a mismatch naming that field.
    private static func populated() -> SessionEvent {
        var event = SessionEvent(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            microCycleId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            programId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sessionType: .assessment,
            title: "Round trip",
            date: Date(timeIntervalSince1970: 1_000_000),
            startTime: Date(timeIntervalSince1970: 1_000_100),
            endTime: Date(timeIntervalSince1970: 1_005_500),
            location: "义蓬酷迅体育中心",
            status: .completed,
            curriculum: SessionCurriculum(),
            attendeeIds: [UUID(uuidString: "44444444-4444-4444-4444-444444444444")!],
            actualAttendeeIds: [UUID(uuidString: "55555555-5555-5555-5555-555555555555")!],
            excusedAbsences: [UUID(uuidString: "66666666-6666-6666-6666-666666666666")!],
            unexcusedAbsences: [UUID(uuidString: "77777777-7777-7777-7777-777777777777")!],
            attendancePhotoPath: "attendance/photo.jpg",
            notes: "pre-session",
            coachNotes: "post-session",
            developmentFocus: [.shooting, .teamPlay],
            manOfTheMatchId: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            drillsCompleted: [UUID(uuidString: "99999999-9999-9999-9999-999999999999")!],
            rating: 4,
            createdByCoachId: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            games: [],
            headerImageURL: "https://example.invalid/header.jpg",
            createdAt: Date(timeIntervalSince1970: 900_000),
            updatedAt: Date(timeIntervalSince1970: 1_100_000))
        // Set through the property so the fixture does not depend on the
        // initializer's argument order for the JSON-backed columns.
        event.curriculum.warmupDrillIds = [UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!]
        return event
    }
}
