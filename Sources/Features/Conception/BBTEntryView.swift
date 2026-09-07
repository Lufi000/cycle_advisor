import SwiftUI

/// 手动基础体温录入（无手表用户的主路径）：数字输入 + 干扰标记多选 + 今日已测状态
struct BBTEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var celsiusText: String
    @State private var disturbances: Set<Disturbance>
    @State private var showInvalidAlert = false

    private let store = ConceptionStore.shared

    init() {
        // 已录过今日体温时预填，便于修改
        if let existing = ConceptionStore.shared.manualEntry(for: Date()) {
            _celsiusText = State(initialValue: String(format: "%.1f", existing.celsius))
            _disturbances = State(initialValue: existing.disturbances)
        } else {
            _celsiusText = State(initialValue: "")
            _disturbances = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("36.5", text: $celsiusText)
                        .keyboardType(.decimalPad)

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
            .alert(String(localized: "conception.bbt.invalid"), isPresented: $showInvalidAlert) {
                Button(String(localized: "conception.onboarding.ok")) {}
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
        // 兼容逗号小数点（部分语言键盘）
        let normalized = celsiusText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized),
              store.upsertManualTemperature(date: Date(), celsius: value, disturbances: disturbances)
        else {
            showInvalidAlert = true
            return
        }
        Task { await ConceptionInsightManager.shared.refresh() }
        dismiss()
    }
}

#Preview {
    BBTEntryView()
}
