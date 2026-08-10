import Foundation

// MARK: - A phase's words are DERIVED too (Phase 2.7)
//
// Phase 2.3 stopped a session's name freezing the phase title of the day it
// was generated. It named, but did not fix, the layer underneath:
//
//     "…also freezes the language the phase was created in, because FEB
//      presets resolve to one locale at instantiation."
//
// PhaseTemplate carries LocalizedTriple(en/zh/es), and `instantiate` calls
// `resolve(currentLanguage)` — flattening three languages into one stored
// string. A plan built while the app was in English is called "Pre-Season"
// forever, and after 2.3 that English leaks onward into every session name,
// the calendar, the widget and the PDFs on a phone running in Chinese.
// Switching the app language changes the chrome and leaves the coach's own
// plan speaking the wrong language.
//
// So the same move, one level up: the stored string is a LEGACY FALLBACK, and
// the displayed words are resolved against the template catalogue in the
// CURRENT language.
//
// There is no schema change and no migration. The link back to the template
// is the stored string itself: a phase's title is matched against every
// locale of every template for that program's age band. Adding a templateId
// column would be truer, but it is a CloudKit deploy plus a backfill for
// something a lookup answers exactly.
//
// TWO RULES KEEP IT HONEST:
//   · PER FIELD. A coach who keeps the preset title but rewrites the
//     objectives must keep their objectives. Each field matches — or does
//     not — on its own, and an unmatched field is returned verbatim.
//   · NEVER GUESS. No match, or more than one, returns the stored string.
//     "Pre-Season" really is two different phases in Chinese (季前适应 for
//     mini12, 季前 for infantil and senior), which is why the age band is
//     part of the lookup rather than a global title index.
enum PhaseNaming {

    /// Templates that could have produced this phase: the coach's own for the
    /// band first — those are what their programs are actually built from —
    /// then the FEB defaults.
    static func candidates(for age: AgeGroup,
                           userTemplates: [UserPhaseTemplate]) -> [PhaseTemplate] {
        let mine = userTemplates.filter { $0.ageGroup == age }.flatMap(\.phases)
        return mine + FEBPhasePresets.phases(for: age)
    }

    /// Resolves one stored string against one field of the candidates.
    ///
    /// `field` picks the slot to compare and to read back, so title,
    /// description and objectives all use one matching rule.
    static func localized(_ stored: String,
                          in candidates: [PhaseTemplate],
                          language: AppLanguage,
                          field: (PhaseTemplate) -> [LocalizedTriple]) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return stored }

        var matches: [LocalizedTriple] = []
        for template in candidates {
            for triple in field(template) where isSameText(triple, trimmed) {
                matches.append(triple)
            }
        }
        // Distinct renderings only: the same phrase appearing in two bands
        // with identical translations is not an ambiguity.
        let renderings = Set(matches.map { $0.resolve(language) })
        guard renderings.count == 1, let only = renderings.first else { return stored }
        return only
    }

    private static func isSameText(_ triple: LocalizedTriple, _ text: String) -> Bool {
        [triple.en, triple.zh, triple.es]
            .contains { !$0.isEmpty && $0.caseInsensitiveCompare(text) == .orderedSame }
    }

    // MARK: - Whole phase

    /// The phase as it should READ right now. Every field independently
    /// matched, so a coach's edits survive and the preset text follows the
    /// app's language.
    static func localized(_ phase: MicroCycle,
                          program: Program?,
                          userTemplates: [UserPhaseTemplate],
                          language: AppLanguage) -> MicroCycle {
        // Without a program there is no age band, so there is no catalogue to
        // match against and nothing may be rewritten.
        guard let age = program?.ageGroup else { return phase }
        let candidates = candidates(for: age, userTemplates: userTemplates)
        guard !candidates.isEmpty else { return phase }

        var copy = phase
        copy.title = localized(phase.title, in: candidates, language: language) { [$0.title] }
        if let description = phase.description, !description.isEmpty {
            copy.description = localized(description, in: candidates,
                                         language: language) { [$0.coachingNote] }
        }
        copy.objectives = phase.objectives.map { objective in
            localized(objective, in: candidates, language: language) { $0.objectives }
        }
        return copy
    }

    /// Whole-collection form, for the manager's cache boundary — the same
    /// wiring point Phase 2.3 used, so renaming or re-languaging happens once
    /// rather than in every view.
    static func localized(_ phases: [MicroCycle],
                          programs: [Program],
                          userTemplates: [UserPhaseTemplate],
                          language: AppLanguage) -> [MicroCycle] {
        let programsById = Dictionary(programs.map { ($0.id, $0) },
                                      uniquingKeysWith: { a, _ in a })
        return phases.map {
            localized($0, program: programsById[$0.programId],
                      userTemplates: userTemplates, language: language)
        }
    }
}
