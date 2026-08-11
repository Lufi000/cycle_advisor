import SwiftUI

struct HomeSideMenuPanel: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label(String(localized: "profile.title"), systemImage: "person.crop.circle.fill")
                    }
                    NavigationLink {
                        SubscriptionView()
                    } label: {
                        Label(String(localized: "subscription.title"), systemImage: "sparkles")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(String(localized: "tab.settings"), systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle(String(localized: "sidebar.title"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Theme.cardBackgroundSolid)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeOut(duration: 0.26)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel(String(localized: "sidebar.close_a11y"))
                }
            }
        }
    }
}

#Preview {
    HomeSideMenuPanel(isPresented: .constant(true))
}
