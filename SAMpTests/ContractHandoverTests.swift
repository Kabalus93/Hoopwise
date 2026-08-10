import XCTest
@testable import Hoopwise

/// Phase 2.9 — the Contract shims that lied.
///
/// `isSigned` returned `true` always. `jerseyGiven` and `ballGiven` returned
/// `false` always, and all three setters threw the write away — while
/// SalesView offered a toggle for each and called save. The coach ticked
/// "Jersey Given", the row said it saved, and the next launch showed it
/// untouched. `isExpired` returned `false` always, behind a red warning in
/// four screens that could therefore never fire.
///
/// These pin the values AND the write path: `applyContract` hand-lists its
/// columns, which is exactly how four session fields were silently dropped on
/// every save before SessionRoundTripTests existed.
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

    // MARK: - The toggles

    func testUntickedIsTheDefaultAndNothingIsAssumed() {
        let contract = bundle()
        XCTAssertFalse(contract.isSigned, "isSigned used to return true for every contract ever created.")
        XCTAssertFalse(contract.jerseyGiven)
        XCTAssertFalse(contract.ballGiven)
        XCTAssertNil(contract.signedDate)
    }

    func testTickingStampsTheDateAndUntickingClearsIt() {
        var contract = bundle()

        contract.isSigned = true
        XCTAssertTrue(contract.isSigned)
        XCTAssertNotNil(contract.signedDate, "The date is the truth; the Bool derives from it.")

        contract.isSigned = false
        XCTAssertFalse(contract.isSigned)
        XCTAssertNil(contract.signedDate)
    }

    func testRetickingKeepsTheOriginalDate() {
        var contract = bundle()
        let handover = Date(timeIntervalSince1970: 1_770_000_000)
        contract.jerseyGivenDate = handover
        contract.jerseyGiven = true
        XCTAssertEqual(contract.jerseyGivenDate, handover,
                       "Setting an already-true toggle must not restamp the day it happened.")
    }

    func testSigningNeverMovesTheEnrollmentDate() {
        // The old setter wrote enrollmentDate, and bundle revenue is
        // attributed via effectiveBundlePurchaseDate — which falls back to
        // enrollmentDate — so ticking "Contract Signed" moved revenue between
        // months.
        let enrolled = Date(timeIntervalSince1970: 1_760_000_000)
        var contract = Contract(studentId: student, kind: .privateBundle,
                                enrollmentDate: enrolled, bundleSize: 10)
        contract.isSigned = true
        XCTAssertEqual(contract.enrollmentDate, enrolled)
        XCTAssertEqual(contract.effectiveBundlePurchaseDate, enrolled)
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

    func testHandoverFactsSurviveASaveAndReload() {
        let dm = SwiftDataManager.inMemoryForTesting()
        var contract = bundle(validityMonths: 6)
        dm.addContract(contract)

        contract.isSigned = true
        contract.jerseyGiven = true
        contract.ballGiven = true
        dm.updateContract(contract)

        let reloaded = dm.contracts.first { $0.id == contract.id }
        XCTAssertEqual(reloaded?.isSigned, true, "applyContract hand-lists columns — a new field is silently dropped unless it is added there.")
        XCTAssertEqual(reloaded?.jerseyGiven, true)
        XCTAssertEqual(reloaded?.ballGiven, true)
        XCTAssertEqual(reloaded?.signedDate?.timeIntervalSince1970,
                       contract.signedDate?.timeIntervalSince1970)
    }

    func testUntickingSurvivesTooSoAMistakeCanBeUndone() {
        let dm = SwiftDataManager.inMemoryForTesting()
        var contract = bundle()
        contract.jerseyGiven = true
        dm.addContract(contract)

        contract.jerseyGiven = false
        dm.updateContract(contract)

        XCTAssertEqual(dm.contracts.first { $0.id == contract.id }?.jerseyGiven, false,
                       "Clearing has to persist as surely as setting, or a mis-tick is permanent.")
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
