import XCTest
@testable import Hoopwise

/// Phase 2.7. A phase built while the app was in English is stored as
/// "Pre-Season" forever, and after 2.3 that English leaks onward into every
/// session name, the calendar and the widget on a phone running in Chinese.
///
/// The stored column keeps whatever locale it was written in; these pin what
/// the app READS, and — just as importantly — what it refuses to rewrite.
@MainActor
final class PhaseNamingTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!

    private func program(_ age: AgeGroup) -> Program {
        Program(id: programId, name: "Test", ageGroup: age)
    }

    private func phase(_ title: String,
                       description: String? = nil,
                       objectives: [String] = []) -> MicroCycle {
        MicroCycle(programId: programId, phaseNumber: 1, title: title,
                   description: description, objectives: objectives)
    }

    private func localized(_ phase: MicroCycle,
                           _ program: Program?,
                           _ language: AppLanguage,
                           templates: [UserPhaseTemplate] = []) -> MicroCycle {
        PhaseNaming.localized(phase, program: program,
                              userTemplates: templates, language: language)
    }

    // MARK: - The leak this closes

    func testAnEnglishPresetTitleReadsInChinese() {
        // "Foundations" is mini10's first phase.
        let result = localized(phase("Foundations"), program(.u10), .chinese)
        XCTAssertEqual(result.title, "基础阶段")
    }

    func testAChinesePresetTitleReadsInEnglish() {
        let result = localized(phase("基础阶段"), program(.u10), .english)
        XCTAssertEqual(result.title, "Foundations")
    }

    func testTheSameTitleResolvesPerAgeBand() {
        // "Pre-Season" is a different phase in Chinese depending on the band —
        // which is why the lookup is scoped to the program's age group rather
        // than a global index of titles.
        XCTAssertEqual(localized(phase("Pre-Season"), program(.u12), .chinese).title, "季前适应")
        XCTAssertEqual(localized(phase("Pre-Season"), program(.u14), .chinese).title, "季前")
    }

    func testSpanishResolvesToo() {
        XCTAssertEqual(localized(phase("Foundations"), program(.u10), .spanish).title, "Fundamentos")
    }

    // MARK: - What it must never rewrite

    func testACoachAuthoredTitleIsLeftAlone() {
        let result = localized(phase("Frank's summer block"), program(.u10), .chinese)
        XCTAssertEqual(result.title, "Frank's summer block",
                       "Only preset text is derived. The coach's own words are theirs.")
    }

    func testAPhaseWithNoProgramIsNotTouched() {
        let result = localized(phase("Foundations"), nil, .chinese)
        XCTAssertEqual(result.title, "Foundations",
                       "No program means no age band, so there is no catalogue to match against.")
    }

    func testEditedObjectivesSurviveALocalizedTitle() {
        // The coach kept the preset title and rewrote the objectives. Matching
        // is per FIELD, so the title follows the language and their words stay.
        let result = localized(phase("Foundations", objectives: ["Fix Mason's left hand"]),
                               program(.u10), .chinese)
        XCTAssertEqual(result.title, "基础阶段")
        XCTAssertEqual(result.objectives, ["Fix Mason's left hand"])
    }

    // MARK: - Coach-authored templates

    func testACoachTemplateIsMatchedToo() {
        let template = UserPhaseTemplate(
            name: "My U10", ageGroup: .u10,
            phases: [PhaseTemplate(
                title: LocalizedTriple(en: "Ball Camp", zh: "篮球营", es: "Campus"),
                weeks: 2, focus: [.shooting], intensity: 5, volume: 5)])

        let result = localized(phase("Ball Camp"), program(.u10), .chinese, templates: [template])
        XCTAssertEqual(result.title, "篮球营",
                       "A coach's own template is what their programs are actually built from.")
    }

    func testATemplateForAnotherBandDoesNotMatch() {
        let template = UserPhaseTemplate(
            name: "My U16", ageGroup: .u16,
            phases: [PhaseTemplate(
                title: LocalizedTriple(en: "Ball Camp", zh: "篮球营", es: "Campus"),
                weeks: 2, focus: [.shooting], intensity: 5, volume: 5)])

        let result = localized(phase("Ball Camp"), program(.u10), .chinese, templates: [template])
        XCTAssertEqual(result.title, "Ball Camp")
    }

    // MARK: - Ambiguity

    func testAmbiguousMatchesKeepTheStoredString() {
        // Two candidates for the same band with DIFFERENT translations: the
        // right answer is unknowable, so nothing is rewritten.
        let a = UserPhaseTemplate(
            name: "A", ageGroup: .u10,
            phases: [PhaseTemplate(title: LocalizedTriple(en: "Block", zh: "甲", es: ""),
                                   weeks: 1, focus: [], intensity: 5, volume: 5)])
        let b = UserPhaseTemplate(
            name: "B", ageGroup: .u10,
            phases: [PhaseTemplate(title: LocalizedTriple(en: "Block", zh: "乙", es: ""),
                                   weeks: 1, focus: [], intensity: 5, volume: 5)])

        let result = localized(phase("Block"), program(.u10), .chinese, templates: [a, b])
        XCTAssertEqual(result.title, "Block", "Never guess between two translations.")
    }

    func testDuplicateTemplatesWithTheSameTranslationAreNotAmbiguous() {
        let a = UserPhaseTemplate(
            name: "A", ageGroup: .u10,
            phases: [PhaseTemplate(title: LocalizedTriple(en: "Block", zh: "同", es: ""),
                                   weeks: 1, focus: [], intensity: 5, volume: 5)])
        let b = UserPhaseTemplate(
            name: "B", ageGroup: .u10,
            phases: [PhaseTemplate(title: LocalizedTriple(en: "Block", zh: "同", es: ""),
                                   weeks: 1, focus: [], intensity: 5, volume: 5)])

        let result = localized(phase("Block"), program(.u10), .chinese, templates: [a, b])
        XCTAssertEqual(result.title, "同", "One rendering is one answer, however many rows produced it.")
    }

    // MARK: - The layer above

    func testDerivedSessionNamesFollowTheLanguage() {
        // 2.3 derives "<phase> · Session N of M" from the phase title, which is
        // exactly how a frozen English phase leaked onward.
        let localizedPhase = localized(phase("Foundations"), program(.u10), .chinese)
        let start = Date(timeIntervalSince1970: 1_777_000_000)
        let session = SessionEvent(microCycleId: localizedPhase.id, programId: programId,
                                   title: "", date: start, startTime: start,
                                   endTime: start.addingTimeInterval(5400))

        let name = SessionNaming.name(for: session,
                                      programs: [program(.u10)],
                                      phases: [localizedPhase],
                                      allSessions: [session],
                                      style: .planFirst)
        XCTAssertTrue(name.hasPrefix("基础阶段"), "Got \(name)")
    }
}
