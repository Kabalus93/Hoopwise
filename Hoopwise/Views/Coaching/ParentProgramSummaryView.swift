import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Program Localization Helper
struct ProgramReportLocalization {
    let isChinese: Bool
    
    init() {
        self.isChinese = LocalizationManager.shared.currentLanguage == .chinese
    }
    
    var trainingProgram: String { isChinese ? "训练计划" : "TRAINING PROGRAM" }
    var weeks: String { isChinese ? "周" : "WEEKS" }
    var phases: String { isChinese ? "阶段" : "PHASES" }
    var perWeek: String { isChinese ? "每周" : "PER WEEK" }
    var trainingPhases: String { isChinese ? "训练阶段" : "TRAINING PHASES" }
    var focus: String { isChinese ? "训练重点" : "FOCUS" }
    var goals: String { isChinese ? "学习目标" : "GOALS" }
    var whatToExpect: String { isChinese ? "家长须知" : "WHAT TO EXPECT" }
    var skillDev: String { isChinese ? "技能发展" : "Skill Development" }
    var skillDevDesc: String { isChinese ? "系统化篮球技能提升" : "Progressive basketball skill building" }
    var passion: String { isChinese ? "运动热情" : "Love for the Game" }
    var passionDesc: String { isChinese ? "培养对篮球的热爱" : "Building passion for basketball" }
    var teamwork: String { isChinese ? "团队合作" : "Teamwork" }
    var teamworkDesc: String { isChinese ? "协作与沟通能力培养" : "Cooperation & communication skills" }
    var shareWithParents: String { isChinese ? "分享给家长" : "Share with Parents" }
    var close: String { isChinese ? "关闭" : "Close" }
    var parentNotice: String { isChinese ? "家长通知" : "Parent Notice" }
    var wks: String { isChinese ? "周" : "wks" }
    var phase: String { isChinese ? "阶段" : "Phase" }
}

// MARK: - Parent Program Summary View (Dark Aesthetic)
struct ParentProgramSummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    let program: Program
    let selectedPhase: MicroCycle?
    
    @State private var isGeneratingImage = false
    @State private var generatedImage: UIImage?
    @State private var showingShareSheet = false
    
    private let loc = ProgramReportLocalization()
    
    private var phases: [MicroCycle] {
        dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
    }
    
    private var accent: Color {
        Color(hex: program.colorHex)
    }
    
    init(program: Program, selectedPhase: MicroCycle? = nil) {
        self.program = program
        self.selectedPhase = selectedPhase
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Preview of the report
                        ProgramReportCard(
                            program: program,
                            phases: phases,
                            selectedPhase: selectedPhase,
                            accent: accent,
                            loc: loc
                        )
                        .scaleEffect(0.9)
                        .frame(height: 680)
                        
                        // Share button
                        Button(action: generateAndShare) {
                            HStack(spacing: 12) {
                                if isGeneratingImage {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                Text(loc.shareWithParents)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(accent)
                            .cornerRadius(14)
                        }
                        .disabled(isGeneratingImage)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(loc.parentNotice)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(loc.close) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = generatedImage {
                ProgramShareSheet(items: [image])
            }
        }
    }
    
    private func generateAndShare() {
        isGeneratingImage = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let reportView = ProgramReportCard(
                program: program,
                phases: phases,
                selectedPhase: selectedPhase,
                accent: accent,
                loc: loc
            )
            
            let controller = UIHostingController(rootView: reportView)
            let size = CGSize(width: 380, height: 750)
            controller.view.bounds = CGRect(origin: .zero, size: size)
            controller.view.backgroundColor = .clear
            
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            
            generatedImage = image
            isGeneratingImage = false
            showingShareSheet = true
        }
    }
}

// MARK: - Program Report Card (Dark Theme - Matches StudentParentReport)
struct ProgramReportCard: View {
    let program: Program
    let phases: [MicroCycle]
    let selectedPhase: MicroCycle?
    let accent: Color
    let loc: ProgramReportLocalization
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            VStack(spacing: 10) {
                statsRow
                if let phase = selectedPhase {
                    phaseDetailSection(phase)
                } else {
                    phasesListSection
                }
                expectationsSection
                footerSection
            }
            .padding(12)
            .background(Color(hex: "#1A1A1A"))
        }
        .frame(width: 380, height: 750)
        .background(Color(hex: "#0D0D0D"))
        .cornerRadius(20)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HOOPWISE ACADEMY")
                        .font(.system(size: 9, weight: .bold)).tracking(1)
                        .foregroundColor(.white.opacity(0.5))
                    Text(loc.trainingProgram)
                        .font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .foregroundColor(accent)
                }
                Spacer()
                Text(formattedDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            HStack(spacing: 14) {
                // Mascot icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                    Image(systemName: program.mascot.icon)
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                .shadow(color: accent.opacity(0.4), radius: 8, x: 0, y: 4)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(program.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Text(program.ageGroup.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Text("•").foregroundColor(.white.opacity(0.3))
                        Text(program.programType.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accent)
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(hex: "#1A1A1A"), Color(hex: "#0D0D0D")], startPoint: .top, endPoint: .bottom))
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: loc.isChinese ? "zh_CN" : "en_US")
        return formatter.string(from: Date())
    }
    
    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: 8) {
            statCard(loc.weeks, "\(program.durationWeeks)", "calendar", Color(hex: "#5B8DEF"))
            statCard(loc.phases, "\(phases.count)", "flag.fill", Color(hex: "#00D26A"))
            statCard(loc.perWeek, "\(program.recurringDays.count)x", "repeat", Color(hex: "#FF9500"))
        }
    }
    
    private func statCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(title).font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.4)).tracking(0.5)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color(hex: "#252525")).cornerRadius(10)
    }
    
    // MARK: - Phases List
    private var phasesListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.trainingPhases)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(0.8)
            
            VStack(spacing: 6) {
                ForEach(phases.prefix(8)) { phase in
                    phaseRow(phase)
                }
                if phases.count > 8 {
                    Text("+\(phases.count - 8) more...")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(Color(hex: "#252525"))
        .cornerRadius(12)
    }
    
    private func phaseRow(_ phase: MicroCycle) -> some View {
        HStack(spacing: 10) {
            // Phase number badge
            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: 24, height: 24)
                Text("\(phase.phaseNumber)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Title and focus
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if !phase.focus.isEmpty {
                    Text(phase.focus.prefix(2).map { $0.displayName }.joined(separator: " • "))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Duration
            Text("\(phase.durationWeeks) \(loc.wks)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Phase Detail
    private func phaseDetailSection(_ phase: MicroCycle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Phase header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 36, height: 36)
                    Text("\(phase.phaseNumber)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(loc.phase) \(phase.phaseNumber)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(accent)
                    Text(phase.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("\(phase.durationWeeks) \(loc.wks)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent)
                    .cornerRadius(6)
            }
            
            // Description
            if let desc = phase.description {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
            
            // Focus areas
            if !phase.focus.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.focus)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(0.8)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(phase.focus.prefix(4), id: \.self) { focus in
                            HStack(spacing: 4) {
                                Image(systemName: focus.icon)
                                    .font(.system(size: 9))
                                Text(focus.displayName)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(accent.opacity(0.15))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            // Objectives
            if !phase.objectives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.goals)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(0.8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(phase.objectives.prefix(4), id: \.self) { objective in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#00D26A"))
                                Text(objective)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: "#252525"))
        .cornerRadius(12)
    }
    
    // MARK: - Expectations
    private var expectationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.whatToExpect)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(0.8)
            
            expectationRow("figure.run", Color(hex: "#FF9500"), loc.skillDev, loc.skillDevDesc)
            expectationRow("heart.fill", Color(hex: "#FF6B6B"), loc.passion, loc.passionDesc)
            expectationRow("person.3.fill", Color(hex: "#5B8DEF"), loc.teamwork, loc.teamworkDesc)
        }
        .padding(12)
        .background(Color(hex: "#252525"))
        .cornerRadius(12)
    }
    
    private func expectationRow(_ icon: String, _ color: Color, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.2))
                .cornerRadius(5)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
    }
    
    // MARK: - Footer
    private var footerSection: some View {
        HStack {
            Image(systemName: "basketball.fill")
                .font(.system(size: 11))
                .foregroundColor(accent)
            Text(loc.isChinese ? "专业篮球训练" : "Professional Basketball Training")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text("Hoopwise")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(accent)
        }
        .padding(.top, 6)
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
