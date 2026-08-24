import SwiftUI
import UIKit
import Photos

struct WorkoutDashboardView: View {
    private var profileManager = UserProfileManager.shared
    let context: CycleContext
    private let statsOverride: WorkoutStats?
    @State private var selectedPeriod: WorkoutPeriod = .week
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
    private var hasWorkoutData: Bool {
        !stats.topActivities.isEmpty
            || (stats.weeklyWorkoutCount ?? 0) > 0
            || (stats.monthlyWorkoutCount ?? 0) > 0
            || (stats.yearlyWorkoutCount ?? 0) > 0
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

                VStack(spacing: 0) {
                    if hasWorkoutData {
                        periodHeader
                    }

                    ScrollView {
                        VStack(spacing: 12) {
                            if hasWorkoutData {
                                periodRhythmSection
                            } else {
                                emptyState
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, hasWorkoutData ? 12 : 24)
                        .padding(.bottom, 20)
                    }
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
        workoutCardShell(
            period: selectedPeriod,
            featuredActivity: nil,
            count: 0,
            totalMinutes: 0,
            displayActivities: [],
            showsShareButton: true
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkoutPeriod.allCases) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(period.displayName)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(selectedPeriod == period ? Color.white : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule()
                                    .fill(selectedPeriod == period ? Theme.accent : Theme.textSecondary.opacity(0.08))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// 顶部固定栏：周期切换 Tab + 当前周期的具体日期范围小字。
    private var periodHeader: some View {
        VStack(spacing: 6) {
            periodPicker

            Text(periodRangeText(for: selectedPeriod))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Theme.warmShell
                .grainTexture(intensity: .subtle, seed: 530)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// 当前周期的具体日期范围，如「8月18日 – 8月24日」。
    private func periodRangeText(for period: WorkoutPeriod) -> String {
        let calendar = Calendar.current
        let now = Date()
        let start: Date
        switch period {
        case .week:
            var mondayCalendar = calendar
            mondayCalendar.firstWeekday = 2
            start = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        case .year:
            start = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        case .recentWeek:
            start = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        case .recentMonth:
            start = calendar.date(byAdding: .day, value: -29, to: now) ?? now
        case .recentYear:
            start = calendar.date(byAdding: .day, value: -363, to: now) ?? now
        }
        let includeYear = period == .year || period == .recentYear
        return "\(shortDate(start, includeYear: includeYear)) – \(shortDate(now, includeYear: includeYear))"
    }

    private func shortDate(_ date: Date, includeYear: Bool = false) -> String {
        let formatter = DateFormatter()
        switch LanguageManager.shared.current {
        case .english:
            formatter.locale = Locale(identifier: "en_US")
        case .simplifiedChinese:
            formatter.locale = Locale(identifier: "zh_CN")
        case .system:
            formatter.locale = .current
        }
        formatter.setLocalizedDateFormatFromTemplate(includeYear ? "yMMMd" : "MMMd")
        return formatter.string(from: date)
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

    /// 无运动记录但已有活动数据时，把步数/运动分钟/活动热量放进统一卡片底部。
    private var activityMetricPillsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ], spacing: 8) {
            activityOnlyMetricPills
        }
    }

    private var periodRhythmSection: some View {
        let data = periodCardData(for: selectedPeriod)
        let summaryID = periodSummaryID(
            period: selectedPeriod,
            for: data.featuredActivity,
            count: data.count,
            totalMinutes: data.totalMinutes
        )

        return workoutCardShell(
            period: selectedPeriod,
            featuredActivity: data.featuredActivity,
            count: data.count,
            totalMinutes: data.totalMinutes,
            displayActivities: data.displayActivities,
            showsShareButton: true
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: summaryID) {
            await loadGeneratedPeriodSummary(
                id: summaryID,
                period: selectedPeriod,
                activity: data.featuredActivity,
                count: data.count,
                totalMinutes: data.totalMinutes
            )
        }
    }

    private func periodCardData(for period: WorkoutPeriod) -> (
        count: Int,
        totalMinutes: Double,
        displayActivities: [WorkoutStats.WorkoutActivity],
        featuredActivity: WorkoutStats.WorkoutActivity?
    ) {
        let activities: [WorkoutStats.WorkoutActivity]
        let count: Int
        let totalMinutes: Double
        switch period {
        case .week:
            activities = sortedWorkoutActivities(stats.calendarWeekActivities ?? [])
            count = stats.calendarWeekWorkoutCount ?? 0
            totalMinutes = stats.calendarWeekTotalDurationMinutes ?? 0
        case .month:
            activities = sortedWorkoutActivities(stats.calendarMonthActivities ?? [])
            count = stats.calendarMonthWorkoutCount ?? 0
            totalMinutes = stats.calendarMonthTotalDurationMinutes ?? 0
        case .year:
            activities = sortedWorkoutActivities(stats.calendarYearActivities ?? [])
            count = stats.calendarYearWorkoutCount ?? 0
            totalMinutes = stats.calendarYearTotalDurationMinutes ?? 0
        case .recentWeek:
            activities = sortedWorkoutActivities(stats.weeklyActivities ?? [])
            count = stats.weeklyWorkoutCount ?? 0
            totalMinutes = stats.weeklyTotalDurationMinutes ?? 0
        case .recentMonth:
            activities = sortedWorkoutActivities(stats.monthlyActivities ?? [])
            count = stats.monthlyWorkoutCount ?? 0
            totalMinutes = stats.monthlyTotalDurationMinutes ?? 0
        case .recentYear:
            activities = sortedWorkoutActivities(stats.yearlyActivities ?? [])
            count = stats.yearlyWorkoutCount ?? 0
            totalMinutes = stats.yearlyTotalDurationMinutes ?? 0
        }
        return (count, totalMinutes, activities, activities.first)
    }

    /// 运动卡片的统一外壳：与屏幕上展示的尺寸保持一致，导出时也复用同一套布局。
    private func workoutCardShell(
        period: WorkoutPeriod,
        featuredActivity: WorkoutStats.WorkoutActivity?,
        count: Int,
        totalMinutes: Double,
        displayActivities: [WorkoutStats.WorkoutActivity],
        showsShareButton: Bool = false,
        contentWidth: CGFloat = 264
    ) -> some View {
        VStack {
            workoutCardContent(
                period: period,
                featuredActivity: featuredActivity,
                count: count,
                totalMinutes: totalMinutes,
                displayActivities: displayActivities,
                showsShareButton: showsShareButton,
                contentWidth: contentWidth
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 24)
        .background(workoutPosterCardBackground)
    }

    private func workoutCardContent(
        period: WorkoutPeriod,
        featuredActivity: WorkoutStats.WorkoutActivity?,
        count: Int,
        totalMinutes: Double,
        displayActivities: [WorkoutStats.WorkoutActivity],
        showsShareButton: Bool = false,
        contentWidth: CGFloat = 313
    ) -> some View {
        let showsActivityMetrics = displayActivities.isEmpty && hasActivityMetrics
        let summaryID = periodSummaryID(period: period, for: featuredActivity, count: count, totalMinutes: totalMinutes)

        return VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Text(periodTitle(for: featuredActivity, count: count, minutes: totalMinutes))
                        .font(Theme.itim(size: 36))
                        .foregroundStyle(workoutPosterInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    if showsShareButton {
                        Spacer(minLength: 0)
                        workoutSaveButton { saveWorkoutCard() }
                    }
                }

                periodSummaryText(for: featuredActivity, count: count, period: period, summaryID: summaryID)
                    .frame(maxWidth: contentWidth, alignment: .leading)
            }

            if displayActivities.isEmpty {
                workoutParkArt()
            } else {
                workoutPosterImage(for: featuredActivity)
            }

            workoutStatsStrip(totalMinutes: totalMinutes, count: count, period: period)

            if showsActivityMetrics {
                activityMetricPillsGrid
            } else {
                workoutCategoryRows(activities: displayActivities, totalMinutes: totalMinutes)
            }
        }
        .frame(maxWidth: contentWidth)
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
        let data = periodCardData(for: selectedPeriod)
        guard let image = renderWorkoutCardImage(
            period: selectedPeriod,
            featuredActivity: data.featuredActivity,
            count: data.count,
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
        period: WorkoutPeriod,
        featuredActivity: WorkoutStats.WorkoutActivity?,
        count: Int,
        totalMinutes: Double,
        displayActivities: [WorkoutStats.WorkoutActivity]
    ) -> UIImage? {
        let content = workoutCardShell(
            period: period,
            featuredActivity: featuredActivity,
            count: count,
            totalMinutes: totalMinutes,
            displayActivities: displayActivities
        )
        .frame(width: exportedCardWidth)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage
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

    /// 与屏幕上运动卡片一致的可视宽度：ScrollView 左右各 16pt 内边距。
    private var exportedCardWidth: CGFloat {
        max(0, UIScreen.main.bounds.width - 32)
    }

    private func periodTitle(for activity: WorkoutStats.WorkoutActivity?, count: Int, minutes: Double) -> String {
        guard count > 0 else { return String(localized: "workout.title.recovery") }
        guard let activity else { return workoutMomentumLabel(count: count, minutes: minutes) }
        return NSLocalizedString(workoutTitleKey(for: activity), comment: "")
    }

    private func periodSummaryFallback(
        for activity: WorkoutStats.WorkoutActivity?,
        count: Int,
        period: WorkoutPeriod
    ) -> String {
        guard count > 0 else {
            switch period {
            case .week:
                return String(localized: "workout.summary.no_workouts")
            case .month:
                return String(localized: "workout.summary.no_workouts_month")
            case .year:
                return String(localized: "workout.summary.no_workouts_year")
            case .recentWeek:
                return String(localized: "workout.summary.no_workouts_recent_week")
            case .recentMonth:
                return String(localized: "workout.summary.no_workouts_recent_month")
            case .recentYear:
                return String(localized: "workout.summary.no_workouts_recent_year")
            }
        }
        switch period {
        case .week:
            return String(localized: "workout.summary.no_activity_type")
        case .month:
            return String(localized: "workout.summary.no_activity_type_month")
        case .year:
            return String(localized: "workout.summary.no_activity_type_year")
        case .recentWeek:
            return String(localized: "workout.summary.no_activity_type_recent_week")
        case .recentMonth:
            return String(localized: "workout.summary.no_activity_type_recent_month")
        case .recentYear:
            return String(localized: "workout.summary.no_activity_type_recent_year")
        }
    }

    @ViewBuilder
    private func periodSummaryText(
        for activity: WorkoutStats.WorkoutActivity?,
        count: Int,
        period: WorkoutPeriod,
        summaryID: String
    ) -> some View {
        if activeSummaryID == summaryID, let generatedWeeklySummary {
            Text(generatedWeeklySummary)
                .font(Theme.itim(size: 18))
                .foregroundStyle(workoutPosterMuted)
                .lineSpacing(5)
        } else {
            Text(periodSummaryFallback(for: activity, count: count, period: period))
                .font(Theme.itim(size: 18))
                .foregroundStyle(workoutPosterMuted)
                .lineSpacing(5)
        }
    }

    @MainActor
    private func loadGeneratedPeriodSummary(
        id: String,
        period: WorkoutPeriod,
        activity: WorkoutStats.WorkoutActivity?,
        count: Int,
        totalMinutes: Double
    ) async {
        guard count > 0, let activity else {
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
                count: count,
                totalDurationMinutes: totalMinutes,
                periodLabel: period.summaryPeriodLabel,
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

    private func periodSummaryID(
        period: WorkoutPeriod,
        for activity: WorkoutStats.WorkoutActivity?,
        count: Int,
        totalMinutes: Double
    ) -> String {
        let activityKey = activity?.key ?? "none"
        let activityCount = activity?.count ?? 0
        let activityMinutes = Int((activity?.totalDurationMinutes ?? 0).rounded())
        let language = LLMService.preferredResponseLanguage().displayName
        return [
            "v5",
            language,
            period.rawValue,
            context.phase.rawValue,
            "\(context.dayInPhase)",
            activityKey,
            "\(activityCount)",
            "\(activityMinutes)",
            "\(count)",
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
        "workout.period.ai_summary.\(id)"
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
            return ballSportsTitleKey(for: activity.key)
        case .cardio:
            return "workout.title.cardio"
        case .other:
            return "workout.title.steady_rhythm"
        }
    }

    /// 球类运动按具体项目给出更贴切的称号；未单独列出的球类回退到通用“球场”称号。
    private func ballSportsTitleKey(for activityKey: String) -> String {
        switch activityKey.lowercased() {
        case "tennis":
            return "workout.title.tennis"
        case "basketball":
            return "workout.title.basketball"
        case "badminton":
            return "workout.title.badminton"
        case "soccer":
            return "workout.title.soccer"
        case "volleyball":
            return "workout.title.volleyball"
        case "table_tennis":
            return "workout.title.table_tennis"
        case "golf":
            return "workout.title.golf"
        case "baseball", "softball":
            return "workout.title.baseball"
        default:
            return "workout.title.ball_sports"
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

    private func workoutPosterImage(for activity: WorkoutStats.WorkoutActivity?) -> some View {
        workoutPosterArt(for: activity)
    }

    private func workoutPosterArt(for activity: WorkoutStats.WorkoutActivity?) -> some View {
        WorkoutPosterArtView(
            kind: activity.map(workoutActivityKind(for:)) ?? .other,
            key: activity?.key
        )
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    private func workoutPosterArt(for kind: WorkoutActivityKind) -> some View {
        WorkoutPosterArtView(kind: kind, key: nil)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)
    }

    /// 无运动记录时的公园休息插画：坐在公园里放空，节奏的一部分。
    private func workoutParkArt() -> some View {
        WorkoutPosterArtView(kind: .other, assetName: "WorkoutPosterPark")
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)
    }

    private func workoutStatsStrip(totalMinutes: Double, count: Int, period: WorkoutPeriod) -> some View {
        HStack(spacing: 0) {
            workoutPosterStat(
                value: formatDurationCompact(totalMinutes),
                label: totalDurationLabel(for: period),
                isTrailing: false
            )

            Rectangle()
                .fill(Theme.textSecondary.opacity(0.20))
                .frame(width: 2, height: 50)
                .padding(.horizontal, 14)

            workoutPosterStat(
                value: "\(count)",
                label: String(localized: "workout.metric.workout_count"),
                isTrailing: true,
                fixedWidth: 58
            )
        }
        .padding(.top, 2)
    }

    private func totalDurationLabel(for period: WorkoutPeriod) -> String {
        switch period {
        case .week:
            return String(localized: "workout.metric.weekly_total_duration")
        case .month:
            return String(localized: "workout.metric.monthly_total_duration")
        case .year:
            return String(localized: "workout.metric.yearly_total_duration")
        case .recentWeek:
            return String(localized: "workout.metric.recent_week_total_duration")
        case .recentMonth:
            return String(localized: "workout.metric.recent_month_total_duration")
        case .recentYear:
            return String(localized: "workout.metric.recent_year_total_duration")
        }
    }

    @ViewBuilder
    private func workoutPosterStat(
        value: String,
        label: String,
        isTrailing: Bool,
        fixedWidth: CGFloat? = nil
    ) -> some View {
        let horizontalAlignment: HorizontalAlignment = isTrailing ? .trailing : .leading
        let frameAlignment: Alignment = isTrailing ? .trailing : .leading
        let content = VStack(alignment: horizontalAlignment, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                Text(value)
                    .font(Theme.itim(size: 34))
                    .lineLimit(1)
                Text(value)
                    .font(Theme.itim(size: 28))
                    .lineLimit(1)
                Text(value)
                    .font(Theme.itim(size: 22))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.itim(size: 14))
                .foregroundStyle(Theme.textSecondary.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        if let fixedWidth {
            content.frame(width: fixedWidth, alignment: frameAlignment)
        } else {
            content.frame(maxWidth: .infinity, alignment: frameAlignment)
        }
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
                    Text(activity.name)
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
                        ViewThatFits(in: .horizontal) {
                            Text(formatDurationCompact(minutes))
                                .font(Theme.itim(size: 20))
                                .lineLimit(1)
                            Text(formatDurationCompact(minutes))
                                .font(Theme.itim(size: 17))
                                .lineLimit(1)
                            Text(formatDurationCompact(minutes))
                                .font(Theme.itim(size: 14))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        Text(String(localized: "workout.category.total"))
                            .font(Theme.itim(size: 14))
                            .foregroundStyle(Theme.textSecondary.opacity(0.55))
                    }
                    .frame(width: 92, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: String(localized: "workout.category.accessibility_format"), activity.name, activity.count, formatDurationCompact(minutes)))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.cardBackgroundSolid.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatDurationCompact(_ minutes: Double) -> String {
        let roundedMinutes = max(0, Int(minutes.rounded()))
        let hours = roundedMinutes / 60
        let mins = roundedMinutes % 60
        if hours > 0, mins > 0 {
            return "\(hours)h \(mins)min"
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

fileprivate enum WorkoutPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year
    case recentWeek
    case recentMonth
    case recentYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week:
            return String(localized: "workout.period.week")
        case .month:
            return String(localized: "workout.period.month")
        case .year:
            return String(localized: "workout.period.year")
        case .recentWeek:
            return String(localized: "workout.period.recent_week")
        case .recentMonth:
            return String(localized: "workout.period.recent_month")
        case .recentYear:
            return String(localized: "workout.period.recent_year")
        }
    }

    /// AI 摘要文案里使用的周期称谓，如「本周」「本月」「今年」「近一周」。
    var summaryPeriodLabel: String {
        switch self {
        case .week:
            return String(localized: "workout.period_label.week")
        case .month:
            return String(localized: "workout.period_label.month")
        case .year:
            return String(localized: "workout.period_label.year")
        case .recentWeek:
            return String(localized: "workout.period_label.recent_week")
        case .recentMonth:
            return String(localized: "workout.period_label.recent_month")
        case .recentYear:
            return String(localized: "workout.period_label.recent_year")
        }
    }
}

private struct WorkoutPosterArtView: View {
    let kind: WorkoutActivityKind
    let key: String?
    let assetName: String?

    init(kind: WorkoutActivityKind, key: String? = nil, assetName: String? = nil) {
        self.kind = kind
        self.key = key
        self.assetName = assetName
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let assetName = Self.posterAssetName(kind: kind, key: key) {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
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
    }

    /// 优先按具体运动 key 匹配对应配图，其次按运动大类匹配；没有的就用自绘插画兜底。
    private static func posterAssetName(kind: WorkoutActivityKind, key: String?) -> String? {
        switch key?.lowercased() {
        case "tennis", "table_tennis":
            return "WorkoutPosterTennis"
        case "basketball":
            return "WorkoutPosterBasketball"
        case "badminton":
            return "WorkoutPosterBadminton"
        case "pickleball":
            return "WorkoutPosterPickleball"
        case "hiking":
            return "WorkoutPosterHiking"
        case "mind_and_body":
            return "WorkoutPosterMeditation"
        case "surfing_sports":
            return "WorkoutPosterSurfing"
        default:
            break
        }

        switch kind {
        case .climbing:
            return "WorkoutPosterBouldering"
        case .walking:
            return "WorkoutPosterWalk"
        case .running:
            return "WorkoutPosterRunning"
        case .ballSports:
            return "WorkoutPosterTennis"
        case .yoga:
            return "WorkoutPosterYoga"
        case .strength:
            return "WorkoutPosterStrength"
        case .cycling:
            return "WorkoutPosterCycling"
        case .swimming:
            return "WorkoutPosterSwimming"
        default:
            return nil
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
        statsOverride: MockData.tennisWorkoutStats
    )
}

#Preview("无运动记录") {
    WorkoutDashboardView(
        context: MockData.noHealthContext,
        statsOverride: WorkoutStats.empty
    )
}
