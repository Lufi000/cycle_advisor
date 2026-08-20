import SwiftUI
import UIKit
import Photos

struct WorkoutDashboardView: View {
    private var profileManager = UserProfileManager.shared
    let context: CycleContext
    private let statsOverride: WorkoutStats?
    @State private var generatedWeeklySummary: String?
    @State private var activeSummaryID: String?
    @State private var weeklySummaryGenerationFailed = false
    @State private var saveFeedbackMessage: String?

    private var stats: WorkoutStats {
        statsOverride ?? profileManager.profile.workoutStats
    }
    private var healthMetrics: HealthMetrics { context.healthMetrics }
    private var hasActivityMetrics: Bool {
        healthMetrics.exerciseMinutes != nil
            || healthMetrics.steps != nil
            || healthMetrics.activeCalories != nil
    }

    init(context: CycleContext, statsOverride: WorkoutStats? = nil) {
        self.context = context
        self.statsOverride = statsOverride
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmShell
                    .grainTexture(intensity: .subtle, seed: 530)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        if stats.topActivities.isEmpty {
                            if hasActivityMetrics {
                                activityOnlySection
                            } else {
                                emptyState
                            }
                        } else {
                            weeklyRhythmSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                String(localized: "workout.share.save_title"),
                isPresented: Binding(
                    get: { saveFeedbackMessage != nil },
                    set: { if !$0 { saveFeedbackMessage = nil } }
                )
            ) {
                Button(String(localized: "common.done"), role: .cancel) {}
            } message: {
                Text(saveFeedbackMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            workoutPosterArt(for: .yoga)
                .frame(maxWidth: 220, alignment: .center)
            Text(String(localized: "workout.empty.title"))
                .font(.system(size: Theme.cardTitleSize, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(String(localized: "workout.empty.body"))
                .font(.system(size: Theme.bodySize))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(Theme.lineSpacing)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .grainCardStyle(seed: 531)
    }

    private var activityOnlySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                sectionHeader(icon: "figure.walk", title: String(localized: "workout.activity_only.section"))
                Spacer(minLength: 0)
                workoutSaveButton { saveActivityOnlyCard() }
            }

            activityOnlyShareContent()
        }
        .grainCardStyle(seed: 531)
    }

    private func activityOnlyShareContent() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text(activityOnlyTitle)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(activityOnlySummary)
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Theme.lineSpacing)
            }

            workoutPosterArt(for: activityOnlyArtKind)
                .frame(maxWidth: 313, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                activityOnlyMetricPills
            }
        }
    }

    @ViewBuilder
    private var activityOnlyMetricPills: some View {
        if let exercise = healthMetrics.formattedExerciseDuration {
            workoutMetricPill(
                icon: "figure.run",
                label: String(localized: "workout.metric.exercise_minutes"),
                value: exercise,
                tint: Theme.phaseFollicular
            )
        }
        if let steps = healthMetrics.formattedSteps {
            workoutMetricPill(
                icon: "figure.walk",
                label: String(localized: "workout.metric.steps"),
                value: steps,
                tint: Theme.phaseOvulation
            )
        }
        if let activeCalories = healthMetrics.activeCalories {
            workoutMetricPill(
                icon: "flame",
                label: String(localized: "workout.metric.active_calories"),
                value: String(format: "%.0f kcal", activeCalories),
                tint: Theme.phaseLuteal
            )
        }
    }

    private var weeklyRhythmSection: some View {
        let data = workoutCardData
        let summaryID = weeklySummaryID(for: data.featuredActivity, weeklyCount: data.weeklyCount, totalMinutes: data.totalMinutes)
        let isLoadingSummary = data.weeklyCount > 0
            && data.featuredActivity != nil
            && generatedWeeklySummary == nil
            && !weeklySummaryGenerationFailed

        return VStack {
            workoutCardContent(
                featuredActivity: data.featuredActivity,
                weeklyCount: data.weeklyCount,
                totalMinutes: data.totalMinutes,
                displayActivities: data.displayActivities,
                isLoadingSummary: isLoadingSummary,
                showsShareButton: true
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 24)
        .background(workoutPosterCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: summaryID) {
            await loadGeneratedWeeklySummary(
                id: summaryID,
                activity: data.featuredActivity,
                weeklyCount: data.weeklyCount,
                totalMinutes: data.totalMinutes
            )
        }
    }

    private var workoutCardData: (
        weeklyCount: Int,
        totalMinutes: Double,
        displayActivities: [WorkoutStats.WorkoutActivity],
        featuredActivity: WorkoutStats.WorkoutActivity?
    ) {
        let weeklyCount = stats.weeklyWorkoutCount ?? 0
        let totalMinutes = stats.weeklyTotalDurationMinutes ?? 0
        let weeklyActivities = sortedWorkoutActivities(stats.weeklyActivities ?? [])
        let topActivities = sortedWorkoutActivities(stats.topActivities)
        let displayActivities = weeklyActivities.isEmpty ? topActivities : weeklyActivities
        let featuredActivity = displayActivities.first
        return (weeklyCount, totalMinutes, displayActivities, featuredActivity)
    }

    private func workoutCardContent(
        featuredActivity: WorkoutStats.WorkoutActivity?,
        weeklyCount: Int,
        totalMinutes: Double,
        displayActivities: [WorkoutStats.WorkoutActivity],
        isLoadingSummary: Bool,
        showsShareButton: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(weeklyTitle(for: featuredActivity, weeklyCount: weeklyCount))
                        .font(Theme.itim(size: 36))
                        .foregroundStyle(workoutPosterInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    weeklySummaryText(for: featuredActivity, weeklyCount: weeklyCount)
                }

                if showsShareButton {
                    Spacer(minLength: 0)
                    workoutSaveButton { saveWorkoutCard() }
                }
            }

            workoutPosterImage(for: featuredActivity, isLoading: isLoadingSummary)

            workoutStatsStrip(totalMinutes: totalMinutes, weeklyCount: weeklyCount)

            workoutCategoryRows(activities: displayActivities, totalMinutes: totalMinutes)
        }
        .frame(maxWidth: 313)
    }

    private var workoutPosterInk: Color {
        Theme.textPrimary
    }

    private var workoutPosterMuted: Color {
        Color.black.opacity(0.50)
    }

    private var workoutPosterCardBackground: Color {
        Theme.cardBackgroundSolid
    }

    private func workoutSaveButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.peachBlush.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "workout.share.label"))
    }

    @MainActor
    private func saveWorkoutCard() {
        let data = workoutCardData
        guard let image = renderWorkoutCardImage(
            featuredActivity: data.featuredActivity,
            weeklyCount: data.weeklyCount,
            totalMinutes: data.totalMinutes,
            displayActivities: data.displayActivities
        ) else {
            saveFeedbackMessage = String(localized: "workout.share.save_failed")
            return
        }
        saveImageToPhotoLibrary(image)
    }

    @MainActor
    private func renderWorkoutCardImage(
        featuredActivity: WorkoutStats.WorkoutActivity?,
        weeklyCount: Int,
        totalMinutes: Double,
        displayActivities: [WorkoutStats.WorkoutActivity]
    ) -> UIImage? {
        let content = workoutCardContent(
            featuredActivity: featuredActivity,
            weeklyCount: weeklyCount,
            totalMinutes: totalMinutes,
            displayActivities: displayActivities,
            isLoadingSummary: false
        )
        .frame(width: 313)
        .padding(.vertical, 38)
        .padding(.horizontal, 24)
        .background(workoutPosterCardBackground)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage
    }

    @MainActor
    private func saveActivityOnlyCard() {
        guard let image = renderActivityOnlyCardImage() else {
            saveFeedbackMessage = String(localized: "workout.share.save_failed")
            return
        }
        saveImageToPhotoLibrary(image)
    }

    @MainActor
    private func saveImageToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    } completionHandler: { success, error in
                        DispatchQueue.main.async {
                            if success {
                                saveFeedbackMessage = String(localized: "workout.share.saved")
                            } else {
                                saveFeedbackMessage = error?.localizedDescription
                                    ?? String(localized: "workout.share.save_failed")
                            }
                        }
                    }
                default:
                    saveFeedbackMessage = String(localized: "workout.share.photo_access_denied")
                }
            }
        }
    }

    @MainActor
    private func renderActivityOnlyCardImage() -> UIImage? {
        let content = activityOnlyShareContent()
            .frame(width: 313, alignment: .leading)
            .padding(Theme.cardPadding)
            .background(workoutPosterCardBackground)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage
    }

    private var activityOnlyTitle: String {
        if let exercise = healthMetrics.exerciseMinutes, exercise >= 30 {
            return String(localized: "workout.activity_only.title.active")
        }
        if let steps = healthMetrics.steps, steps >= 6000 {
            return String(localized: "workout.activity_only.title.walker")
        }
        return String(localized: "workout.activity_only.title.light")
    }

    private var activityOnlySummary: String {
        switch context.phase {
        case .menstrual:
            return String(localized: "workout.activity_only.summary.menstrual")
        case .follicular:
            return String(localized: "workout.activity_only.summary.follicular")
        case .ovulation:
            return String(localized: "workout.activity_only.summary.ovulation")
        case .luteal:
            return String(localized: "workout.activity_only.summary.luteal")
        }
    }

    private var activityOnlyArtKind: WorkoutActivityKind {
        if let exercise = healthMetrics.exerciseMinutes, exercise >= 30 {
            return .running
        }
        if let steps = healthMetrics.steps, steps >= 6000 {
            return .walking
        }
        return .other
    }

    private func weeklyTitle(for activity: WorkoutStats.WorkoutActivity?, weeklyCount: Int) -> String {
        guard weeklyCount > 0 else { return String(localized: "workout.title.recovery") }
        guard let activity else { return workoutMomentumLabel(count: weeklyCount, minutes: stats.weeklyTotalDurationMinutes ?? 0) }
        return NSLocalizedString(workoutTitleKey(for: activity), comment: "")
    }

    private func weeklySummaryFallback(for activity: WorkoutStats.WorkoutActivity?, weeklyCount: Int) -> String {
        guard weeklyCount > 0 else {
            return String(localized: "workout.summary.no_workouts")
        }
        return String(localized: "workout.summary.no_activity_type")
    }

    @ViewBuilder
    private func weeklySummaryText(for activity: WorkoutStats.WorkoutActivity?, weeklyCount: Int) -> some View {
        if weeklyCount <= 0 || activity == nil {
            Text(weeklySummaryFallback(for: activity, weeklyCount: weeklyCount))
                .font(Theme.itim(size: 18))
                .foregroundStyle(workoutPosterMuted)
                .lineSpacing(5)
        } else if let generatedWeeklySummary {
            Text(generatedWeeklySummary)
                .font(Theme.itim(size: 18))
                .foregroundStyle(workoutPosterMuted)
                .lineSpacing(5)
        } else if weeklySummaryGenerationFailed {
            Color.clear
                .frame(height: 44)
        } else {
            Color.clear
                .frame(height: 44, alignment: .leading)
        }
    }

    @MainActor
    private func loadGeneratedWeeklySummary(
        id: String,
        activity: WorkoutStats.WorkoutActivity?,
        weeklyCount: Int,
        totalMinutes: Double
    ) async {
        guard weeklyCount > 0, let activity else {
            generatedWeeklySummary = nil
            activeSummaryID = id
            return
        }

        if activeSummaryID != id {
            activeSummaryID = id
            generatedWeeklySummary = cachedWorkoutSummary(for: id)
            weeklySummaryGenerationFailed = false
        }

        guard generatedWeeklySummary == nil else { return }

        do {
            let summary = try await LLMService.shared.generateWorkoutSummary(
                context: context,
                profile: profileManager.profile,
                featuredActivity: activity,
                weeklyCount: weeklyCount,
                weeklyTotalDurationMinutes: totalMinutes,
                responseLanguage: LLMService.preferredResponseLanguage()
            )
            guard activeSummaryID == id else { return }
            generatedWeeklySummary = summary
            cacheWorkoutSummary(summary, for: id)
        } catch {
            print("[WorkoutDashboard] AI summary failed: \(error)")
            guard activeSummaryID == id else { return }
            weeklySummaryGenerationFailed = true
        }
    }

    private func weeklySummaryID(
        for activity: WorkoutStats.WorkoutActivity?,
        weeklyCount: Int,
        totalMinutes: Double
    ) -> String {
        let activityKey = activity?.key ?? "none"
        let activityCount = activity?.count ?? 0
        let activityMinutes = Int((activity?.totalDurationMinutes ?? 0).rounded())
        let language = LLMService.preferredResponseLanguage().displayName
        return [
            "v2",
            language,
            context.phase.rawValue,
            "\(context.dayInPhase)",
            activityKey,
            "\(activityCount)",
            "\(activityMinutes)",
            "\(weeklyCount)",
            "\(Int(totalMinutes.rounded()))"
        ].joined(separator: "|")
    }

    private func cachedWorkoutSummary(for id: String) -> String? {
        UserDefaults.standard.string(forKey: workoutSummaryCacheKey(for: id))
    }

    private func cacheWorkoutSummary(_ summary: String, for id: String) {
        UserDefaults.standard.set(summary, forKey: workoutSummaryCacheKey(for: id))
    }

    private func workoutSummaryCacheKey(for id: String) -> String {
        "workout.weekly.ai_summary.\(id)"
    }

    private func workoutTitleKey(for activity: WorkoutStats.WorkoutActivity) -> String {
        switch workoutActivityKind(for: activity) {
        case .climbing:
            return "workout.title.climbing"
        case .walking:
            return "workout.title.walking"
        case .running:
            return "workout.title.running"
        case .yoga:
            return "workout.title.yoga"
        case .cycling:
            return "workout.title.cycling"
        case .swimming:
            return "workout.title.swimming"
        case .strength:
            return "workout.title.strength"
        case .flexibility:
            return "workout.title.flexibility"
        case .dance:
            return "workout.title.dance"
        case .ballSports:
            return "workout.title.ball_sports"
        case .cardio:
            return "workout.title.cardio"
        case .other:
            return "workout.title.steady_rhythm"
        }
    }

    private func workoutMomentumLabel(count: Int, minutes: Double) -> String {
        switch count {
        case 0:
            return String(localized: "workout.title.recovery")
        case 1...2 where minutes < 60:
            return String(localized: "workout.title.light_activity")
        case 1...3:
            return String(localized: "workout.title.rhythm_building")
        default:
            return String(localized: "workout.title.steady_rhythm")
        }
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        Text(title)
            .font(.system(size: Theme.cardTitleSize, weight: .semibold))
            .foregroundStyle(Theme.accent)
    }
}

    @ViewBuilder
    private func workoutPosterImage(for activity: WorkoutStats.WorkoutActivity?, isLoading: Bool) -> some View {
        if isLoading {
            workoutPosterLoadingPlaceholder
        } else {
            workoutPosterArt(for: activity.map(workoutActivityKind(for:)) ?? .other)
        }
    }

    private var workoutPosterLoadingPlaceholder: some View {
        ZStack {
            Theme.peachBlush
                .grainTexture(intensity: .subtle, seed: 533)
            TypingIndicatorView()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    private func workoutPosterArt(for kind: WorkoutActivityKind) -> some View {
        WorkoutPosterArtView(kind: kind)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)
    }

    private func workoutStatsStrip(totalMinutes: Double, weeklyCount: Int) -> some View {
        HStack(spacing: 0) {
            workoutPosterStat(value: formatDurationCompact(totalMinutes), label: String(localized: "workout.metric.weekly_total_duration"), isTrailing: false)

            Rectangle()
                .fill(Theme.textSecondary.opacity(0.20))
                .frame(width: 2, height: 50)
                .padding(.horizontal, 28)

            workoutPosterStat(value: "\(weeklyCount)", label: String(localized: "workout.metric.workout_count"), isTrailing: true)
        }
        .padding(.top, 2)
    }

    private func workoutPosterStat(value: String, label: String, isTrailing: Bool) -> some View {
        let horizontalAlignment: HorizontalAlignment = isTrailing ? .trailing : .leading
        let frameAlignment: Alignment = isTrailing ? .trailing : .leading
        return VStack(alignment: horizontalAlignment, spacing: 3) {
            Text(value)
                .font(Theme.itim(size: 34))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(Theme.itim(size: 14))
                .foregroundStyle(Theme.textSecondary.opacity(0.62))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func workoutCategoryRows(activities: [WorkoutStats.WorkoutActivity], totalMinutes: Double) -> some View {
        VStack(spacing: 16) {
            ForEach(activities.prefix(5), id: \.key) { activity in
                workoutCategoryRow(activity: activity, totalMinutes: totalMinutes, tint: Theme.accent)
            }
        }
    }

    private func workoutCategoryRow(
        activity: WorkoutStats.WorkoutActivity,
        totalMinutes: Double,
        tint: Color
    ) -> some View {
        let minutes = activity.totalDurationMinutes ?? 0
        let share = totalMinutes > 0 ? min(max(minutes / totalMinutes, 0.04), 1) : 0.04
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: workoutIconName(for: activity))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.peachBlush)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(localizedActivityName(for: activity))
                        .font(Theme.itim(size: 22))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(String(format: String(localized: "workout.category.count_format"), activity.count))
                        .font(Theme.itim(size: 14))
                        .foregroundStyle(Theme.textSecondary.opacity(0.68))
                    Spacer()
                }

                HStack(alignment: .top, spacing: 14) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.peachBlush.opacity(0.72))
                            Capsule()
                                .fill(tint)
                                .frame(width: proxy.size.width * CGFloat(share))
                        }
                    }
                    .frame(height: 9)
                    .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatDurationCompact(minutes))
                            .font(Theme.itim(size: 20))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(String(localized: "workout.category.total"))
                            .font(Theme.itim(size: 14))
                            .foregroundStyle(Theme.textSecondary.opacity(0.55))
                    }
                    .frame(width: 66, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: String(localized: "workout.category.accessibility_format"), localizedActivityName(for: activity), activity.count, formatDurationCompact(minutes)))
    }

    private func sortedWorkoutActivities(_ activities: [WorkoutStats.WorkoutActivity]) -> [WorkoutStats.WorkoutActivity] {
        activities.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            let lhsDuration = lhs.totalDurationMinutes ?? 0
            let rhsDuration = rhs.totalDurationMinutes ?? 0
            if lhsDuration != rhsDuration {
                return lhsDuration > rhsDuration
            }
            return lhs.key < rhs.key
        }
    }

    private func workoutIconName(for activity: WorkoutStats.WorkoutActivity) -> String {
        switch workoutActivityKind(for: activity) {
        case .climbing:
            return "figure.climbing"
        case .walking:
            return "figure.walk"
        case .running:
            return "figure.run"
        case .yoga:
            return "figure.mind.and.body"
        case .cycling:
            return "figure.outdoor.cycle"
        case .swimming:
            return "figure.pool.swim"
        case .strength:
            return "dumbbell"
        case .flexibility:
            return "figure.cooldown"
        case .dance:
            return "figure.dance"
        case .ballSports:
            return "sportscourt"
        case .cardio:
            return "heart"
        case .other:
            return "figure.mixed.cardio"
        }
    }

    private func localizedActivityName(for activity: WorkoutStats.WorkoutActivity) -> String {
        switch workoutActivityKind(for: activity) {
        case .climbing:
            return String(localized: "workout.activity.climbing")
        case .walking:
            return String(localized: "workout.activity.walking")
        case .running:
            return String(localized: "workout.activity.running")
        case .yoga:
            return String(localized: "workout.activity.yoga")
        case .cycling:
            return String(localized: "workout.activity.cycling")
        case .swimming:
            return String(localized: "workout.activity.swimming")
        case .strength:
            return String(localized: "workout.activity.traditional_strength_training")
        case .flexibility:
            return String(localized: "workout.activity.flexibility")
        case .dance, .ballSports, .cardio, .other:
            return activity.name
        }
    }

    private func workoutActivityKind(for activity: WorkoutStats.WorkoutActivity) -> WorkoutActivityKind {
        let key = activity.key.lowercased()
        let text = "\(activity.key) \(activity.name)".lowercased()

        switch key {
        case "climbing":
            return .climbing
        case "walking", "hiking":
            return .walking
        case "running", "track_and_field", "wheelchair_run_pace":
            return .running
        case "yoga", "mind_and_body", "pilates", "tai_chi", "barre":
            return .yoga
        case "cycling", "hand_cycling", "swim_bike_run":
            return .cycling
        case "swimming", "water_fitness", "water_sports", "water_polo", "underwater_diving":
            return .swimming
        case "functional_strength_training", "traditional_strength_training", "core_training":
            return .strength
        case "flexibility", "preparation_and_recovery", "cooldown":
            return .flexibility
        case "dance", "dance_inspired_training", "cardio_dance", "social_dance":
            return .dance
        case "badminton", "baseball", "basketball", "cricket", "golf", "handball", "hockey", "lacrosse", "paddle_sports", "pickleball", "racquetball", "rugby", "soccer", "softball", "squash", "table_tennis", "tennis", "volleyball":
            return .ballSports
        case "cross_training", "elliptical", "high_intensity_interval_training", "jump_rope", "mixed_cardio", "mixed_metabolic_cardio_training", "stair_climbing", "stairs", "step_training":
            return .cardio
        default:
            break
        }

        if text.contains("攀岩") || text.contains("climb") { return .climbing }
        if text.contains("步行") || text.contains("散步") || text.contains("徒步") || text.contains("walk") || text.contains("hik") { return .walking }
        if text.contains("跑") || text.contains("run") { return .running }
        if text.contains("瑜伽") || text.contains("身心") || text.contains("普拉提") || text.contains("太极") || text.contains("yoga") || text.contains("pilates") { return .yoga }
        if text.contains("骑") || text.contains("cycling") || text.contains("bike") { return .cycling }
        if text.contains("游泳") || text.contains("水") || text.contains("swim") { return .swimming }
        if text.contains("力量") || text.contains("核心") || text.contains("strength") { return .strength }
        if text.contains("拉伸") || text.contains("柔韧") || text.contains("stretch") || text.contains("flexibility") { return .flexibility }
        if text.contains("舞") || text.contains("dance") { return .dance }
        if text.contains("球") || text.contains("ball") || text.contains("tennis") { return .ballSports }
        if text.contains("有氧") || text.contains("hiit") || text.contains("cardio") { return .cardio }
        return .other
    }

    private func workoutMetricPill(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.cardBackgroundSolid.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatDurationCompact(_ minutes: Double) -> String {
        let roundedMinutes = max(0, Int(minutes.rounded()))
        let hours = roundedMinutes / 60
        let mins = roundedMinutes % 60
        if hours > 0, mins > 0 {
            return "\(hours)h\(mins)min"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(mins)min"
    }

}

fileprivate enum WorkoutActivityKind {
    case climbing
    case walking
    case running
    case yoga
    case cycling
    case swimming
    case strength
    case flexibility
    case dance
    case ballSports
    case cardio
    case other
}

private struct WorkoutPosterArtView: View {
    let kind: WorkoutActivityKind

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Theme.peachBlush
                    .grainTexture(intensity: .subtle, seed: 533)

                switch kind {
                case .climbing:
                    climbingArt(side: side)
                case .walking:
                    walkingArt(side: side)
                case .running:
                    runningArt(side: side)
                case .yoga, .flexibility:
                    yogaArt(side: side)
                case .cycling:
                    cyclingArt(side: side)
                case .swimming:
                    swimmingArt(side: side)
                case .strength:
                    strengthArt(side: side)
                case .dance:
                    danceArt(side: side)
                case .ballSports:
                    ballSportsArt(side: side)
                case .cardio:
                    cardioArt(side: side)
                case .other:
                    mixedArt(side: side)
                }
            }
        }
    }

    private func climbingArt(side: CGFloat) -> some View {
        ZStack {
            climbingHold(
                fill: Color(red: 245/255, green: 215/255, blue: 39/255),
                highlight: Color(red: 195/255, green: 171/255, blue: 30/255),
                size: CGSize(width: side * 0.40, height: side * 0.25),
                x: side * 0.36,
                y: side * 0.28,
                rotation: -128
            )

            climbingHold(
                fill: Color(red: 190/255, green: 79/255, blue: 120/255),
                highlight: Color(red: 136/255, green: 52/255, blue: 85/255),
                size: CGSize(width: side * 0.20, height: side * 0.14),
                x: side * 0.77,
                y: side * 0.23,
                rotation: 138
            )

            climbingHold(
                fill: Color(red: 107/255, green: 130/255, blue: 218/255),
                highlight: Color(red: 55/255, green: 73/255, blue: 149/255),
                size: CGSize(width: side * 0.15, height: side * 0.23),
                x: side * 0.19,
                y: side * 0.63,
                rotation: 8
            )

            climbingHold(
                fill: Color(red: 252/255, green: 79/255, blue: 112/255),
                highlight: Color(red: 255/255, green: 141/255, blue: 161/255),
                size: CGSize(width: side * 0.31, height: side * 0.17),
                x: side * 0.45,
                y: side * 0.77,
                rotation: -165
            )

            climbingHold(
                fill: Color(red: 170/255, green: 186/255, blue: 73/255),
                highlight: Color(red: 132/255, green: 153/255, blue: 56/255),
                size: CGSize(width: side * 0.31, height: side * 0.11),
                x: side * 0.75,
                y: side * 0.60,
                rotation: -24
            )
        }
    }

    private func walkingArt(side: CGFloat) -> some View {
        ZStack {
            posterPath(side: side, color: Color(red: 116/255, green: 156/255, blue: 93/255))
                .trim(from: 0.04, to: 0.95)
                .stroke(style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round))
                .opacity(0.62)

            footprint(side: side, x: 0.30, y: 0.35, rotation: -18, color: Color(red: 252/255, green: 111/255, blue: 120/255))
            footprint(side: side, x: 0.65, y: 0.61, rotation: 16, color: Color(red: 107/255, green: 130/255, blue: 218/255))
            footprint(side: side, x: 0.43, y: 0.76, rotation: -12, color: Color(red: 245/255, green: 215/255, blue: 39/255))

            Image(systemName: "figure.walk")
                .font(.system(size: side * 0.32, weight: .medium))
                .foregroundStyle(Color(red: 63/255, green: 83/255, blue: 69/255))
                .position(x: side * 0.50, y: side * 0.49)
        }
    }

    private func runningArt(side: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3) { index in
                Capsule()
                    .stroke(Color.white.opacity(0.72), lineWidth: side * 0.018)
                    .frame(width: side * (0.72 - CGFloat(index) * 0.12), height: side * (0.42 - CGFloat(index) * 0.06))
                    .rotationEffect(.degrees(-12))
                    .position(x: side * 0.50, y: side * 0.56)
            }
            posterBlob(side: side, fill: Color(red: 252/255, green: 111/255, blue: 120/255), size: side * 0.22, x: 0.34, y: 0.40)
            posterBlob(side: side, fill: Color(red: 245/255, green: 215/255, blue: 39/255), size: side * 0.16, x: 0.63, y: 0.47)
            Image(systemName: "figure.run")
                .font(.system(size: side * 0.28, weight: .medium))
                .foregroundStyle(Color(red: 63/255, green: 83/255, blue: 69/255))
                .position(x: side * 0.52, y: side * 0.56)
        }
    }

    private func yogaArt(side: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 245/255, green: 215/255, blue: 39/255).opacity(0.90))
                .frame(width: side * 0.26, height: side * 0.26)
                .position(x: side * 0.70, y: side * 0.28)
            RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
                .fill(Color(red: 107/255, green: 130/255, blue: 218/255))
                .frame(width: side * 0.62, height: side * 0.13)
                .rotationEffect(.degrees(-7))
                .position(x: side * 0.48, y: side * 0.72)
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: side * 0.32, weight: .regular))
                .foregroundStyle(Color(red: 63/255, green: 83/255, blue: 69/255))
                .position(x: side * 0.45, y: side * 0.52)
        }
    }

    private func cyclingArt(side: CGFloat) -> some View {
        ZStack {
            wheel(side: side, x: 0.32, y: 0.64)
            wheel(side: side, x: 0.70, y: 0.64)
            Path { path in
                path.move(to: CGPoint(x: side * 0.32, y: side * 0.64))
                path.addLine(to: CGPoint(x: side * 0.46, y: side * 0.42))
                path.addLine(to: CGPoint(x: side * 0.57, y: side * 0.64))
                path.addLine(to: CGPoint(x: side * 0.70, y: side * 0.64))
                path.move(to: CGPoint(x: side * 0.46, y: side * 0.42))
                path.addLine(to: CGPoint(x: side * 0.55, y: side * 0.42))
            }
            .stroke(Color(red: 63/255, green: 83/255, blue: 69/255), style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round, lineJoin: .round))
            posterBlob(side: side, fill: Color(red: 252/255, green: 111/255, blue: 120/255), size: side * 0.14, x: 0.53, y: 0.34)
        }
    }

    private func swimmingArt(side: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4) { index in
                wave(side: side, y: 0.34 + CGFloat(index) * 0.13)
                    .stroke(Color(red: 84/255, green: 132/255, blue: 196/255).opacity(0.82), style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
            }
            Circle()
                .fill(Color(red: 245/255, green: 215/255, blue: 39/255))
                .frame(width: side * 0.18, height: side * 0.18)
                .position(x: side * 0.30, y: side * 0.28)
        }
    }

    private func strengthArt(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.03)
                .fill(Color(red: 63/255, green: 83/255, blue: 69/255))
                .frame(width: side * 0.56, height: side * 0.045)
                .position(x: side * 0.50, y: side * 0.52)
            ForEach([0.25, 0.32, 0.68, 0.75], id: \.self) { x in
                RoundedRectangle(cornerRadius: side * 0.025)
                    .fill(x < 0.5 ? Color(red: 107/255, green: 130/255, blue: 218/255) : Color(red: 252/255, green: 111/255, blue: 120/255))
                    .frame(width: side * 0.07, height: side * 0.25)
                    .position(x: side * x, y: side * 0.52)
            }
            posterBlob(side: side, fill: Color(red: 245/255, green: 215/255, blue: 39/255), size: side * 0.18, x: 0.50, y: 0.28)
        }
    }

    private func danceArt(side: CGFloat) -> some View {
        ZStack {
            posterBlob(side: side, fill: Color(red: 252/255, green: 111/255, blue: 120/255), size: side * 0.25, x: 0.35, y: 0.62)
            posterBlob(side: side, fill: Color(red: 107/255, green: 130/255, blue: 218/255), size: side * 0.20, x: 0.67, y: 0.38)
            Image(systemName: "music.note")
                .font(.system(size: side * 0.28, weight: .bold))
                .foregroundStyle(Color(red: 63/255, green: 83/255, blue: 69/255))
                .rotationEffect(.degrees(-14))
                .position(x: side * 0.48, y: side * 0.48)
        }
    }

    private func ballSportsArt(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.04, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: side * 0.018)
                .frame(width: side * 0.72, height: side * 0.46)
                .position(x: side * 0.50, y: side * 0.52)
            Rectangle()
                .fill(Color.white.opacity(0.62))
                .frame(width: side * 0.018, height: side * 0.46)
                .position(x: side * 0.50, y: side * 0.52)
            Circle()
                .fill(Color(red: 245/255, green: 215/255, blue: 39/255))
                .frame(width: side * 0.20, height: side * 0.20)
                .overlay(Circle().stroke(Color(red: 63/255, green: 83/255, blue: 69/255).opacity(0.45), lineWidth: side * 0.012))
                .position(x: side * 0.65, y: side * 0.38)
        }
    }

    private func cardioArt(side: CGFloat) -> some View {
        ZStack {
            posterBlob(side: side, fill: Color(red: 252/255, green: 111/255, blue: 120/255), size: side * 0.30, x: 0.38, y: 0.42)
            posterBlob(side: side, fill: Color(red: 245/255, green: 215/255, blue: 39/255), size: side * 0.18, x: 0.70, y: 0.66)
            Path { path in
                path.move(to: CGPoint(x: side * 0.18, y: side * 0.55))
                path.addLine(to: CGPoint(x: side * 0.32, y: side * 0.55))
                path.addLine(to: CGPoint(x: side * 0.40, y: side * 0.38))
                path.addLine(to: CGPoint(x: side * 0.51, y: side * 0.72))
                path.addLine(to: CGPoint(x: side * 0.62, y: side * 0.48))
                path.addLine(to: CGPoint(x: side * 0.82, y: side * 0.48))
            }
            .stroke(Color(red: 63/255, green: 83/255, blue: 69/255), style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round, lineJoin: .round))
        }
    }

    private func mixedArt(side: CGFloat) -> some View {
        ZStack {
            climbingHold(
                fill: Color(red: 245/255, green: 215/255, blue: 39/255),
                highlight: Color(red: 195/255, green: 171/255, blue: 30/255),
                size: CGSize(width: side * 0.32, height: side * 0.18),
                x: side * 0.35,
                y: side * 0.34,
                rotation: -20
            )
            posterBlob(side: side, fill: Color(red: 107/255, green: 130/255, blue: 218/255), size: side * 0.20, x: 0.66, y: 0.50)
            posterBlob(side: side, fill: Color(red: 252/255, green: 111/255, blue: 120/255), size: side * 0.24, x: 0.42, y: 0.72)
        }
    }

    private func climbingHold(
        fill: Color,
        highlight: Color,
        size: CGSize,
        x: CGFloat,
        y: CGFloat,
        rotation: Double
    ) -> some View {
        ZStack {
            Ellipse()
                .fill(fill)
            Ellipse()
                .fill(highlight.opacity(0.42))
                .frame(width: size.width * 0.44, height: size.height * 0.70)
                .offset(x: -size.width * 0.08, y: -size.height * 0.03)
                .rotationEffect(.degrees(12))
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(rotation))
        .position(x: x, y: y)
    }

    private func posterBlob(side: CGFloat, fill: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(fill.opacity(0.92))
            .frame(width: size, height: size)
            .position(x: side * x, y: side * y)
    }

    private func footprint(side: CGFloat, x: CGFloat, y: CGFloat, rotation: Double, color: Color) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: side * 0.14, height: side * 0.23)
            .rotationEffect(.degrees(rotation))
            .position(x: side * x, y: side * y)
    }

    private func wheel(side: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .stroke(Color(red: 63/255, green: 83/255, blue: 69/255), lineWidth: side * 0.025)
            .background(Circle().fill(Color.white.opacity(0.42)))
            .frame(width: side * 0.25, height: side * 0.25)
            .position(x: side * x, y: side * y)
    }

    private func posterPath(side: CGFloat, color: Color) -> Path {
        Path { path in
            path.move(to: CGPoint(x: side * 0.22, y: side * 0.25))
            path.addCurve(
                to: CGPoint(x: side * 0.72, y: side * 0.78),
                control1: CGPoint(x: side * 0.72, y: side * 0.22),
                control2: CGPoint(x: side * 0.22, y: side * 0.64)
            )
        }
    }

    private func wave(side: CGFloat, y: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: side * 0.18, y: side * y))
            path.addCurve(
                to: CGPoint(x: side * 0.48, y: side * y),
                control1: CGPoint(x: side * 0.26, y: side * (y - 0.08)),
                control2: CGPoint(x: side * 0.40, y: side * (y + 0.08))
            )
            path.addCurve(
                to: CGPoint(x: side * 0.82, y: side * y),
                control1: CGPoint(x: side * 0.58, y: side * (y - 0.08)),
                control2: CGPoint(x: side * 0.72, y: side * (y + 0.08))
            )
        }
    }

}

#Preview {
    WorkoutDashboardView(
        context: MockData.lutealContext,
        statsOverride: MockData.climbingWorkoutStats
    )
}
