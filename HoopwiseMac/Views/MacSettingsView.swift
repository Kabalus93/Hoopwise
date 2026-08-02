import SwiftUI
import CloudKit

// MARK: - Settings (⌘,)
//
// Only settings that change real behaviour — no placeholder toggles. All
// local (@AppStorage); nothing here syncs. The interface-language picker is
// deliberately ABSENT: LocalizationManager only localizes drill content and
// skip reasons, Mac interface strings are English, and interface
// localization is not on the roadmap — a picker would lie.
struct MacSettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var syncMonitor = CloudSyncMonitor.shared

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintbrush") }
            editorTab.tabItem { Label("Editor", systemImage: "sportscourt") }
            syncTab.tabItem { Label("Sync", systemImage: "icloud") }
            shortcutsTab.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            dataTab.tabItem { Label("Data", systemImage: "internaldrive") }
        }
        .frame(width: 560, height: 460)
    }

    // MARK: General

    @AppStorage("settings.startupPage") private var startupPage = "today"
    @AppStorage("settings.confirmBeforeDelete") private var confirmBeforeDelete = true

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Picker("Open at launch", selection: $startupPage) {
                    Text("Today").tag("today")
                    Text("Last used page").tag("last")
                }
            }
            Section {
                Toggle("Confirm before deleting", isOn: $confirmBeforeDelete)
            } footer: {
                Text("Applies to athletes, sessions and programs. Deletes are permanent — attendance and contract records go with an athlete.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Profile") {
                LabeledContent("Coach", value: dataManager.coach.name.isEmpty ? "—" : dataManager.coach.name)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Appearance

    @AppStorage("settings.theme") private var theme = "system"
    @AppStorage("settings.accent") private var accent = "system"
    @AppStorage("settings.textScale") private var textScale = "m"
    @AppStorage("settings.listDensity") private var listDensity = "comfortable"

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Accent", selection: $accent) {
                    Text("System").tag("system")
                    Text("Hoopwise Orange").tag("app")
                }
            }
            Section {
                Picker("Text size", selection: $textScale) {
                    Text("S").tag("s")
                    Text("M").tag("m")
                    Text("L").tag("l")
                    Text("XL").tag("xl")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Scales every label in the app through Dynamic Type. M is the system default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("List density", selection: $listDensity) {
                    Text("Comfortable").tag("comfortable")
                    Text("Compact").tag("compact")
                }
            } footer: {
                Text("Row height and padding in directory lists and the editor timeline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Editor

    @AppStorage("autoPresentOnPlay") private var autoPresentOnPlay = true
    @AppStorage("settings.defaultCourtStandard") private var defaultStandard = "fiba"
    @AppStorage("settings.defaultCourtMode") private var defaultMode = "half"
    @AppStorage("editor.pathStrokeHex") private var pathStrokeHex = "#A76458"
    @AppStorage("editor.pathWidthFactor") private var pathWidthFactor = 0.6
    @AppStorage("editor.pathBlurFactor") private var pathBlurFactor = 0.35

    private var editorTab: some View {
        Form {
            Section("Playback") {
                Toggle("Switch to Presentation while playing", isOn: $autoPresentOnPlay)
            }
            Section("New diagrams") {
                Picker("Court standard", selection: $defaultStandard) {
                    Text("FIBA").tag("fiba")
                    Text("NBA").tag("nba")
                }
                Picker("Extent", selection: $defaultMode) {
                    Text("Half court").tag("half")
                    Text("Full court").tag("full")
                }
            }
            Section {
                ColorPicker("Path colour", selection: Binding(
                    get: { Color(hex: pathStrokeHex) },
                    set: { pathStrokeHex = $0.hexString }))
                HStack {
                    Text("Path width")
                    Slider(value: $pathWidthFactor, in: 0.2...1.2)
                    Text(String(format: "%.2f×", pathWidthFactor))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Path blur")
                    Slider(value: $pathBlurFactor, in: 0...0.8)
                    Text(String(format: "%.2f×", pathBlurFactor))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                Button("Reset to Default") {
                    pathStrokeHex = "#A76458"
                    pathWidthFactor = 0.6
                    pathBlurFactor = 0.35
                }
                .controlSize(.small)
            } header: {
                Text("Presentation brush")
            } footer: {
                Text("The published video look: width as a fraction of puck diameter, blur as a fraction of stroke width. Applies to canvas playback and exports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Shortcuts (read-only, from the dispatch layer's own tables)

    private var shortcutsTab: some View {
        Form {
            Section("Everywhere") {
                shortcutRows(PresentationKeyDispatcher.shortcuts)
            }
            Section("Directory pages (Athletes, Sessions)") {
                shortcutRows(DirectoryKeyDispatcher.shortcuts)
            }
            Section("Court editor") {
                shortcutRows(EditorKeyDispatcher.shortcuts)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func shortcutRows(_ shortcuts: [KeyShortcutDescriptor]) -> some View {
        ForEach(shortcuts, id: \.keys) { item in
            LabeledContent(item.action) {
                Text(item.keys)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sync

    // Deliberately has no "Sync Now" or "Auto Sync" control. SwiftData drives CloudKit
    // itself, so neither would do anything, and CLAUDE.md rule 6 forbids replicating the
    // iOS placebos. What this shows instead is the state that was previously invisible.
    private var syncTab: some View {
        Form {
            if let failure = SwiftDataManager.startupFailure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Store")
                }
            }

            Section {
                LabeledContent("iCloud Account") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accountStatusColor)
                            .frame(width: 8, height: 8)
                        Text(syncMonitor.accountStatusLabel)
                    }
                }

                if let advice = syncMonitor.accountStatusAdvice {
                    Text(advice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        if syncMonitor.isSyncing { ProgressView().controlSize(.small) }
                        Text(syncMonitor.activity.label)
                    }
                }

                LabeledContent("Last Synced", value: syncMonitor.lastSyncLabel)
            }

            Section {
                if let error = syncMonitor.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("No sync errors", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Environment", value: syncMonitor.environmentLabel)
                LabeledContent("Container", value: CloudSyncMonitor.containerIdentifier)
                    .textSelection(.enabled)
            } footer: {
                Text("Development and Production are separate databases. A debug build never sees data written by a TestFlight or App Store build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Check iCloud Account") {
                    Task { await syncMonitor.refreshAccountStatus() }
                }
                .disabled(syncMonitor.isCheckingAccount)
            } footer: {
                Text("SwiftData syncs with CloudKit automatically; there is nothing to trigger by hand. This re-checks the account this build can reach.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await syncMonitor.refreshAccountStatus() }
    }

    private var accountStatusColor: Color {
        switch syncMonitor.accountStatus {
        case .available:  return .green
        case .noAccount:  return .orange
        case .restricted: return .red
        default:          return .gray
        }
    }

    private var dataTab: some View {
        Form {
            Button("Refresh All Data") {
                Task { await dataManager.refreshAllCaches() }
            }
            LabeledContent("Athletes", value: "\(dataManager.students.count)")
            LabeledContent("Sessions", value: "\(dataManager.sessionEvents.count)")
            LabeledContent("Programs", value: "\(dataManager.programs.count)")
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance application (root modifier)

/// Applied once at the window root: theme override wins over system in both
/// directions, accent recolours controls, text scale rides Dynamic Type so
/// every semantic font in the app follows.
struct AppearanceSettingsModifier: ViewModifier {
    @AppStorage("settings.theme") private var theme = "system"
    @AppStorage("settings.accent") private var accent = "system"
    @AppStorage("settings.textScale") private var textScale = "m"

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
            .tint(accent == "app" ? Color.orange : nil)
            .dynamicTypeSize(typeSize)
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    private var typeSize: DynamicTypeSize {
        switch textScale {
        case "s":  return .small
        case "l":  return .xLarge
        case "xl": return .xxxLarge
        default:   return .large
        }
    }
}

// MARK: - Editor defaults plumbing

extension RenderStyle {
    /// Presentation with the coach's stored brush overrides — what canvas
    /// playback and exports use on the Mac. Reset in Settings restores the
    /// shipped video look.
    static var presentationUser: RenderStyle {
        var style = RenderStyle.presentation
        let defaults = UserDefaults.standard
        if let hex = defaults.string(forKey: "editor.pathStrokeHex"), !hex.isEmpty {
            style.pathStrokeHex = hex
        }
        let width = defaults.double(forKey: "editor.pathWidthFactor")
        if width > 0 { style.pathWidthPuckFactor = width }
        if defaults.object(forKey: "editor.pathBlurFactor") != nil {
            style.pathBlurFactor = defaults.double(forKey: "editor.pathBlurFactor")
        }
        return style
    }
}
