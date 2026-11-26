import XCTest
@testable import Hoopwise

/// The batch background removal keeps each original so it can be put back
/// (26 Nov 2026, Luther: "too high risk, I still want to be able to undo").
@MainActor
final class PhotoBatchUndoTests: XCTestCase {

    private func student(photo: Data?) -> Student {
        var s = Student(name: "Test \(UUID().uuidString.prefix(4))")
        s.profileImageData = photo
        return s
    }

    func testTheOriginalIsKeptAndComesBackOnlyWhileThePhotoIsStillTheCutOut() {
        let original = Data("the original photo".utf8)
        let cutout = Data("the cut-out".utf8)
        var athlete = student(photo: original)
        defer { ProfileBackgroundBatch.forgetOriginal(for: athlete.id) }

        XCTAssertTrue(ProfileBackgroundBatch.restorable(in: [athlete]).isEmpty, "nothing kept yet")
        XCTAssertTrue(ProfileBackgroundBatch.keepOriginal(original, cutout: cutout, for: athlete.id))

        XCTAssertTrue(ProfileBackgroundBatch.restorable(in: [athlete]).isEmpty,
                      "the photo is still the original — there is nothing to put back")
        athlete.profileImageData = cutout
        XCTAssertEqual(ProfileBackgroundBatch.restorable(in: [athlete]).map(\.id), [athlete.id])
        XCTAssertEqual(ProfileBackgroundBatch.original(for: athlete.id), original, "byte for byte")

        // Retaken since: an older original must never replace a newer photo.
        athlete.profileImageData = Data("a photo taken later".utf8)
        XCTAssertTrue(ProfileBackgroundBatch.restorable(in: [athlete]).isEmpty)
    }

    func testAPutBackOriginalIsForgotten() {
        let cutout = Data("cut".utf8)
        var athlete = student(photo: cutout)
        XCTAssertTrue(ProfileBackgroundBatch.keepOriginal(Data("orig".utf8), cutout: cutout, for: athlete.id))
        XCTAssertEqual(ProfileBackgroundBatch.restorable(in: [athlete]).count, 1)
        ProfileBackgroundBatch.forgetOriginal(for: athlete.id)
        XCTAssertNil(ProfileBackgroundBatch.original(for: athlete.id))
        athlete.profileImageData = cutout
        XCTAssertTrue(ProfileBackgroundBatch.restorable(in: [athlete]).isEmpty)
    }

    func testOnlyPhotosThatStillHaveABackgroundAreCandidates() {
        XCTAssertTrue(ProfileBackgroundBatch.candidates(in: [student(photo: nil)]).isEmpty, "no photo, no work")
        let opaque = student(photo: Data("not an image at all".utf8))
        XCTAssertEqual(ProfileBackgroundBatch.candidates(in: [opaque]).count, 1,
                       "anything that is not a transparent cut-out counts as still having its background")
    }
}
