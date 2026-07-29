import Foundation

// MARK: - Localized Triple
/// Three-locale string slot. Falls back to English when the requested locale is missing.
struct LocalizedTriple: Codable, Hashable {
    var en: String
    var zh: String
    var es: String

    @MainActor
    func resolve() -> String {
        resolve(LocalizationManager.shared.currentLanguage)
    }

    func resolve(_ language: AppLanguage) -> String {
        switch language {
        case .english: return en
        case .chinese: return zh.isEmpty ? en : zh
        case .spanish: return es.isEmpty ? en : es
        }
    }
}

// MARK: - Phase Template
/// Periodisation building block. Resolves to a `MicroCycle` when applied to a
/// program; consumed by `AddPhaseOnboardingView`, the "Generate phases"
/// affordance on phase-less programs, and the editable Settings library.
struct PhaseTemplate: Codable, Hashable, Identifiable {
    var id: UUID
    var title: LocalizedTriple
    var weeks: Int
    var focus: [TrainingFocus]
    var intensity: Int
    var volume: Int
    var objectives: [LocalizedTriple]
    var coachingNote: LocalizedTriple

    init(id: UUID = UUID(),
         title: LocalizedTriple,
         weeks: Int,
         focus: [TrainingFocus],
         intensity: Int,
         volume: Int,
         objectives: [LocalizedTriple] = [],
         coachingNote: LocalizedTriple = LocalizedTriple(en: "", zh: "", es: "")) {
        self.id = id
        self.title = title
        self.weeks = weeks
        self.focus = focus
        self.intensity = intensity
        self.volume = volume
        self.objectives = objectives
        self.coachingNote = coachingNote
    }

    /// Materialise this template as a `MicroCycle` ready for `dataManager.addMicroCycle(_:)`.
    @MainActor
    func instantiate(programId: UUID, phaseNumber: Int, startingOn startDate: Date? = nil,
                     suggestedDrillIds: [UUID] = []) -> MicroCycle {
        let lang = LocalizationManager.shared.currentLanguage
        let endDate = startDate.flatMap {
            Calendar.current.date(byAdding: .day, value: weeks * 7, to: $0)
        }
        let note = coachingNote.resolve(lang)
        return MicroCycle(
            programId: programId,
            phaseNumber: phaseNumber,
            title: title.resolve(lang),
            focus: focus,
            durationWeeks: weeks,
            description: note.isEmpty ? nil : note,
            objectives: objectives.map { $0.resolve(lang) },
            suggestedDrillIds: suggestedDrillIds,
            startDate: startDate,
            endDate: endDate,
            intensity: intensity,
            volume: volume
        )
    }
}

// MARK: - User-authored template collection
/// A coach-authored bundle of phases tied to an age group. Stored via
/// `PhaseTemplateStore` and editable in Settings. Falls back to FEB defaults
/// per `FEBPhasePresets.phases(for:)` when the coach hasn't authored one.
struct UserPhaseTemplate: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var ageGroup: AgeGroup
    var phases: [PhaseTemplate]
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, ageGroup: AgeGroup,
         phases: [PhaseTemplate], updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.ageGroup = ageGroup
        self.phases = phases
        self.updatedAt = updatedAt
    }
}

// MARK: - FEB Phase Presets
/// Federación de Baloncesto de Madrid / Federación Española de Baloncesto
/// macro-cycle defaults. Each age group gets a season-shaped chain of phases
/// following the canonical Spanish progression:
/// `adaptación → técnica individual → táctica → competición → recuperación`.
///
/// These are *defaults* — the coach can override them in Settings or edit
/// per-phase during onboarding. Encoded with full EN/ZH/ES strings so the
/// labels read natively in Spanish on Spanish-locale devices.
enum FEBPhasePresets {

    /// Canonical phase chain for a given age group.
    static func phases(for age: AgeGroup) -> [PhaseTemplate] {
        switch age {
        case .u6, .u8:    return prePreMini
        case .u10:        return mini10
        case .u12:        return mini12
        case .u14:        return infantil
        case .u16:        return cadete
        case .u18:        return junior
        case .adult:      return senior
        }
    }

    /// Objective placeholder suggestions for the phase-onboarding objectives
    /// step. Tailored by age × the focus tags the coach picked. Returns up to
    /// six bullets the coach can tap-to-insert.
    static func objectiveSuggestions(for age: AgeGroup, focus: [TrainingFocus]) -> [LocalizedTriple] {
        var bag: [LocalizedTriple] = []
        let f = Set(focus)

        if f.contains(.shooting) {
            bag.append(LocalizedTriple(
                en: "Lock in form: BEEF (Balance, Eyes, Elbow, Follow-through)",
                zh: "投篮姿势 BEEF：平衡 / 视线 / 肘部 / 随挥",
                es: "Mecánica BEEF: equilibrio, mirada, codo, acompañamiento"))
        }
        if f.contains(.ballHandling) {
            bag.append(LocalizedTriple(
                en: "Two-ball dribbling at game speed, 3 sets × 30s",
                zh: "双球运球（比赛节奏），3 组 × 30 秒",
                es: "Bote de dos balones a ritmo de partido, 3×30s"))
        }
        if f.contains(.defense) && (age == .u14 || age == .u16 || age == .u18 || age == .adult) {
            bag.append(LocalizedTriple(
                en: "Help-side rotation on every drive — verbal cues required",
                zh: "每次突破均触发协防轮转，必须出声沟通",
                es: "Rotación de ayuda en toda penetración — comunicación obligatoria"))
        }
        if f.contains(.passing) {
            bag.append(LocalizedTriple(
                en: "Crisp two-handed chest pass under pressure",
                zh: "压力下的双手胸前传球",
                es: "Pase de pecho con dos manos bajo presión"))
        }
        if f.contains(.teamPlay) {
            switch age {
            case .u6, .u8, .u10:
                bag.append(LocalizedTriple(
                    en: "Spacing: stay 3 big steps from the next player",
                    zh: "间距：与队友保持三大步距离",
                    es: "Espaciado: mantén tres pasos grandes con el compañero"))
            case .u12, .u14:
                bag.append(LocalizedTriple(
                    en: "Give-and-go reads on the wing",
                    zh: "侧翼传切配合的判断",
                    es: "Lectura de pasa y va en alero"))
            case .u16, .u18, .adult:
                bag.append(LocalizedTriple(
                    en: "Pick-and-roll: read the big's coverage (drop, hedge, switch)",
                    zh: "挡拆阅读大个防守（退守 / 延误 / 换防）",
                    es: "Bloqueo directo: leer la defensa del cinco (drop, hedge, cambio)"))
            }
        }
        if f.contains(.conditioning) {
            bag.append(LocalizedTriple(
                en: "Suicide drill — under 28 seconds, 4 sets",
                zh: "全场折返跑 28 秒以内 × 4 组",
                es: "Suicidios en menos de 28 s, 4 series"))
        }
        if f.contains(.gamePrep) {
            bag.append(LocalizedTriple(
                en: "Walk through opponent's top 2 sets and ATOs",
                zh: "走演对手两个主战术与暂停后战术",
                es: "Repasar dos jugadas principales y los ATOs del rival"))
        }
        if f.contains(.recovery) {
            bag.append(LocalizedTriple(
                en: "Light shooting + mobility, 30 minutes max",
                zh: "轻投篮加柔韧训练，最多 30 分钟",
                es: "Tiro suave + movilidad, máximo 30 minutos"))
        }
        return Array(bag.prefix(6))
    }

    // MARK: - Recipes

    private static let prePreMini: [PhaseTemplate] = [
        PhaseTemplate(
            title: LocalizedTriple(en: "Movement & Coordination", zh: "动作协调", es: "Movimiento y coordinación"),
            weeks: 3,
            focus: [.ballHandling, .conditioning],
            intensity: 3, volume: 5,
            objectives: [
                LocalizedTriple(en: "Run, jump, change direction with confidence",
                                zh: "自信地跑、跳与变向",
                                es: "Correr, saltar y cambiar de dirección con confianza")
            ],
            coachingNote: LocalizedTriple(
                en: "ABC: agility, balance, coordination. Keep the ball secondary.",
                zh: "ABC 原则：敏捷、平衡、协调。球放次要。",
                es: "ABC: agilidad, balance, coordinación. El balón es secundario.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "Ball Friendship", zh: "认识篮球", es: "Amistad con el balón"),
            weeks: 3,
            focus: [.ballHandling, .passing],
            intensity: 4, volume: 5,
            objectives: [
                LocalizedTriple(en: "Comfortable dribbling at a jog",
                                zh: "慢跑中能稳运球",
                                es: "Botar al trote con seguridad")
            ],
            coachingNote: LocalizedTriple(
                en: "Build confidence with the ball at speed.",
                zh: "在节奏中建立持球信心。",
                es: "Construir confianza con el balón en movimiento.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "Mini-Game Discovery", zh: "迷你比赛体验", es: "Descubrir el mini-juego"),
            weeks: 2,
            focus: [.teamPlay, .gamePrep],
            intensity: 4, volume: 4,
            objectives: [
                LocalizedTriple(en: "3v3 half-court games, no zones",
                                zh: "半场 3v3，不打区域",
                                es: "3v3 a media pista, sin zonas")
            ],
            coachingNote: LocalizedTriple(
                en: "Fun first. Score every play.",
                zh: "趣味优先，每球都得分。",
                es: "La diversión primero. Anota cada jugada."))
    ]

    private static let mini10: [PhaseTemplate] = [
        PhaseTemplate(
            title: LocalizedTriple(en: "Foundations", zh: "基础阶段", es: "Fundamentos"),
            weeks: 3,
            focus: [.ballHandling, .passing],
            intensity: 4, volume: 6),
        PhaseTemplate(
            title: LocalizedTriple(en: "Shooting Form", zh: "投篮姿势", es: "Mecánica de tiro"),
            weeks: 3,
            focus: [.shooting],
            intensity: 5, volume: 6,
            coachingNote: LocalizedTriple(
                en: "Mechanics over distance.",
                zh: "动作优先于距离。",
                es: "Mecánica antes que distancia.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "1v1 Concepts", zh: "1v1 概念", es: "Conceptos del 1c1"),
            weeks: 2,
            focus: [.ballHandling, .defense],
            intensity: 6, volume: 5),
        PhaseTemplate(
            title: LocalizedTriple(en: "Mini-Tournament Prep", zh: "迷你联赛准备", es: "Preparación al mini-torneo"),
            weeks: 2,
            focus: [.teamPlay, .gamePrep],
            intensity: 6, volume: 5)
    ]

    private static let mini12: [PhaseTemplate] = [
        PhaseTemplate(
            title: LocalizedTriple(en: "Pre-Season", zh: "季前适应", es: "Adaptación"),
            weeks: 2,
            focus: [.conditioning, .ballHandling],
            intensity: 4, volume: 7),
        PhaseTemplate(
            title: LocalizedTriple(en: "Individual Technical", zh: "个人技术", es: "Técnica individual"),
            weeks: 4,
            focus: [.shooting, .ballHandling],
            intensity: 6, volume: 7),
        PhaseTemplate(
            title: LocalizedTriple(en: "1v1 Offense / Defense", zh: "1v1 攻防", es: "1c1 ofensivo y defensivo"),
            weeks: 3,
            focus: [.defense, .ballHandling],
            intensity: 7, volume: 6),
        PhaseTemplate(
            title: LocalizedTriple(en: "Tactical Introduction", zh: "战术启蒙", es: "Iniciación táctica"),
            weeks: 3,
            focus: [.passing, .teamPlay],
            intensity: 6, volume: 6,
            coachingNote: LocalizedTriple(
                en: "Spacing, give-and-go, basic screens.",
                zh: "空间、传切、基础掩护。",
                es: "Espaciado, pasa y va, bloqueos básicos.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "Competition", zh: "比赛阶段", es: "Competición"),
            weeks: 2,
            focus: [.gamePrep, .teamPlay],
            intensity: 7, volume: 5)
    ]

    private static let infantil: [PhaseTemplate] = [
        PhaseTemplate(
            title: LocalizedTriple(en: "Pre-Season", zh: "季前", es: "Pretemporada"),
            weeks: 2,
            focus: [.conditioning, .ballHandling],
            intensity: 5, volume: 7),
        PhaseTemplate(
            title: LocalizedTriple(en: "Advanced Technique", zh: "进阶技术", es: "Técnica avanzada"),
            weeks: 4,
            focus: [.shooting, .ballHandling, .passing],
            intensity: 6, volume: 7),
        PhaseTemplate(
            title: LocalizedTriple(en: "Defensive Reads", zh: "防守阅读", es: "Lectura defensiva"),
            weeks: 3,
            focus: [.defense, .teamPlay],
            intensity: 7, volume: 6,
            coachingNote: LocalizedTriple(
                en: "Help-side, closeouts, basic switches.",
                zh: "弱侧协防、补防、简单换防。",
                es: "Ayuda, recuperación al tirador, cambios básicos.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "Team Concepts", zh: "团队战术", es: "Conceptos colectivos"),
            weeks: 3,
            focus: [.teamPlay, .passing],
            intensity: 7, volume: 6,
            coachingNote: LocalizedTriple(
                en: "Pick-and-roll intro, motion offense.",
                zh: "挡拆入门，移动进攻。",
                es: "Introducción al BD y al juego en movimiento.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "Competition & Review", zh: "比赛与评估", es: "Competición y evaluación"),
            weeks: 2,
            focus: [.gamePrep, .recovery],
            intensity: 8, volume: 5)
    ]

    private static let cadete: [PhaseTemplate] = [
        PhaseTemplate(
            title: LocalizedTriple(en: "Physical Pre-Season", zh: "体能季前", es: "Pretemporada física"),
            weeks: 3,
            focus: [.conditioning],
            intensity: 5, volume: 8),
        PhaseTemplate(
            title: LocalizedTriple(en: "Technical Block", zh: "技术阶段", es: "Bloque técnico"),
            weeks: 3,
            focus: [.shooting, .ballHandling],
            intensity: 6, volume: 7),
        PhaseTemplate(
            title: LocalizedTriple(en: "Offensive Systems", zh: "进攻体系", es: "Sistemas ofensivos"),
            weeks: 4,
            focus: [.teamPlay, .passing],
            intensity: 7, volume: 6,
            coachingNote: LocalizedTriple(
                en: "Motion, P&R reads, transition rules.",
                zh: "移动进攻 / 挡拆判断 / 转换规则。",
                es: "Motion, lectura del BD, reglas de contraataque.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "Defensive Systems", zh: "防守体系", es: "Sistemas defensivos"),
            weeks: 3,
            focus: [.defense, .teamPlay],
            intensity: 7, volume: 6,
            coachingNote: LocalizedTriple(
                en: "Man, zone variants, press break.",
                zh: "人盯人 / 区域变化 / 破紧逼。",
                es: "Individual, variantes de zona, ruptura de presión.")),
        PhaseTemplate(
            title: LocalizedTriple(en: "Competition", zh: "比赛阶段", es: "Periodo competitivo"),
            weeks: 4,
            focus: [.gamePrep, .teamPlay],
            intensity: 8, volume: 5),
        PhaseTemplate(
            title: LocalizedTriple(en: "Transition / Recovery", zh: "过渡 / 恢复", es: "Transición / recuperación"),
            weeks: 1,
            focus: [.recovery],
            intensity: 3, volume: 3)
    ]

    private static let junior: [PhaseTemplate] = [
        PhaseTemplate(
            title: LocalizedTriple(en: "Strength & Conditioning Base", zh: "力量与体能基础", es: "Base de fuerza y condición"),
            weeks: 3,
            focus: [.conditioning],
            intensity: 6, volume: 8),
        PhaseTemplate(
            title: LocalizedTriple(en: "Technical Refinement", zh: "技术精修", es: "Refinamiento técnico"),
            weeks: 3,
            focus: [.shooting, .ballHandling],
            intensity: 7, volume: 7),
        PhaseTemplate(
            title: LocalizedTriple(en: "Advanced Offensive Systems", zh: "进阶进攻体系", es: "Sistemas ofensivos avanzados"),
            weeks: 4,
            focus: [.teamPlay, .passing],
            intensity: 8, volume: 6),
        PhaseTemplate(
            title: LocalizedTriple(en: "Advanced Defensive Systems", zh: "进阶防守体系", es: "Sistemas defensivos avanzados"),
            weeks: 3,
            focus: [.defense, .teamPlay],
            intensity: 8, volume: 6),
        PhaseTemplate(
            title: LocalizedTriple(en: "Competitive Peak", zh: "比赛巅峰", es: "Pico competitivo"),
            weeks: 4,
            focus: [.gamePrep, .teamPlay],
            intensity: 9, volume: 5),
        PhaseTemplate(
            title: LocalizedTriple(en: "Off-Season", zh: "休赛期", es: "Off-season"),
            weeks: 2,
            focus: [.recovery, .ballHandling],
            intensity: 4, volume: 5)
    ]

    private static let senior: [PhaseTemplate] = [
        PhaseTemplate(
            title: LocalizedTriple(en: "Pre-Season", zh: "季前", es: "Pretemporada"),
            weeks: 4,
            focus: [.conditioning],
            intensity: 5, volume: 8),
        PhaseTemplate(
            title: LocalizedTriple(en: "Skill Development", zh: "技能发展", es: "Desarrollo de habilidades"),
            weeks: 4,
            focus: [.shooting, .ballHandling, .defense],
            intensity: 7, volume: 7),
        PhaseTemplate(
            title: LocalizedTriple(en: "Tactical Integration", zh: "战术整合", es: "Integración táctica"),
            weeks: 4,
            focus: [.teamPlay, .passing],
            intensity: 8, volume: 6),
        PhaseTemplate(
            title: LocalizedTriple(en: "In-Season Maintenance", zh: "赛季维持", es: "Mantenimiento competitivo"),
            weeks: 8,
            focus: [.gamePrep],
            intensity: 8, volume: 5),
        PhaseTemplate(
            title: LocalizedTriple(en: "Off-Season", zh: "休赛期", es: "Off-season"),
            weeks: 2,
            focus: [.recovery],
            intensity: 3, volume: 4)
    ]
}
