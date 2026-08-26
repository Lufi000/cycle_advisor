import SwiftUI

struct ProfileView: View {
    private var profileManager = UserProfileManager.shared
    @AppStorage("displayName") private var displayName = ""
    @State private var showResetAlert = false

    private var profile: UserProfile { profileManager.profile }

    var body: some View {
        ZStack {
            Theme.background
                .grainTexture(intensity: .subtle, seed: 500)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    displayNameSection
                    if profile.isEmpty {
                        emptyState
                    } else {
                        bodyInfoSection
                        cycleStatsSection
                        symptomsSection
                        lifestyleSection
                        resetSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(String(localized: "profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "profile.reset.confirm"), isPresented: $showResetAlert) {
            Button(String(localized: "profile.reset.cancel"), role: .cancel) {}
            Button(String(localized: "profile.reset.action"), role: .destructive) {
                profileManager.resetAll()
            }
        }
    }

    // MARK: - Display Name

    private var displayNameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "person.text.rectangle", title: String(localized: "profile.section.name"))

            TextField(String(localized: "settings.profile.display_name"), text: $displayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.system(size: Theme.bodySize))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.background.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("settings.profile.display_name.hint")
                .font(.system(size: Theme.captionSize))
                .foregroundStyle(Theme.textSecondary)
        }
        .grainCardStyle(seed: 500)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textSecondary)
            Text("profile.empty")
                .font(.system(size: Theme.bodySize))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - Body Info

    @ViewBuilder
    private var bodyInfoSection: some View {
        let info = profile.bodyInfo
        if info != .empty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "figure.stand", title: String(localized: "profile.section.body"))

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    if let age = info.age {
                        infoCell(label: String(localized: "profile.age"), value: "\(age)")
                    }
                    if let height = info.heightCM {
                        infoCell(label: String(localized: "profile.height"), value: String(format: "%.0f cm", height))
                    }
                    if let weight = info.weightKG {
                        infoCell(label: String(localized: "profile.weight"), value: String(format: "%.1f kg", weight))
                    }
                    if let bmi = info.bmi {
                        infoCell(label: "BMI", value: String(format: "%.1f", bmi))
                    }
                }
            }
            .grainCardStyle(seed: 501)
        }
    }

    // MARK: - Cycle Stats

    @ViewBuilder
    private var cycleStatsSection: some View {
        let stats = profile.accumulatedStats
        if stats.cyclesRecorded > 0 {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "calendar.circle", title: String(localized: "profile.section.cycle"))

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    if let avg = stats.averageCycleLength {
                        infoCell(
                            label: String(localized: "profile.avg_cycle"),
                            value: String(format: "%.0f %@", avg, String(localized: "profile.days"))
                        )
                    }
                    if let avg = stats.averagePeriodDuration {
                        infoCell(
                            label: String(localized: "profile.avg_period"),
                            value: String(format: "%.0f %@", avg, String(localized: "profile.days"))
                        )
                    }
                    infoCell(
                        label: String(localized: "profile.cycles_recorded"),
                        value: "\(stats.cyclesRecorded)"
                    )
                }

                // 出血量模式
                if !stats.flowPatternByDay.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("profile.flow_pattern")
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.textSecondary)
                        let sorted = stats.flowPatternByDay.sorted {
                            (Int($0.key) ?? 0) < (Int($1.key) ?? 0)
                        }
                        HStack(spacing: 6) {
                            ForEach(sorted, id: \.key) { day, flow in
                                VStack(spacing: 2) {
                                    Text("D\(day)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                    flowDot(FlowLevel(rawValue: flow))
                                }
                            }
                        }
                    }
                }
            }
            .grainCardStyle(seed: 502)
        }
    }

    // MARK: - Symptoms

    @ViewBuilder
    private var symptomsSection: some View {
        let stats = profile.accumulatedStats
        let allPhases = CyclePhase.allCases.filter { phase in
            !(stats.topSymptoms(for: phase).isEmpty)
        }
        let currentSymptoms = stats.recentSymptoms48h ?? []
        let cycleSymptoms = stats.currentCycleSymptoms ?? []
        if !allPhases.isEmpty || !currentSymptoms.isEmpty || !cycleSymptoms.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "heart.text.square", title: String(localized: "profile.section.symptoms"))

                if !currentSymptoms.isEmpty {
                    symptomTimelineBlock(
                        title: "最近 48 小时",
                        subtitle: "AI 会优先按这些症状理解当前状态",
                        symptoms: currentSymptoms,
                        tint: Theme.phaseMenstrual
                    )
                }

                if !cycleSymptoms.isEmpty {
                    symptomTimelineBlock(
                        title: "当前周期",
                        subtitle: "周期回顾，不一定代表现在仍有症状",
                        symptoms: cycleSymptoms,
                        tint: Theme.phaseLuteal
                    )
                }

                if !allPhases.isEmpty {
                    Divider().opacity(0.25)
                    Text("历史高频")
                        .font(.system(size: Theme.captionSize, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(allPhases, id: \.self) { phase in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phase.displayName)
                                .font(.system(size: Theme.captionSize, weight: .medium))
                                .foregroundStyle(phase.color)

                            FlowLayout(spacing: 4) {
                                ForEach(stats.topSymptoms(for: phase), id: \.symptom) { item in
                                    HStack(spacing: 3) {
                                        Text(symptomDisplayName(item.symptom))
                                            .font(.system(size: Theme.captionSize))
                                        Text("(\(item.count))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(phase.color.opacity(0.1))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .grainCardStyle(seed: 504)
        }
    }

    // MARK: - Lifestyle (AI-extracted)

    @ViewBuilder
    private var lifestyleSection: some View {
        let ls = profile.lifestyle
        let hasData = ls.sleepPattern != nil || !ls.dietaryPreferences.isEmpty
            || !ls.knownSensitivities.isEmpty || !profile.knownConditions.isEmpty

        if hasData {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "sparkles", title: String(localized: "profile.section.lifestyle"))

                if let sleep = ls.sleepPattern {
                    profileRow(
                        label: sleepLabel(observedAt: ls.sleepPatternObservedAt),
                        value: sleep,
                        onDelete: { profileManager.resetField(\.lifestyle.sleepPattern) }
                    )
                }

                if !ls.dietaryPreferences.isEmpty {
                    profileRow(
                        label: String(localized: "profile.diet"),
                        value: ls.dietaryPreferences.joined(separator: "、"),
                        onDelete: { profileManager.resetLifestyleDietaryPreferences() }
                    )
                }

                if !ls.knownSensitivities.isEmpty {
                    profileRow(
                        label: String(localized: "profile.sensitivities"),
                        value: ls.knownSensitivities.joined(separator: "、"),
                        onDelete: { profileManager.resetKnownSensitivities() }
                    )
                }

                if !profile.knownConditions.isEmpty {
                    profileRow(
                        label: String(localized: "profile.conditions"),
                        value: profile.knownConditions.joined(separator: "、"),
                        onDelete: { profileManager.resetKnownConditions() }
                    )
                }

                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("profile.ai_source")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .grainCardStyle(seed: 505)
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Button {
            showResetAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                Text("profile.reset")
                    .font(.system(size: Theme.bodySize))
            }
            .foregroundStyle(.red.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .grainCardStyle(seed: 506)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: Theme.cardTitleSize, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func infoCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: Theme.captionSize))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func profileRow(label: String, value: String, onDelete: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
    }

    private func symptomTimelineBlock(
        title: String,
        subtitle: String,
        symptoms: [SymptomEntry],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: Theme.captionSize, weight: .medium))
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            FlowLayout(spacing: 4) {
                ForEach(symptoms) { symptom in
                    HStack(spacing: 3) {
                        Text(symptom.type.displayName)
                            .font(.system(size: Theme.captionSize))
                        Text(symptom.severity.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(tint)
                        Text(relativeDayLabel(for: symptom.date))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func sleepLabel(observedAt: Date?) -> String {
        guard let observedAt else { return "\(String(localized: "profile.sleep")) · 旧版画像" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: observedAt),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        let freshness = days <= 14 ? "近期" : "历史"
        return "\(String(localized: "profile.sleep")) · \(freshness) · \(relativeDayLabel(for: observedAt))"
    }

    private func relativeDayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        switch days {
        case ..<0:
            return "未来"
        case 0:
            return "今天"
        case 1:
            return "昨天"
        case 2:
            return "前天"
        default:
            return "\(days)天前"
        }
    }

    private func flowDot(_ level: FlowLevel?) -> some View {
        let count: Int = switch level {
        case .light: 1
        case .medium: 2
        case .heavy: 3
        default: 0
        }
        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < count ? Theme.phaseMenstrual : Theme.phaseMenstrual.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func symptomDisplayName(_ rawValue: String) -> String {
        guard let type = SymptomEntry.SymptomType(rawValue: rawValue) else { return rawValue }
        return type.displayName
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
