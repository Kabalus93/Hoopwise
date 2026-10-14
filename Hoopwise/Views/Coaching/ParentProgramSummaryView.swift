import SwiftUI
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Parent Program Guide
//
// October 2026 (Luther's request, a sanctioned exception to the iOS UI
// freeze — see CLAUDE.md): the old "Parent Notice" was a screenshot of a
// dark in-app card, fixed at 380×750, with generic copy. It is replaced by
// ProgramGuideDocument — a real document rendered from the program's data —
// and this screen, which previews it, lets the coach edit the parent-facing
// wording, and shares it as an A4 PDF or a long image for WeChat.
//
// The type keeps its old name and initializer so the call site in
// FlightyProgramDetailView is unchanged.

struct ParentProgramSummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    let program: Program

    @State private var notes: ProgramGuideNotes
    @State private var academyName: String
    @State private var pdfURL: URL?
    @State private var revision = 0
    @State private var gaps: [String] = []
    @State private var errorMessage: String?
    @State private var showingEditor = false
    @State private var shareItem: GuideShareItem?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    /// `selectedPhase` is accepted for source compatibility; the guide always
    /// covers the whole program, because a parent needs the progression.
    init(program: Program, selectedPhase: MicroCycle? = nil) {
        self.program = program
        _notes = State(initialValue: ProgramGuideStore.notes(for: program.id))
        _academyName = State(initialValue: ProgramGuideStore.academyName)
    }

    /// Re-read from the manager so edits made elsewhere are picked up.
    private var currentProgram: Program {
        dataManager.programs.first { $0.id == program.id } ?? program
    }

    private var programPhases: [MicroCycle] {
        dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !gaps.isEmpty {
                    gapBanner
                }
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                shareBar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isChinese ? "家长版计划指南" : "Parent Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "关闭" : "Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isChinese ? "编辑文字" : "Edit Wording") { showingEditor = true }
                }
            }
        }
        .task { regenerate() }
        .sheet(isPresented: $showingEditor) {
            ProgramGuideEditor(program: currentProgram,
                               phases: programPhases,
                               notes: $notes,
                               academyName: $academyName,
                               isChinese: isChinese) {
                ProgramGuideStore.save(notes, for: program.id)
                ProgramGuideStore.academyName = academyName
                regenerate()
            }
        }
        .sheet(item: $shareItem) { item in
            ProgramShareSheet(items: [item.url])
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if let pdfURL {
            GuidePDFPreview(url: pdfURL, revision: revision)
        } else if let errorMessage {
            ContentUnavailableView(isChinese ? "无法生成指南" : "Could not create the guide",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(errorMessage))
        } else {
            ProgressView()
        }
    }

    /// Says what is still generic, and opens the editor. The guide is only as
    /// specific as the program's own words.
    private var gapBanner: some View {
        Button {
            showingEditor = true
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.badge.plus")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "让指南更具体" : "Make the guide specific")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(gaps.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Share

    private var shareBar: some View {
        HStack(spacing: 12) {
            Button {
                if let pdfURL { shareItem = GuideShareItem(url: pdfURL) }
            } label: {
                Label("PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                shareLongImage()
            } label: {
                Label(isChinese ? "长图（微信）" : "Long Image", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .disabled(pdfURL == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Rendering

    private func makeInput() -> ProgramGuideDocument.Input {
        ProgramGuideDocument.makeInput(program: currentProgram,
                                       dataManager: dataManager,
                                       notes: notes,
                                       academyName: academyName,
                                       isChinese: isChinese)
    }

    private func regenerate() {
        let input = makeInput()
        gaps = ProgramGuideDocument.gaps(in: input)
        do {
            pdfURL = try ProgramGuideDocument.renderPDF(input)
            revision += 1
            errorMessage = nil
        } catch {
            pdfURL = nil
            errorMessage = error.localizedDescription
        }
    }

    private func shareLongImage() {
        do {
            let url = try ProgramGuideDocument.renderLongImage(makeInput())
            shareItem = GuideShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GuideShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - PDF preview

/// PDFKit view of the rendered file. The file is rewritten in place on every
/// edit, so `revision` tells the view when to reload it.
private struct GuidePDFPreview: UIViewRepresentable {
    let url: URL
    let revision: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(url: url)
        context.coordinator.revision = revision
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.revision != revision else { return }
        context.coordinator.revision = revision
        view.document = PDFDocument(url: url)
        view.autoScales = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var revision = -1
    }
}

// MARK: - Wording editor

/// The parent-facing words. Fields start from the program's own data where
/// it exists (introduction, phase names and descriptions); a value equal to
/// that data is not stored as an override, so later edits to the program
/// still flow through. Empty optional sections are left out of the guide.
private struct ProgramGuideEditor: View {
    @Environment(\.dismiss) private var dismiss

    let program: Program
    let phases: [MicroCycle]
    @Binding var notes: ProgramGuideNotes
    @Binding var academyName: String
    let isChinese: Bool
    let onSave: () -> Void

    @State private var draft = ProgramGuideNotes()
    @State private var academyDraft = ""
    @State private var purposeDraft = ""
    @State private var titleDrafts: [String: String] = [:]
    @State private var summaryDrafts: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isChinese ? "学院或球队名称" : "Academy or club name", text: $academyDraft)
                } header: {
                    Text(isChinese ? "抬头" : "Letterhead")
                } footer: {
                    Text(isChinese ? "所有计划共用。留空则使用教练姓名。" : "Shared by all programs. Leave empty to use the coach's name.")
                }

                Section {
                    TextEditor(text: $purposeDraft)
                        .frame(minHeight: 100)
                } header: {
                    Text(isChinese ? "关于本计划" : "About this program")
                } footer: {
                    Text(isChinese ? "用家长听得懂的话说明这个计划的目的。" : "In plain words for parents: what this program is for and who it suits.")
                }

                ForEach(phases) { phase in
                    Section {
                        TextField(isChinese ? "阶段名称" : "Phase name",
                                  text: binding(for: phase, in: $titleDrafts))
                        TextEditor(text: binding(for: phase, in: $summaryDrafts))
                            .frame(minHeight: 80)
                    } header: {
                        Text(isChinese ? "第\(phase.phaseNumber)阶段" : "Phase \(phase.phaseNumber)")
                    } footer: {
                        Text(isChinese
                             ? "给阶段起一个有意义的名字，并说明它为什么重要、会培养什么。练习重点和示例活动来自阶段的目标和训练内容。"
                             : "A meaningful name, then why this phase matters and what it builds. Practice points and example activities come from the phase's objectives and drills.")
                    }
                }

                Section {
                    TextEditor(text: $draft.sessionNote)
                        .frame(minHeight: 70)
                } header: {
                    Text(isChinese ? "一节课的样子（补充说明）" : "Typical session (note)")
                } footer: {
                    Text(isChinese ? "时间分配和活动取自一节已计划的训练课。" : "Timings and activities are read from a planned session.")
                }

                Section {
                    TextEditor(text: $draft.reviewNote)
                        .frame(minHeight: 70)
                } header: {
                    Text(isChinese ? "进度与反馈" : "Progress and feedback")
                } footer: {
                    Text(isChinese ? "家长会在何时、以什么方式了解孩子的进度。" : "How and when parents will hear about their child's progress.")
                }

                Section {
                    TextEditor(text: $draft.coachNote)
                        .frame(minHeight: 90)
                } header: {
                    Text(isChinese ? "教练寄语" : "A note from the coach")
                }

                Section {
                    TextEditor(text: $draft.homeActivity)
                        .frame(minHeight: 70)
                } header: {
                    Text(isChinese ? "在家可以练" : "Try at home")
                } footer: {
                    Text(isChinese ? "留空的部分不会出现在指南里。" : "Empty sections are left out of the guide.")
                }
            }
            .navigationTitle(isChinese ? "编辑文字" : "Edit Wording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func binding(for phase: MicroCycle, in store: Binding<[String: String]>) -> Binding<String> {
        let key = phase.id.uuidString
        return Binding(
            get: { store.wrappedValue[key] ?? "" },
            set: { store.wrappedValue[key] = $0 }
        )
    }

    private func load() {
        draft = notes
        academyDraft = academyName
        purposeDraft = notes.purpose.isEmpty ? (program.description ?? "") : notes.purpose
        for phase in phases {
            let key = phase.id.uuidString
            titleDrafts[key] = notes.phaseTitles[key] ?? phase.title
            summaryDrafts[key] = notes.phaseSummaries[key] ?? (phase.description ?? "")
        }
    }

    private func save() {
        var result = draft
        let purpose = trimmed(purposeDraft)
        result.purpose = purpose == trimmed(program.description ?? "") ? "" : purpose

        var titles: [String: String] = [:]
        var summaries: [String: String] = [:]
        for phase in phases {
            let key = phase.id.uuidString
            let title = trimmed(titleDrafts[key] ?? "")
            if !title.isEmpty && title != trimmed(phase.title) {
                titles[key] = title
            }
            let summary = trimmed(summaryDrafts[key] ?? "")
            if !summary.isEmpty && summary != trimmed(phase.description ?? "") {
                summaries[key] = summary
            }
        }
        result.phaseTitles = titles
        result.phaseSummaries = summaries
        result.sessionNote = trimmed(result.sessionNote)
        result.reviewNote = trimmed(result.reviewNote)
        result.coachNote = trimmed(result.coachNote)
        result.homeActivity = trimmed(result.homeActivity)

        notes = result
        academyName = trimmed(academyDraft)
        onSave()
        dismiss()
    }

    private func trimmed(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Share Sheet

struct ProgramShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
