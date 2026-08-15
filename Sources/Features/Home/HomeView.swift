import SwiftUI

struct HomeView: View {
    var viewModel: HomeViewModel

    @AppStorage("displayName") private var displayName = "Lufi"
    @AppStorage("hasAskedDisplayName") private var hasAskedDisplayName = false
    @State private var isSideMenuOpen = false
    @State private var healthRefreshRotation: Double = 0
    @State private var isDisplayNameSheetPresented = false
    @State private var draftDisplayName = ""
    @State private var inspectedPhase: CyclePhase?

    private var context: CycleContext { viewModel.context }
    private let engine = CyclePhaseEngine()
    private var displayedPhase: CyclePhase { inspectedPhase ?? context.phase }
    private var homeMutedText: Color { Color.black.opacity(0.50) }
    private var homeSoftText: Color { Color.black.opacity(0.28) }

    private var sideMenuWidth: CGFloat {
        min(320, UIScreen.main.bounds.width * 0.82)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        homeGreetingHeader
                        cycleStageHeader
                        healthDashboard
                        periodSymptomsEntry
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .background(
                    Theme.background
                        .grainTexture(intensity: .subtle, seed: 100)
                        .ignoresSafeArea()
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(isSideMenuOpen ? .hidden : .visible, for: .navigationBar)
                .toolbar(isSideMenuOpen ? .hidden : .visible, for: .tabBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.easeOut(duration: 0.28)) {
                                isSideMenuOpen = true
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .accessibilityLabel(String(localized: "sidebar.open_a11y"))
                    }
                }
                .task { await viewModel.load() }
                .onChange(of: context.cycleDay) { _, _ in
                    inspectedPhase = nil
                }
                .onAppear {
                    guard !hasAskedDisplayName else { return }
                    draftDisplayName = sanitizedDisplayName
                    isDisplayNameSheetPresented = true
                }
                .sheet(isPresented: $isDisplayNameSheetPresented) {
                    DisplayNameOnboardingView(
                        draftName: $draftDisplayName,
                        onSave: {
                            let trimmed = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                            displayName = trimmed.isEmpty ? "Lufi" : trimmed
                            hasAskedDisplayName = true
                            isDisplayNameSheetPresented = false
                        },
                        onSkip: {
                            hasAskedDisplayName = true
                            isDisplayNameSheetPresented = false
                        }
                    )
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                }
            }

            if isSideMenuOpen {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.26)) {
                            isSideMenuOpen = false
                        }
                    }
                    .transition(.opacity)

                HStack(spacing: 0) {
                    HomeSideMenuPanel(isPresented: $isSideMenuOpen)
                        .frame(width: sideMenuWidth)
                        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 14, x: 6, y: 0)
                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .leading))
                .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.28), value: isSideMenuOpen)
    }

    // MARK: - Period Symptoms Entry

    @ViewBuilder
    private var periodSymptomsEntry: some View {
        let symptoms = context.menstrualSymptoms
        if context.phase == .menstrual, !symptoms.activeSymptoms.isEmpty {
            NavigationLink {
                PeriodDetailView(
                    symptoms: symptoms,
                    phase: context.phase,
                    dayInPhase: context.dayInPhase,
                    showsFlow: false
                )
                .padding(16)
                .background(
                    Theme.background
                        .grainTexture(intensity: .subtle, seed: 670)
                        .ignoresSafeArea()
                )
                .navigationTitle(String(localized: "period.symptoms.title"))
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.phaseMenstrual)
                        .frame(width: 34, height: 34)
                        .background(Theme.phaseMenstrual.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("period.symptoms.title")
                            .font(Theme.itim(size: 22))
                            .foregroundStyle(Theme.textPrimary)
                        Text(String(format: String(localized: "period.symptoms.summary %lld"), Int64(symptoms.activeSymptoms.count)))
                            .font(Theme.itim(size: 16))
                            .foregroundStyle(homeMutedText)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.65))
                }
                .grainCardStyle(seed: 667)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cycle Stage Header

    private var homeGreetingHeader: some View {
        Text(String(format: String(localized: "home.greeting %@"), sanitizedDisplayName))
            .font(Theme.itim(size: 36))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var sanitizedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Lufi" : trimmed
    }

    private var cycleStageHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                        Text(inspectedPhase == nil
                             ? (context.isPredicted ? String(localized: "phase.predicted_label") : String(localized: "home.cycle_stage.current"))
                             : String(localized: "home.cycle_stage.explore"))
                        .font(Theme.itim(size: 18))
                        .foregroundStyle(homeMutedText)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayedPhase.displayName)
                            .font(Theme.itim(size: 32))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                }
            }

            CycleTrackingTimelineView(
                context: context,
                engine: engine,
                selectedPhase: displayedPhase,
                onSelectPhase: { phase in
                    withAnimation(.easeOut(duration: 0.2)) {
                        inspectedPhase = phase == context.phase ? nil : phase
                    }
                }
            )

            Text(displayedPhase.description)
                .font(Theme.itim(size: 18))
                .lineSpacing(Theme.lineSpacing)
                .foregroundStyle(homeMutedText)
                .fixedSize(horizontal: false, vertical: true)

        }
        .grainCardStyle(seed: UInt64(displayedPhase.rawValue.utf8.reduce(0) { $0 + Int($1) }))
    }

    // MARK: - Health Dashboard

    private var healthDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("home.health_metrics.title")
                        .font(Theme.itim(size: 18))
                        .foregroundStyle(homeMutedText)
                    Text("home.health_metrics.today")
                        .font(Theme.itim(size: 28))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.linear(duration: 0.7)) {
                        healthRefreshRotation += 360
                    }
                    Task { @MainActor in
                        await Task.yield()
                        await viewModel.load(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(healthRefreshRotation), anchor: .center)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingHealthData)
                .accessibilityLabel(String(localized: "home.health_metrics.refresh_a11y"))
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                healthMetricCard(
                    metric: .hrv,
                    icon: "heart.fill",
                    label: "HRV",
                    value: context.healthMetrics.hrvCurrent.map { "\(Int($0))ms" } ?? "--",
                    trend: context.healthMetrics.hrvTrend,
                    color: Theme.phaseMenstrual
                )
                healthMetricCard(
                    metric: .daylight,
                    icon: "sun.max.fill",
                    label: String(localized: "home.health_metrics.daylight"),
                    value: context.healthMetrics.formattedDaylightDuration ?? "--",
                    trend: context.healthMetrics.daylightTrend,
                    color: Theme.phaseOvulation
                )
                healthMetricCard(
                    metric: .exercise,
                    icon: "figure.run",
                    label: String(localized: "home.health_metrics.exercise"),
                    value: context.healthMetrics.formattedExerciseDuration ?? "--",
                    trend: context.healthMetrics.exerciseTrend,
                    color: Theme.phaseFollicular
                )
                healthMetricCard(
                    metric: .steps,
                    icon: "figure.walk",
                    label: String(localized: "home.health_metrics.steps"),
                    value: context.healthMetrics.formattedSteps ?? "--",
                    trend: context.healthMetrics.activityTrend,
                    color: Theme.phaseLuteal
                )
            }
        }
        .grainCardStyle(seed: 1)
    }

    private func healthMetricCard(metric: HealthMetricKind, icon: String, label: String, value: String, trend: Trend?, color: Color) -> some View {
        NavigationLink {
            HealthMetricDetailView(metric: metric, value: value, trend: trend, color: color)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 30, height: 30)
                        .background(color.opacity(0.13))
                        .clipShape(Circle())
                    Spacer(minLength: 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(Theme.itim(size: 28))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(label)
                        .font(Theme.itim(size: 16))
                        .foregroundStyle(homeMutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.peachBlush.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

}

private enum HealthMetricKind {
    case hrv
    case daylight
    case exercise
    case steps

    var title: String {
        switch self {
        case .hrv: return "HRV"
        case .daylight: return String(localized: "home.health_metrics.daylight")
        case .exercise: return String(localized: "home.health_metrics.exercise")
        case .steps: return String(localized: "home.health_metrics.steps")
        }
    }

    var iconName: String {
        switch self {
        case .hrv: return "heart.fill"
        case .daylight: return "sun.max.fill"
        case .exercise: return "figure.run"
        case .steps: return "figure.walk"
        }
    }

    var meaning: String {
        switch self {
        case .hrv: return String(localized: "health.metric.hrv.meaning")
        case .daylight: return String(localized: "health.metric.daylight.meaning")
        case .exercise: return String(localized: "health.metric.exercise.meaning")
        case .steps: return String(localized: "health.metric.steps.meaning")
        }
    }

    var source: String {
        switch self {
        case .hrv: return String(localized: "health.metric.hrv.source")
        case .daylight: return String(localized: "health.metric.daylight.source")
        case .exercise: return String(localized: "health.metric.exercise.source")
        case .steps: return String(localized: "health.metric.steps.source")
        }
    }
}

private struct HealthMetricDetailView: View {
    let metric: HealthMetricKind
    let value: String
    let trend: Trend?
    let color: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: metric.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 48, height: 48)
                        .background(color.opacity(0.13))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.title)
                            .font(Theme.itim(size: 18))
                            .foregroundStyle(Color.black.opacity(0.50))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(value)
                                .font(Theme.itim(size: 32))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .grainCardStyle(seed: 121)

                metricInfoBlock(title: String(localized: "health.metric.meaning.title"), body: metric.meaning, icon: "questionmark.circle")
                metricInfoBlock(title: String(localized: "health.metric.source.title"), body: metric.source, icon: "applewatch")

                DisclaimerView()
            }
            .padding(16)
        }
        .background(
            Theme.background
                .grainTexture(intensity: .subtle, seed: 122)
                .ignoresSafeArea()
        )
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricInfoBlock(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(Theme.itim(size: 22))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(body)
                .font(Theme.itim(size: 18))
                .lineSpacing(Theme.lineSpacing)
                .foregroundStyle(Color.black.opacity(0.50))
                .fixedSize(horizontal: false, vertical: true)
        }
        .grainCardStyle(seed: UInt64(title.utf8.reduce(0) { $0 + Int($1) }))
    }
}

private struct DisplayNameOnboardingView: View {
    @Binding var draftName: String
    let onSave: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("onboarding.display_name.title")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("onboarding.display_name.subtitle")
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(Theme.textSecondary)
            }

            TextField(String(localized: "settings.profile.display_name"), text: $draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.system(size: Theme.bodySize))
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.background.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button(action: onSkip) {
                    Text("onboarding.display_name.skip")
                        .font(.system(size: Theme.bodySize, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)

                Button(action: onSave) {
                    Text("onboarding.display_name.save")
                        .font(.system(size: Theme.bodySize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBackgroundSolid)
    }
}

// MARK: - Cycle Tracking Timeline

private struct CycleTrackingTimelineView: View {
    let context: CycleContext
    let engine: CyclePhaseEngine
    let selectedPhase: CyclePhase
    let onSelectPhase: (CyclePhase) -> Void
    private let segmentSpacing: CGFloat = 3

    private var durations: PhaseDurations {
        engine.phaseDurations(for: context.avgCycleLength)
    }

    private var currentProgress: CGFloat {
        let total = max(durations.total, 1)
        let clampedDay = min(max(context.cycleDay, 1), total)
        return CGFloat(clampedDay - 1) / CGFloat(max(total - 1, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let markerX = width * currentProgress

                ZStack(alignment: .leading) {
                    HStack(spacing: segmentSpacing) {
                        ForEach(CyclePhase.allCases, id: \.self) { phase in
                            Button {
                                onSelectPhase(phase)
                            } label: {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(phase.color.opacity(segmentOpacity(for: phase)))
                                    .overlay {
                                        if phase == selectedPhase {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(phase.color, lineWidth: 1.5)
                                        }
                                    }
                                    .frame(width: segmentWidth(for: phase, totalWidth: width), height: 18)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(phase.displayName)
                        }
                    }
                    .frame(height: 18)

                    Circle()
                        .fill(Theme.cardBackgroundSolid)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(context.phase.color, lineWidth: 4)
                        )
                        .shadow(color: context.phase.color.opacity(0.18), radius: 5, y: 2)
                        .offset(x: min(max(markerX - 13, 0), max(width - 26, 0)))

                    Text("D\(context.cycleDay)")
                        .font(Theme.itim(size: 12))
                        .foregroundStyle(context.phase.color)
                        .frame(width: 36, height: 18)
                        .background(Theme.cardBackgroundSolid.opacity(0.92))
                        .clipShape(Capsule())
                        .offset(x: min(max(markerX - 18, 0), max(width - 36, 0)), y: -29)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .bottomLeading)
            }
            .frame(height: 48)

            GeometryReader { proxy in
                let width = proxy.size.width
                let labelWidth: CGFloat = 56
                let labelX = phaseMidpoint(for: selectedPhase, totalWidth: width)

                Text(selectedPhase.displayName)
                    .font(Theme.itim(size: 12))
                    .foregroundStyle(selectedPhase.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: labelWidth, height: 16)
                    .offset(x: min(max(labelX - labelWidth / 2, 0), max(width - labelWidth, 0)))
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: String(localized: "home.cycle_stage.a11y %lld %@"), Int64(context.cycleDay), context.phase.displayName))
    }

    private func segmentOpacity(for phase: CyclePhase) -> Double {
        if phase == selectedPhase { return 0.9 }
        if phase == context.phase { return 0.55 }
        return 0.28
    }

    private func segmentWidth(for phase: CyclePhase, totalWidth: CGFloat) -> CGFloat {
        let gapTotal = segmentSpacing * CGFloat(max(CyclePhase.allCases.count - 1, 0))
        let available = max(totalWidth - gapTotal, 1)
        let phaseDuration = durations.duration(for: phase)
        return available * CGFloat(phaseDuration) / CGFloat(max(durations.total, 1))
    }

    private func phaseMidpoint(for phase: CyclePhase, totalWidth: CGFloat) -> CGFloat {
        let phases = CyclePhase.allCases
        let precedingWidth = phases.prefix { $0 != phase }.reduce(CGFloat.zero) { partial, item in
            partial + segmentWidth(for: item, totalWidth: totalWidth) + segmentSpacing
        }
        return precedingWidth + segmentWidth(for: phase, totalWidth: totalWidth) / 2
    }
}

// MARK: - Notebook-style loading (pencil along wave)

/// 波浪笔迹路径，配合 `trim` 从左向右画出，像铅笔沿横格书写。
private struct GentleWaveRule: Shape {
    var cycles: CGFloat = 4.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let margin = max(1.0, rect.height * 0.1)
        let maxAmp = max(0, rect.height / 2 - margin)
        let amp = maxAmp * 0.92
        let w = rect.width
        let steps = max(28, Int(w))
        for i in 0...steps {
            let x = CGFloat(i) / CGFloat(steps) * w
            let t = (x / max(w, 1)) * cycles * 2 * .pi
            let y = midY + sin(t) * amp
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

/// 无建议占位格专用：波浪笔迹 loading（有内容的卡片用右上角 `···`）。
private struct NotebookLinesLoadingView: View {
    enum Style {
        case standard
        case compact
    }

    var style: Style = .standard

    private var visualScale: CGFloat {
        switch style {
        case .compact: return 1.0
        case .standard: return 2.0
        }
    }

    private var waveWidthFraction: CGFloat {
        switch style {
        case .compact: return 0.58
        case .standard: return 1.0
        }
    }

    private var contentHeight: CGFloat {
        let rowH = (style == .compact ? 9 : 12) * visualScale
        let pad = style == .compact ? 2.5 : 11
        return 2 + CGFloat(rowCount) * (rowH + pad)
    }

    private var rowCount: Int {
        switch style {
        case .standard: return 3
        case .compact: return 2
        }
    }

    private var cycleSeconds: TimeInterval {
        switch style {
        case .standard: return 7.2
        case .compact: return 5.6
        }
    }

    private var compactRowStartStagger: TimeInterval { 1.0 }

    private var compactStrokeDrawDuration: TimeInterval { 2.5 }

    private var compactCycleEndPause: TimeInterval { 0.6 }

    private var compactCyclePeriod: TimeInterval {
        TimeInterval(max(rowCount - 1, 0)) * compactRowStartStagger + compactStrokeDrawDuration + compactCycleEndPause
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t / cycleSeconds).truncatingRemainder(dividingBy: 1.0))
            let elapsedCompact = t.truncatingRemainder(dividingBy: compactCyclePeriod)

            GeometryReader { geo in
                let waveW = geo.size.width * waveWidthFraction
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        pencilWaveRow(
                            index: index,
                            phase: phase,
                            elapsedCompact: elapsedCompact,
                            waveWidth: rowWaveWidth(index: index, base: waveW),
                            referenceWaveWidth: waveW
                        )
                    }
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: contentHeight)
            .accessibilityHidden(true)
        }
    }

    private func rowWaveWidth(index: Int, base: CGFloat) -> CGFloat {
        if style == .compact && rowCount == 2 {
            return index == 0 ? base * 0.5 : base
        }
        return base
    }

    @ViewBuilder
    private func pencilWaveRow(
        index: Int,
        phase: CGFloat,
        elapsedCompact: TimeInterval,
        waveWidth: CGFloat,
        referenceWaveWidth: CGFloat
    ) -> some View {
        // 与最长行相同的「每像素」波纹密度；仅行宽变化时样式一致，只长短不同。
        let baseCycles = style == .compact ? 3.6 : 3.2
        let rawCycles = baseCycles * (waveWidth / max(referenceWaveWidth, 1))
        // 非 0.5 整数倍时 sin(cycles·2π)≠0，右端会悬在中线外；抬到最近 n/2 让最后一浪落回横线。
        let cycles = Self.cyclesEndingOnBaseline(rawCycles)
        let guide = Theme.textSecondary.opacity(0.0225)
        let pencil = Theme.textSecondary.opacity(0.14)
        let drawProgress: CGFloat = style == .compact
            ? compactStrokeDrawProgress(index: index, elapsed: elapsedCompact)
            : strokeDrawProgress(index: index, phase: phase)
        let wGuide = 1.05 * visualScale
        let wPencil = 2.05 * visualScale
        let lineGuide = StrokeStyle(lineWidth: wGuide, lineCap: .round, lineJoin: .round)
        let linePencil = StrokeStyle(lineWidth: wPencil, lineCap: .round, lineJoin: .round)
        let rowH = (style == .compact ? 9 : 12) * visualScale

        ZStack {
            GentleWaveRule(cycles: cycles)
                .stroke(guide, style: lineGuide)
            GentleWaveRule(cycles: cycles)
                .trim(from: 0, to: drawProgress)
                .stroke(pencil, style: linePencil)
        }
        .frame(width: waveWidth, height: rowH)
        .padding(.bottom, style == .compact ? 2.5 : 11)
    }

    private func compactStrokeDrawProgress(index: Int, elapsed: TimeInterval) -> CGFloat {
        let start = Double(index) * compactRowStartStagger
        let u = elapsed - start
        if u <= 0 {
            return 0
        }
        if u >= compactStrokeDrawDuration {
            return 1
        }
        return CGFloat(smoothstep(u / compactStrokeDrawDuration))
    }

    private func strokeDrawProgress(index: Int, phase: CGFloat) -> CGFloat {
        let n = CGFloat(max(rowCount, 1))
        let start = CGFloat(index) / n
        let end = CGFloat(index + 1) / n
        if phase <= start {
            return 0
        }
        if phase >= end {
            return 1
        }
        let u = (Double(phase) - Double(start)) * Double(n)
        return CGFloat(smoothstep(u))
    }

    private func smoothstep(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    /// `sin(cycles · 2π) = 0` iff `cycles` 为 0.5 的整数倍；此时左右端点落在同一条中心横线上。
    private static func cyclesEndingOnBaseline(_ raw: CGFloat) -> CGFloat {
        max(0.5, ceil(raw * 2) / 2)
    }
}

// MARK: - Mini loading (· · ·)

/// 卡片右上角迷你「···」动画；刷新健康数据时保留原有建议正文，仅作轻量提示。
private struct MiniEllipsisLoadingView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { i in
                Text(verbatim: "·")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(0.28 + 0.72 * dotOpacity(index: i))
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            phase = 0
            withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func dotOpacity(index: Int) -> Double {
        let adjusted = (Double(phase) * 3 - Double(index) * 0.32).truncatingRemainder(dividingBy: 1.0)
        let pulse = adjusted < 0.5 ? adjusted * 2 : (1.0 - adjusted) * 2
        return max(0.12, min(1.0, pulse))
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel())
}
