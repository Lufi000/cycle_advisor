import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var homeViewModel = HomeViewModel()
    @State private var assistantViewModel = AssistantViewModel()

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $selectedTab) {
                    Tab(String(localized: "tab.home"), systemImage: "camera.macro", value: 0) {
                        HomeView(viewModel: homeViewModel)
                    }
                    Tab(String(localized: "tab.workout"), systemImage: "figure.run", value: 1) {
                        WorkoutDashboardView(context: homeViewModel.context)
                    }
                    Tab(String(localized: "tab.assistant"), systemImage: "sparkles", value: 2) {
                        AssistantView(viewModel: assistantViewModel, selectedTab: $selectedTab)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .tint(Theme.accent)
            } else {
                TabView(selection: $selectedTab) {
                    HomeView(viewModel: homeViewModel)
                        .tabItem {
                            Image(systemName: "camera.macro")
                            Text(String(localized: "tab.home"))
                        }
                        .tag(0)
                    WorkoutDashboardView(context: homeViewModel.context)
                        .tabItem {
                            Image(systemName: "figure.run")
                            Text(String(localized: "tab.workout"))
                        }
                        .tag(1)
                    AssistantView(viewModel: assistantViewModel, selectedTab: $selectedTab)
                        .tabItem {
                            Image(systemName: "sparkles")
                            Text(String(localized: "tab.assistant"))
                        }
                        .tag(2)
                }
                .tint(Theme.accent)
            }
        }
        // 同步 HomeViewModel 的 context 和推荐问题到 AssistantViewModel
        .onChange(of: homeViewModel.context) { _, newContext in
            assistantViewModel.context = newContext
        }
        .onChange(of: homeViewModel.suggestedQuestions) { _, newQuestions in
            assistantViewModel.suggestedQuestions = newQuestions
        }
        // 切换到助手 Tab 时按当前周期阶段生成推荐问题
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == 1 {
                Task { await homeViewModel.load() }
            }
            if newTab == 2 {
                assistantViewModel.prepareCurrentDayConversation()
                Task { await homeViewModel.loadSuggestedQuestionsIfNeeded() }
            }
        }
    }
}

#Preview {
    MainTabView()
}
