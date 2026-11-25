import XCTest
@testable import Hoopwise

/// Contract expiry, and the stored hand-over dates.
///
/// `isExpired` used to return `false` always, behind a red warning that could
/// never fire. The signed / jersey / ball toggles are gone (25 Nov 2026); the
/// three date columns stay in the schema and must survive every save —
/// `applyContract` hand-lists its columns.
@MainActor
final class ContractHandoverTests: XCTestCase {

    private let student = UUID()

    private func bundle(validityMonths: Int = 0,
                        purchased: Date? = nil) -> Contract {
        Contract(studentId: student, kind: .privateBundle,
                 enrollmentDate: purchased ?? Date(),
                 pricePerSession: 300, bundleSize: 10,
                 bundlePurchaseDate: purchased,
                 validityMonths: validityMonths)
    }

    // MARK: - Expiry

    func testNoTermMeansNoExpiry() {
        let contract = bundle(validityMonths: 0,
                              purchased: Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertNil(contract.expiresOn)
        XCTAssertFalse(contract.isExpired(), "A term nobody agreed cannot expire.")
    }

    func testATermRunsFromThePurchaseDate() {
        let purchased = Date(timeIntervalSince1970: 1_770_000_000)   // 2026-02-02
        let contract = bundle(validityMonths: 3, purchased: purchased)
        let expected = Calendar.current.date(byAdding: .month, value: 3, to: purchased)
        XCTAssertEqual(contract.expiresOn, expected)
    }

    func testExpiredOnlyAfterTheTermEnds() {
        let purchased = Date(timeIntervalSince1970: 1_770_000_000)
        let contract = bundle(validityMonths: 3, purchased: purchased)
        let dayBefore = contract.expiresOn!.addingTimeInterval(-86_400)
        let dayAfter = contract.expiresOn!.addingTimeInterval(86_400)

        XCTAssertFalse(contract.isExpired(asOf: dayBefore))
        XCTAssertTrue(contract.isExpired(asOf: dayAfter),
                      "isExpired returned false unconditionally, so four red warnings could never fire.")
    }

    func testExpiryFallsBackToEnrollmentWhenNoPurchaseDateWasRecorded() {
        let enrolled = Date(timeIntervalSince1970: 1_770_000_000)
        var contract = bundle(validityMonths: 1)
        contract.enrollmentDate = enrolled
        contract.bundlePurchaseDate = nil
        XCTAssertEqual(contract.expiresOn,
                       Calendar.current.date(byAdding: .month, value: 1, to: enrolled))
    }

    func testExpiryDoesNotChangeContractStatus() {
        // Deliberate: `status` gates redemption and the private-session rule.
        // Making an expired contract inactive would stop it consuming
        // sessions, which is a money decision, not a display one.
        let contract = bundle(validityMonths: 1,
                              purchased: Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertTrue(contract.isExpired())
        XCTAssertEqual(contract.status, .active)
    }

    // MARK: - The write path

    func testStoredHandoverDatesAreCarriedThroughASave() {
        // Nothing sets these any more, but contracts that have them must keep
        // them: `applyContract` hand-lists its columns.
        let dm = SwiftDataManager.inMemoryForTesting()
        let day = Date(timeIntervalSince1970: 1_770_000_000)
        var contract = bundle(validityMonths: 6)
        contract.signedDate = day
        contract.jerseyGivenDate = day
        contract.ballGivenDate = day
        dm.addContract(contract)

        contract.notes = "edited"
        dm.updateContract(contract)

        let reloaded = dm.contracts.first { $0.id == contract.id }
        XCTAssertEqual(reloaded?.signedDate, day)
        XCTAssertEqual(reloaded?.jerseyGivenDate, day)
        XCTAssertEqual(reloaded?.ballGivenDate, day)
    }

    // MARK: - Coverage guard

    /// Every stored property of `Contract` as reviewed on 2026-08-10. Mirrors
    /// SessionRoundTripTests' guard: reflection fails when the model gains a
    /// property, forcing whoever adds one to decide whether `applyContract`
    /// must carry it. Without this, a new field is simply never persisted on
    /// update and nothing notices.
    private static let reviewedProperties: Set<String> = [
        "id", "studentId", "contractNumber", "kind", "enrollmentDate",
        "pricePerSession", "bundleSize", "bundlePurchaseDate", "bundleSessionIds",
        "payments", "travelFeeAmount", "travelFeeBasis", "consents",
        "sessionMinutes", "validityMonths", "signedDate", "jerseyGivenDate",
        "ballGivenDate", "programId", "notes", "createdByCoachId",
        "manualStatus", "createdAt", "updatedAt",
    ]

    func testFixtureCoversEveryProperty() {
        let live = Set(Mirror(reflecting: bundle()).children.compactMap(\.label))
        let added = live.subtracting(Self.reviewedProperties)
        let removed = Self.reviewedProperties.subtracting(live)

        XCTAssertTrue(added.isEmpty, """
            Contract gained \(added.sorted().joined(separator: ", ")).
            Decide whether SwiftDataManager.applyContract must persist it and \
            whether SDContract needs a column, then add it here.
            """)
        XCTAssertTrue(removed.isEmpty, """
            Contract no longer has \(removed.sorted().joined(separator: ", ")).
            """)
    }
}
