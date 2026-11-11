import Foundation

// WHAT A DRILL DEVELOPS (November 2026, Luther: "give drills an attribute —
// court vision, passing, dribbling, IQ, finishing, playmaking … a hex graph
// in each drill; the session plan shows what is emphasised and what is
// neglected, and that feeds back into the program"). Eight axes, drawn as an
// octagon; every drill scores 0–3 on each (0 none · 1 touched · 2 worked ·
// 3 a main focus).
//
// Where a drill's scores come from, first match wins:
// 1. its own tags `attr:<axis>=<0-3>` — the coach's override (`attr:by:coach`)
//    or Claude's rating of a personal drill; synced with the drill, no schema
//    change;
// 2. the library's ratings (ActivityLibraryAttributes, generated once by
//    Claude from each activity's name, type, block and how it runs);
// 3. a rough guess from the drill's type or category, so nothing is blank.

enum DrillAttribute: String, CaseIterable, Codable, Identifiable {
    case ballHandling, passing, shooting, finishing, playmaking, gameIQ, defense, footwork

    var id: String { rawValue }

    var title: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .ballHandling: return zh ? "控球" : "Ball handling"
        case .passing: return zh ? "传球" : "Passing"
        case .shooting: return zh ? "投篮" : "Shooting"
        case .finishing: return zh ? "终结" : "Finishing"
        case .playmaking: return zh ? "组织" : "Playmaking"
        case .gameIQ: return zh ? "球商与视野" : "Game IQ & vision"
        case .defense: return zh ? "防守" : "Defense"
        case .footwork: return zh ? "步法与运动能力" : "Footwork & athleticism"
        }
    }

    /// Short label for the octagon's corners.
    var short: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .ballHandling: return zh ? "控球" : "Handle"
        case .passing: return zh ? "传球" : "Pass"
        case .shooting: return zh ? "投篮" : "Shoot"
        case .finishing: return zh ? "终结" : "Finish"
        case .playmaking: return zh ? "组织" : "Create"
        case .gameIQ: return zh ? "球商" : "IQ"
        case .defense: return zh ? "防守" : "Defend"
        case .footwork: return zh ? "步法" : "Move"
        }
    }

    var icon: String {
        switch self {
        case .ballHandling: return "basketball"
        case .passing: return "arrow.left.arrow.right"
        case .shooting: return "target"
        case .finishing: return "arrow.up.forward.circle"
        case .playmaking: return "wand.and.stars"
        case .gameIQ: return "brain.head.profile"
        case .defense: return "shield.lefthalf.filled"
        case .footwork: return "figure.run"
        }
    }

    /// What each axis means — the rubric Claude rates against, and the
    /// drill page's explanation.
    static let rubric = """
    ballHandling: dribbling, protecting the ball, changes of direction with the ball.
    passing: passing technique, timing and catching.
    shooting: set and jump shots, free throws, shooting form.
    finishing: lay-ups and scoring at the rim, through contact.
    playmaking: creating for others — drive and kick, reading help, making the pass that leads to a score.
    gameIQ: decisions, spacing, reading the defence and the play, knowing the rules (court vision).
    defense: on-ball and help defence, closing out, rebounding position, steals.
    footwork: stops, pivots, coordination, agility, running and jumping (athleticism).
    """
}

/// A drill's eight scores, 0…3 each.
struct AttributeProfile: Equatable, Codable {
    var scores: [DrillAttribute: Int] = [:]

    subscript(_ axis: DrillAttribute) -> Int {
        get { scores[axis] ?? 0 }
        set { scores[axis] = max(0, min(3, newValue)) }
    }

    init(scores: [DrillAttribute: Int] = [:]) { self.scores = scores.mapValues { max(0, min(3, $0)) } }

    /// The eight scores in `DrillAttribute.allCases` order (the generated
    /// library data's shape).
    init(array: [Int]) {
        var s: [DrillAttribute: Int] = [:]
        for (axis, value) in zip(DrillAttribute.allCases, array) { s[axis] = value }
        self.init(scores: s)
    }

    var array: [Int] { DrillAttribute.allCases.map { self[$0] } }
    var isEmpty: Bool { scores.values.allSatisfy { $0 == 0 } }

    /// The axes it works most, strongest first (score ≥ 2).
    var main: [DrillAttribute] {
        DrillAttribute.allCases.filter { self[$0] >= 2 }.sorted { self[$0] > self[$1] }
    }

    // MARK: Tags

    static let tagPrefix = "attr:"
    static let coachTag = "attr:by:coach"

    init?(tags: [String]) {
        var s: [DrillAttribute: Int] = [:]
        for tag in tags where tag.hasPrefix(Self.tagPrefix) {
            let body = tag.dropFirst(Self.tagPrefix.count)
            let parts = body.split(separator: "=")
            guard parts.count == 2, let axis = DrillAttribute(rawValue: String(parts[0])), let v = Int(parts[1]) else { continue }
            s[axis] = v
        }
        guard !s.isEmpty else { return nil }
        self.init(scores: s)
    }

    /// The tags for this profile, with or without the coach mark.
    func tags(byCoach: Bool) -> [String] {
        DrillAttribute.allCases.map { "\(Self.tagPrefix)\($0.rawValue)=\(self[$0])" } + (byCoach ? [Self.coachTag] : [])
    }

    /// `tags` with every attr tag replaced by this profile's.
    func replacing(in tags: [String], byCoach: Bool) -> [String] {
        tags.filter { !$0.hasPrefix(Self.tagPrefix) } + self.tags(byCoach: byCoach)
    }

    // MARK: A rough guess, when nothing has rated the drill

    static func guess(type: ActivityType?, category: DrillCategory) -> AttributeProfile {
        var p = AttributeProfile()
        switch type {
        case .warmup: p[.footwork] = 3; p[.ballHandling] = 1
        case .ballMovement: p[.ballHandling] = 2; p[.footwork] = 2
        case .dribbling: p[.ballHandling] = 3; p[.footwork] = 1
        case .passing: p[.passing] = 3; p[.gameIQ] = 1
        case .footwork: p[.footwork] = 3; p[.ballHandling] = 1
        case .layups: p[.finishing] = 3; p[.footwork] = 2
        case .shooting: p[.shooting] = 3; p[.footwork] = 1
        case .rebounding: p[.defense] = 2; p[.footwork] = 2
        case .oneOnOne: p[.ballHandling] = 2; p[.defense] = 2; p[.finishing] = 2; p[.gameIQ] = 1
        case .defence: p[.defense] = 3; p[.footwork] = 2
        case .teamPlay: p[.gameIQ] = 3; p[.passing] = 2; p[.playmaking] = 2
        case .post: p[.finishing] = 2; p[.footwork] = 2
        case .guards: p[.ballHandling] = 2; p[.playmaking] = 2
        case .games: p[.gameIQ] = 2; p[.passing] = 1; p[.defense] = 1
        case .rules, .none:
            switch category {
            case .shooting: p[.shooting] = 3
            case .defense: p[.defense] = 3; p[.footwork] = 1
            case .offense: p[.gameIQ] = 2; p[.passing] = 2; p[.playmaking] = 1
            case .conditioning, .warmup, .cooldown: p[.footwork] = 3
            case .skills: p[.ballHandling] = 2; p[.passing] = 1
            }
        }
        return p
    }

    // MARK: The other vocabularies, on the same eight axes

    /// A phase focus as axis weights.
    static func weights(for focus: TrainingFocus) -> [DrillAttribute: Double] {
        switch focus {
        case .shooting: return [.shooting: 1, .finishing: 0.5]
        case .ballHandling: return [.ballHandling: 1, .footwork: 0.3]
        case .passing: return [.passing: 1, .playmaking: 0.5]
        case .defense: return [.defense: 1, .footwork: 0.3]
        case .conditioning: return [.footwork: 1]
        case .teamPlay: return [.gameIQ: 1, .playmaking: 0.6, .passing: 0.4]
        case .gamePrep: return [.gameIQ: 1, .defense: 0.5, .playmaking: 0.5]
        case .recovery: return [:]
        }
    }

    /// A drill-library skill (`ActivityType` raw value — the team play
    /// breakdowns' skills) as axis weights.
    static func weights(forSkill skill: String) -> [DrillAttribute: Double] {
        guard let type = ActivityType(rawValue: skill) else { return [:] }
        return guess(type: type, category: .skills).scores.mapValues { Double($0) / 3 }
    }
}

extension DrillItem {
    /// What this drill develops — its own tags, else the library's rating,
    /// else a guess from its type or category.
    var attributes: AttributeProfile {
        if let own = AttributeProfile(tags: tags) { return own }
        if let activity = libraryActivity, let rated = ActivityLibraryAttributes.ratings[activity.key] {
            return AttributeProfile(array: rated)
        }
        return AttributeProfile.guess(type: libraryActivity?.type, category: category)
    }

    /// Where the scores come from, for the drill page's footnote.
    var attributesSource: AttributesSource {
        if AttributeProfile(tags: tags) != nil { return tags.contains(AttributeProfile.coachTag) ? .coach : .claude }
        if let activity = libraryActivity, ActivityLibraryAttributes.ratings[activity.key] != nil { return .claude }
        return .guess
    }

    enum AttributesSource { case coach, claude, guess }
}
