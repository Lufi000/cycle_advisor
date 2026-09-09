import SwiftUI

/// 手动基础体温录入（无手表用户的主路径）：滚轮选温 + 干扰标记多选 + 今日已测状态
struct BBTEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var whole: Int
    @State private var tenth: Int
    @State private var disturbances: Set<Disturbance>

    private let store = ConceptionStore.shared

    init() {
        // 已录过今日体温时预填，便于修改；默认 36.5
        if let existing = ConceptionStore.shared.manualEntry(for: Date()) {
            let totalTenths = Int((existing.celsius * 10).rounded())
            _whole = State(initialValue: min(max(totalTenths / 10, 35), 38))
            _tenth = State(initialValue: totalTenths % 10)
            _disturbances = State(initialValue: existing.disturbances)
        } else {
            _whole = State(initialValue: 36)
            _tenth = State(initialValue: 5)
            _disturbances = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("", selection: $whole) {
                            ForEach(35...38, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .accessibilityLabel(String(localized: "conception.bbt.celsius"))

                        Text(".")
                            .font(.system(size: Theme.bodySize, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Picker("", selection: $tenth) {
                            ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .accessibilityLabel(String(localized: "conception.bbt.celsius"))

                        Text("°C")
                            .font(.system(size: Theme.bodySize))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.leading, 4)
                    }
                    .frame(height: 120)
                    .listRowSeparator(.hidden)

                    if store.manualEntry(for: Date()) != nil {
                        Label(
                            String(localized: "conception.bbt.measured_today"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.accent)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("conception.bbt.celsius")
                }

                Section {
                    ForEach(Disturbance.allCases) { disturbance in
                        Toggle(disturbance.displayName, isOn: binding(for: disturbance))
                            .tint(Theme.accent)
                    }
                } header: {
                    Text("conception.bbt.disturbances")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(String(localized: "conception.bbt.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "conception.bbt.save")) { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func binding(for disturbance: Disturbance) -> Binding<Bool> {
        Binding(
            get: { disturbances.contains(disturbance) },
            set: { isOn in
                if isOn { disturbances.insert(disturbance) }
                else { disturbances.remove(disturbance) }
            }
        )
    }

    private func save() {
        // 滚轮取值恒在 35.0–38.0 合法区间内，无需校验失败路径
        let value = Double(whole) + Double(tenth) / 10
        _ = store.upsertManualTemperature(date: Date(), celsius: value, disturbances: disturbances)
        Task { await ConceptionInsightManager.shared.refresh() }
        dismiss()
    }
}

#Preview {
    BBTEntryView()
}
