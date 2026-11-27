import SwiftUI

/// THE LEVEL MARK (26 Nov 2026, Luther, pointing at the Mac's "● Below
/// average" pill: "also add this mark … to iPadOS and iOS"). The athlete's
/// level in their group as a small pill — the level's colour as a dot, its
/// name beside it — under the player card on the profile and in the Quick
/// Peep. For the coach only: it sits beside the card, never on it (the card
/// is what gets shared and printed).
///
/// A TAP OPENS THE PATH (27 Nov 2026, Luther: a kid asked how much he has to
/// improve to reach the next level, and the level sat "hidden perfectly
/// behind the system"): what the level is made of and what the next one
/// takes (`LevelPathSheet`). An athlete in a group that does not rank them
/// yet gets a quiet "No level yet" pill that says what is missing.
struct SkillLevelMark: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.skillLevelProgram) private var program
    let studentId: UUID
    @State private var showingPath = false

    var body: some View {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        let tier = dataManager.skillTier(for: studentId, program: program)
        if tier != nil || dataManager.levelProgram(for: studentId, preferred: program) != nil {
            Button { showingPath = true } label: {
                HStack(spacing: 7) {
                    Circle().fill(Color(hex: tier?.hex ?? PhotoPalette.unranked)).frame(width: 9, height: 9)
                    Text(tier?.title(chinese: zh) ?? (zh ? "暂无水平" : "No level yet")).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tier == nil ? .secondary : .primary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .filmGlass(.regular, in: Capsule())
                .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((zh ? "组内水平：" : "Level in the group: ")
                                + (tier?.title(chinese: zh) ?? (zh ? "暂无" : "none yet")))
            .accessibilityIdentifier("athlete.levelMark")
            .sheet(isPresented: $showingPath) {
                LevelPathSheet(studentId: studentId, preferredProgram: program)
                    .environmentObject(dataManager)
            }
        }
    }
}

/// What the level is made of, and what the next one takes.
struct LevelPathSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let studentId: UUID
    let preferredProgram: UUID?

    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var program: Program? { dataManager.levelProgram(for: studentId, preferred: preferredProgram) }
    private var skills: SkillsEvaluation? { dataManager.player(for: studentId)?.skills }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let program {
                        if let standing = dataManager.levelStanding(for: studentId, in: program) {
                            header(standing, program: program)
                            scale(standing)
                            madeOf(standing)
                            if let next = standing.next { path(standing, to: next) } else { top(standing) }
                            note
                        } else {
                            missing(program)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .filmRoomPage()
            .navigationTitle(zh ? "水平" : "Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(zh ? "完成" : "Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("level.sheet")
    }

    // MARK: Parts

    private func header(_ s: SkillLevel.Standing, program: Program) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: s.tier.hex)).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.tier.title(chinese: zh)).font(.title2.weight(.bold))
                Text(zh ? "\(program.resolvedDisplayName(in: dataManager.programs)) · \(s.ranked) 人有水平"
                        : "\(program.resolvedDisplayName(in: dataManager.programs)) · \(s.ranked) athletes ranked")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("level.header")
    }

    /// The five bands with the athlete's place on them.
    private func scale(_ s: SkillLevel.Standing) -> some View {
        let bands: [SkillTier] = [.bottom, .belowAverage, .average, .better, .best]
        // −2.5…+2.5 across the bar; each band is one point wide.
        let place = min(1, max(0, (s.delta + 2.5) / 5))
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(bands, id: \.self) { band in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: band.hex).opacity(band == s.tier ? 1 : 0.35))
                        }
                    }
                    .frame(height: 10)
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: place * geo.size.width - 7)
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            Text(zh ? "距本组平均 \(signed(s.delta)) 分"
                    : "\(signed(s.delta)) from the group's average")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func madeOf(_ s: SkillLevel.Standing) -> some View {
        card(zh ? "水平的组成" : "What the level is made of") {
            if let rating = s.rating {
                row(icon: "slider.horizontal.3",
                    title: zh ? "评估" : "Your ratings",
                    value: zh ? "平均 \(one(rating))" : "\(one(rating)) average",
                    detail: s.groupRating.map { zh ? "本组 \(one($0))" : "group \(one($0))" },
                    share: s.ratingWeight)
            }
            if let production = s.production {
                row(icon: "sportscourt",
                    title: zh ? "比赛" : "Games",
                    value: zh ? "每场 \(one(production))" : "\(one(production)) a game",
                    detail: s.groupProduction.map { zh ? "本组 \(one($0))" : "group \(one($0))" },
                    share: s.gameWeight)
                Text(zh ? "比赛值 = 进球 ×2 + 篮板 + 助攻 ×1.5 +（抢断 + 盖帽）×2，取本组近六周的比赛。"
                        : "A game counts baskets × 2 + rebounds + assists × 1.5 + (steals + blocks) × 2, over this group's games of the last six weeks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if s.rating == nil {
                Text(zh ? "还没有评估（至少评 4 项技能），目前只看比赛。"
                        : "Not rated yet (four skills or more): only games count for now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if s.production == nil {
                Text(zh ? "本组比赛不足 3 场，目前只看评估。"
                        : "Fewer than three games in this group: only the ratings count for now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func path(_ s: SkillLevel.Standing, to next: SkillTier) -> some View {
        card(zh ? "升到「\(next.title(chinese: true))」需要" : "To reach \(next.title(chinese: false))") {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: next.hex)).frame(width: 10, height: 10)
                Text(zh ? "还差 \(two(s.gap)) 分" : "\(two(s.gap)) to go")
                    .font(.headline).monospacedDigit()
            }
            .accessibilityIdentifier("level.gap")

            if let need = s.ratingNeeded, let rating = s.rating {
                let rated = DrillAttribute.allCases.filter { skills?.rating($0) != nil }.count
                let points = Int((need * Double(max(1, rated))).rounded(.up))
                route(zh ? "靠评估" : "On ratings",
                      zh ? "评估平均从 \(one(rating)) 到 \(one(rating + need))，也就是 \(rated) 项技能一共提高约 \(points) 分。"
                         : "Rating average from \(one(rating)) to \(one(rating + need)) — about \(points) rating point\(points == 1 ? "" : "s") in all across the \(rated) rated skills.")
                if let lowest = lowestSkills(), !lowest.isEmpty {
                    Text((zh ? "目前最低：" : "Lowest now: ") + lowest)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let need = s.productionNeeded, let production = s.production {
                route(zh ? "靠比赛" : "On games",
                      zh ? "每场比赛值从 \(one(production)) 到 \(one(production + need))，例如每场多进 \(half(need / 2)) 球，或多 \(half(need / 1.5)) 次助攻，或多 \(half(need / 2)) 次抢断/盖帽。"
                         : "From \(one(production)) to \(one(production + need)) a game — for example \(half(need / 2)) more basket\(need / 2 > 1.25 ? "s" : "") a game, or \(half(need / 1.5)) more assists, or \(half(need / 2)) more steals or blocks.")
            }
            if s.ratingNeeded != nil, s.productionNeeded != nil {
                Text(zh ? "两者一起提高，各需一半左右。" : "Improving both, about half of each does it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if s.ratingNeeded == nil, s.productionNeeded == nil {
                Text(zh ? "仅靠一项已到不了：需要评估和比赛一起提高。"
                        : "Neither alone can carry it that far: it takes the ratings and the games together.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let cushion = s.cushion {
                Divider()
                Text(zh ? "保持目前水平：比下一档的线高 \(two(cushion)) 分。"
                        : "To stay where they are: \(two(cushion)) above the line of the level below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func top(_ s: SkillLevel.Standing) -> some View {
        card(zh ? "已是本组最高" : "The top of this group") {
            Text(zh ? "比「最佳」的线高 \(two(s.cushion ?? 0)) 分。\(SkillTier.best.meaning(chinese: true))。"
                    : "\(two(s.cushion ?? 0)) above the line for Best. \(SkillTier.best.meaning(chinese: false)).")
                .font(.subheadline)
        }
    }

    private var note: some View {
        Text(zh ? "水平是和本组其他学员比出来的：别人进步，线也会动。这些说法只给教练看。"
                : "A level compares the athletes of this group, so the line moves when the others improve. The level names are for you, not for the athlete.")
            .font(.caption).foregroundStyle(.secondary)
    }

    /// No level: what is missing.
    private func missing(_ program: Program) -> some View {
        let members = program.enrolledStudentIds.count
        let rated = DrillAttribute.allCases.filter { skills?.rating($0) != nil }.count
        return card(zh ? "暂无水平" : "No level yet") {
            Text(program.resolvedDisplayName(in: dataManager.programs))
                .font(.subheadline).foregroundStyle(.secondary)
            if members < SkillLevel.minimumGroup {
                Text(zh ? "本组不足 \(SkillLevel.minimumGroup) 人，无法比较。"
                        : "The group has fewer than \(SkillLevel.minimumGroup) athletes — nobody to compare with.")
            } else {
                Text(zh ? "需要其中一项：" : "It takes one of these:")
                    .font(.subheadline.weight(.semibold))
                Label(zh ? "评估至少 4 项技能（已评 \(rated) 项）"
                         : "Ratings on four skills or more (\(rated) rated so far)",
                      systemImage: rated >= SkillsEvaluation.minimumRated ? "checkmark.circle.fill" : "circle")
                Label(zh ? "在本组打满 3 场比赛" : "Three games played in this group",
                      systemImage: "circle")
                Text(zh ? "并且本组至少有 \(SkillLevel.minimumGroup) 人有数据。"
                        : "And at least \(SkillLevel.minimumGroup) athletes of the group need data to be compared.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("level.missing")
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.filmCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(icon: String, title: String, value: String, detail: String?, share: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text([value, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            Text("\(Int((share * 100).rounded()))%")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(share > 0 ? .primary : .tertiary)
        }
    }

    private func route(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The two lowest rated skills, "Defense 3, Passing 4".
    private func lowestSkills() -> String? {
        guard let skills else { return nil }
        let rated = DrillAttribute.allCases.compactMap { axis in skills.rating(axis).map { (axis, $0) } }
        return rated.sorted { $0.1 < $1.1 }.prefix(2)
            .map { "\($0.0.title(chinese: zh)) \($0.1)" }.joined(separator: zh ? "、" : ", ")
    }

    private func one(_ v: Double) -> String { String(format: "%.1f", v) }
    private func two(_ v: Double) -> String { String(format: "%.2f", v) }
    private func signed(_ v: Double) -> String { (v >= 0 ? "+" : "−") + String(format: "%.2f", abs(v)) }
    /// To the nearest half, never under a half.
    private func half(_ v: Double) -> String {
        let h = max(0.5, (v * 2).rounded() / 2)
        return h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)
    }
}
