import SwiftUI

// SETTING UP A TRACKED DRILL (23 Nov 2026, Luther: "annoying to set up … the
// time could only be set up to 3 minutes"). A sheet, not a menu: how it is
// scored, then the amount — shots 1–100 with quick chips, or a time on
// minute and second wheels up to 20 minutes with quick chips — then the
// drill's own option (range, how far to dribble). Saved as the drill's
// default for next time (ShootingSetup.remember). Locked once results exist
// (they would no longer compare).

struct ShootingSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drill: ShootingDrill
    let onSave: (ShootingSetup) -> Void
    @State private var draft: ShootingSetup

    init(setup: ShootingSetup, onSave: @escaping (ShootingSetup) -> Void) {
        drill = setup.drill
        self.onSave = onSave
        _draft = State(initialValue: setup)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var perSpot: Bool { drill.spotCount > 1 }

    static let shotChips = [5, 10, 15, 20, 25, 30, 50]
    static let timeChips = [30, 60, 90, 120, 180, 300, 600]
    static let maxSeconds = 20 * 60

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(draft.summary(chinese: isChinese))
                        .font(.headline)
                        .accessibilityIdentifier("shootingSetup.summary")
                } footer: {
                    Text(isChinese ? "下次加入这个训练时默认使用这一设置。"
                                   : "Used again the next time this drill is in a plan.")
                }
                Section(isChinese ? "计分方式" : "Scoring") {
                    Picker(isChinese ? "计分方式" : "Scoring", selection: $draft.mode) {
                        if drill == .shotChart {
                            Text(isChinese ? "每区命中 / 出手" : "Made / attempted").tag(ShootingMode.chart)
                            Text(isChinese ? "每区固定出手" : "Same shots each zone").tag(ShootingMode.attempts)
                        } else {
                            Text(isChinese ? "命中 / 出手" : "Made of shots").tag(ShootingMode.attempts)
                            Text(isChinese ? "限时命中" : "Makes in a time").tag(ShootingMode.timed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("shootingSetup.mode")
                }

                switch draft.mode {
                case .attempts: shotsSection
                case .timed: timeSection
                case .chart: EmptyView()
                }

                if drill == .twos {
                    Section(isChinese ? "距离" : "Range") {
                        Picker(isChinese ? "距离" : "Range", selection: $draft.range) {
                            ForEach(TwosRange.allCases, id: \.self) { Text($0.title(chinese: isChinese)).tag(Optional($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if drill == .dribbleShoot {
                    Section(isChinese ? "折返距离" : "Dribble to") {
                        Picker(isChinese ? "折返距离" : "Dribble to", selection: $draft.court) {
                            ForEach(CourtLength.allCases, id: \.self) { Text($0.title(chinese: isChinese)).tag(Optional($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

            }
            .navigationTitle(drill.title(chinese: isChinese))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") {
                        draft.remember()
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("shootingSetup.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Shots

    private var shotsSection: some View {
        Section(perSpot ? (isChinese ? (drill == .shotChart ? "每区出手" : "每点出手") : (drill == .shotChart ? "Shots a zone" : "Shots a spot"))
                        : (isChinese ? "出手数" : "Shots")) {
            Stepper(value: $draft.shots, in: 1...100) {
                Text("\(draft.shots)").font(.title2.weight(.bold)).monospacedDigit()
            }
            .accessibilityIdentifier("shootingSetup.shots")
            chips(Self.shotChips, selected: draft.shots, label: { "\($0)" }) { draft.shots = $0 }
        }
    }

    // MARK: Time

    private var timeSection: some View {
        Section(perSpot ? (isChinese ? "每点时间" : "Time a spot") : (isChinese ? "时间" : "Time")) {
            HStack(spacing: 0) {
                Picker(isChinese ? "分" : "Minutes", selection: Binding(
                    get: { draft.seconds / 60 },
                    set: { draft.seconds = Self.clamped($0 * 60 + draft.seconds % 60) })) {
                    ForEach(0...20, id: \.self) { Text(isChinese ? "\($0) 分" : "\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("shootingSetup.minutes")
                Picker(isChinese ? "秒" : "Seconds", selection: Binding(
                    get: { draft.seconds % 60 },
                    set: { draft.seconds = Self.clamped(draft.seconds / 60 * 60 + $0) })) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(isChinese ? "\($0) 秒" : "\($0) s").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("shootingSetup.seconds")
            }
            .frame(height: 140)
            chips(Self.timeChips, selected: draft.seconds, label: { ShootingSetup.time($0, chinese: isChinese) }) { draft.seconds = $0 }
        }
    }

    /// 5 s to 20 min.
    static func clamped(_ seconds: Int) -> Int { min(maxSeconds, max(5, seconds)) }

    private func chips(_ values: [Int], selected: Int, label: @escaping (Int) -> String,
                       pick: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { v in
                    Button { pick(v) } label: {
                        Text(label(v))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .background(Capsule().fill(v == selected ? Color.orange : Color(.tertiarySystemFill)))
                            .foregroundStyle(v == selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shootingSetup.chip.\(v)")
                }
            }
        }
    }
}
