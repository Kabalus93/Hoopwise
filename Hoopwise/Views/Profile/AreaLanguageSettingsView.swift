import SwiftUI

/// Profile → Preferences → Languages by area: the language of what leaves the
/// app or is shown to children and parents, apart from the app's own.
struct AreaLanguageSettingsView: View {
    @State private var choices: [AreaLanguage.Area: AreaLanguage.Choice] =
        Dictionary(uniqueKeysWithValues: AreaLanguage.Area.allCases.map { ($0, AreaLanguage.choice(for: $0)) })

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        Form {
            Section {
                ForEach(AreaLanguage.Area.allCases) { area in
                    Picker(area.title(chinese: isChinese), selection: Binding(
                        get: { choices[area] ?? area.defaultChoice },
                        set: { choice in
                            choices[area] = choice
                            AreaLanguage.set(choice, for: area)
                        })) {
                        ForEach(AreaLanguage.Choice.allCases) { choice in
                            Text(choice.title(chinese: isChinese)).tag(choice)
                        }
                    }
                    .accessibilityIdentifier("areaLanguage.\(area.rawValue)")
                }
            } footer: {
                Text(isChinese
                     ? "这些内容可以使用与应用不同的语言。点名照片默认中文（发到微信群）。"
                     : "These can use a different language from the app. The roll-call photo starts in Chinese, for WeChat groups.")
            }
        }
        .navigationTitle(isChinese ? "分区语言" : "Languages by Area")
        .navigationBarTitleDisplayMode(.inline)
    }
}
