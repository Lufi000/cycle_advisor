import SwiftUI

struct SettingsView: View {
    @AppStorage("displayName") private var displayName = ""
    @AppStorage("thinkingMode") private var thinkingModeRaw: String = ThinkingMode.fast.rawValue
    @AppStorage("hasShownConceptionOnboarding") private var hasShownConceptionOnboarding = false
    @AppStorage("conception.reminderTimeMinutes") private var reminderTimeMinutes = 420
    @AppStorage("conception.reminderEnabled") private var reminderEnabled = false
    @State private var showConceptionOnboarding = false
    private var profileManager = UserProfileManager.shared

    private var thinkingModeBinding: Binding<ThinkingMode> {
        Binding(
            get: { ThinkingMode(rawValue: thinkingModeRaw) ?? .fast },
            set: { thinkingModeRaw = $0.rawValue }
        )
    }

    private var conceptionBinding: Binding<Bool> {
        Binding(
            get: { profileManager.profile.isTryingToConceive },
            set: { newValue in
                profileManager.setTryingToConceive(newValue)
                if newValue && !hasShownConceptionOnboarding {
                    showConceptionOnboarding = true
                }
            }
        )
    }

    /// 晨间提醒时间（UserDefaults 存"距午夜分钟数"，默认 7:00 = 420）
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderTimeMinutes / 60,
                    minute: reminderTimeMinutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderTimeMinutes = (comps.hour ?? 7) * 60 + (comps.minute ?? 0)
            }
        )
    }

    /// 当前 App 实际生效的语言名(以其自身语言显示,如 "Español")。
    /// `Bundle.main.preferredLocalizations` 是系统按用户语言偏好从我们的 lproj 里挑出来的结果。
    private var currentSystemLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return name.capitalized
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
                Toggle(String(localized: "settings.conception.title"), isOn: conceptionBinding)
                    .tint(Theme.accent)

                if profileManager.profile.isTryingToConceive {
                    Toggle(String(localized: "conception.reminder.enabled"), isOn: $reminderEnabled)
                        .tint(Theme.accent)
                        .onChange(of: reminderEnabled) { _, _ in
                            Task { await ConceptionInsightManager.shared.refresh() }
                        }

                    if reminderEnabled {
                        DatePicker(
                            String(localized: "conception.reminder.time"),
                            selection: reminderTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }

                Text("settings.conception.hint")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("settings.section.conception")
            }

            Section {
                // 语言跟随系统(iOS 13+ per-app 语言),这里只展示当前生效语言并跳到系统设置。
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    HStack {
                        Text("settings.language.title")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(currentSystemLanguageName)
                            .foregroundStyle(Theme.textSecondary)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

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
        .alert(String(localized: "conception.onboarding.title"), isPresented: $showConceptionOnboarding) {
            Button(String(localized: "conception.onboarding.ok")) {
                hasShownConceptionOnboarding = true
            }
        } message: {
            Text("conception.onboarding.body")
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
