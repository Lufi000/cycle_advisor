import SwiftUI

struct WorkoutDashboardView: View {
    private var profileManager = UserProfileManager.shared
    let context: CycleContext

    private var stats: WorkoutStats {
        let storedStats = profileManager.profile.workoutStats
        #if DEBUG
        return storedStats.topActivities.isEmpty ? MockData.climbingWorkoutStats : storedStats
        #else
        return storedStats
        #endif
    }
    private var healthMetrics: HealthMetrics { context.healthMetrics }
    private var hasActivityMetrics: Bool {
        healthMetrics.exerciseMinutes != nil
            || healthMetrics.steps != nil
            || healthMetrics.activeCalories != nil
    }

    init(context: CycleContext) {
        self.context = context
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 46))
                .foregroundStyle(Theme.phaseFollicular)
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
            sectionHeader(icon: "figure.walk", title: String(localized: "workout.activity_only.section"))

            VStack(alignment: .leading, spacing: 5) {
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

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
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
        }
        .grainCardStyle(seed: 531)
    }

    private var weeklyRhythmSection: some View {
        let weeklyCount = stats.weeklyWorkoutCount ?? 0
        let totalMinutes = stats.weeklyTotalDurationMinutes ?? 0
        let featuredActivity = stats.weeklyActivities?.first ?? stats.topActivities.first
        let displayActivities = (stats.weeklyActivities?.isEmpty == false) ? (stats.weeklyActivities ?? []) : stats.topActivities
        let title = weeklyTitle(for: featuredActivity, weeklyCount: weeklyCount)

        return VStack {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(title)
                        .font(Theme.itim(size: 36))
                        .foregroundStyle(workoutPosterInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(weeklySummary(for: featuredActivity, weeklyCount: weeklyCount))
                        .font(Theme.itim(size: 18))
                        .foregroundStyle(workoutPosterMuted)
                        .lineSpacing(5)
                }

                workoutPosterImage

                workoutStatsStrip(totalMinutes: totalMinutes, weeklyCount: weeklyCount)

                workoutCategoryRows(activities: displayActivities, totalMinutes: totalMinutes)
            }
            .frame(maxWidth: 313)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 24)
        .background(workoutPosterCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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

    private func weeklyTitle(for activity: WorkoutStats.WorkoutActivity?, weeklyCount: Int) -> String {
        guard weeklyCount > 0 else { return String(localized: "workout.title.recovery") }
        guard let activity else { return workoutMomentumLabel(count: weeklyCount, minutes: stats.weeklyTotalDurationMinutes ?? 0) }
        return String(format: String(localized: "workout.title.activity_ace_format"), localizedActivityName(for: activity))
    }

    private func weeklySummary(for activity: WorkoutStats.WorkoutActivity?, weeklyCount: Int) -> String {
        guard weeklyCount > 0 else {
            return String(localized: "workout.summary.no_workouts")
        }
        guard let activity else {
            return String(localized: "workout.summary.no_activity_type")
        }
        return String(format: String(localized: "workout.summary.activity_insight_format"), localizedActivityName(for: activity))
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
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var workoutPosterImage: some View {
        WorkoutClimbingArtView()
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
            Circle()
                .fill(Theme.peachBlush)
                .frame(width: 52, height: 52)

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

    private func workoutIconName(for activity: WorkoutStats.WorkoutActivity) -> String {
        let text = "\(activity.key) \(activity.name)".lowercased()
        if text.contains("攀岩") || text.contains("climb") {
            return "figure.climbing"
        }
        if text.contains("步行") || text.contains("散步") || text.contains("walk") {
            return "figure.walk"
        }
        if text.contains("跑") || text.contains("run") {
            return "figure.run"
        }
        if text.contains("瑜伽") || text.contains("yoga") || text.contains("身心") {
            return "figure.mind.and.body"
        }
        if text.contains("骑") || text.contains("cycling") || text.contains("bike") {
            return "figure.outdoor.cycle"
        }
        if text.contains("游泳") || text.contains("swim") {
            return "figure.pool.swim"
        }
        if text.contains("力量") || text.contains("strength") {
            return "dumbbell"
        }
        if text.contains("拉伸") || text.contains("stretch") || text.contains("flexibility") {
            return "figure.cooldown"
        }
        return "figure.mixed.cardio"
    }

    private func localizedActivityName(for activity: WorkoutStats.WorkoutActivity) -> String {
        let text = "\(activity.key) \(activity.name)".lowercased()
        if text.contains("攀岩") || text.contains("climb") {
            return String(localized: "workout.activity.climbing")
        }
        if text.contains("步行") || text.contains("散步") || text.contains("walk") {
            return String(localized: "workout.activity.walking")
        }
        if text.contains("跑") || text.contains("run") {
            return String(localized: "workout.activity.running")
        }
        if text.contains("瑜伽") || text.contains("yoga") || text.contains("身心") {
            return String(localized: "workout.activity.yoga")
        }
        if text.contains("骑") || text.contains("cycling") || text.contains("bike") {
            return String(localized: "workout.activity.cycling")
        }
        if text.contains("游泳") || text.contains("swim") {
            return String(localized: "workout.activity.swimming")
        }
        if text.contains("力量") || text.contains("strength") {
            return String(localized: "workout.activity.traditional_strength_training")
        }
        if text.contains("拉伸") || text.contains("stretch") || text.contains("flexibility") {
            return String(localized: "workout.activity.flexibility")
        }
        return activity.name
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
            return String(format: String(localized: "workout.duration.hour_min_format"), hours, mins)
        }
        if hours > 0 {
            return String(format: String(localized: "workout.duration.hour_format"), hours)
        }
        return String(format: String(localized: "workout.duration.minute_format"), mins)
    }

}

private struct WorkoutClimbingArtView: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Theme.peachBlush
                    .grainTexture(intensity: .subtle, seed: 533)

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
}

#Preview {
    WorkoutDashboardView(context: MockData.lutealContext)
}
