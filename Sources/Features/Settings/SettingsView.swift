import SwiftUI

struct SettingsView: View {
    @AppStorage("displayName") private var displayName = "Lufi"
    @AppStorage("thinkingMode") private var thinkingModeRaw: String = ThinkingMode.fast.rawValue
    private let languageManager = LanguageManager.shared

    private var languageBinding: Binding<LanguageManager.AppLanguage> {
        Binding(
            get: { languageManager.current },
            set: { languageManager.current = $0 }
        )
    }

    private var thinkingModeBinding: Binding<ThinkingMode> {
        Binding(
            get: { ThinkingMode(rawValue: thinkingModeRaw) ?? .fast },
            set: { thinkingModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section {
                TextField(String(localized: "settings.profile.display_name"), text: $displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                Text("settings.profile.display_name.hint")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("settings.section.profile")
            }

            Section {
                Picker(String(localized: "settings.thinking_mode"), selection: thinkingModeBinding) {
                    ForEach(ThinkingMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Text("settings.thinking_mode.hint")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("settings.section.ai")
            }

            Section {
                Picker(String(localized: "settings.language.title"), selection: languageBinding) {
                    ForEach(LanguageManager.AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .pickerStyle(.inline)

                Text("settings.language.hint")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("settings.section.language")
            }

            Section {
                DisclaimerView()
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            } header: {
                Text("settings.section.disclaimer")
            }

            Section {
                CitationLinksView(sources: ReferenceLibrary.all)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            } header: {
                Text("settings.section.medical_sources")
            }
        }
        .navigationTitle(String(localized: "tab.settings"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
