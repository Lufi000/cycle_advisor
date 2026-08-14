import SwiftUI
import StoreKit

struct SubscriptionView: View {
    private let billing = BillingManager.shared
    @State private var purchaseErrorMessage: String?
    @State private var purchaseInfoMessage: String?
    @State private var isRestoring: Bool = false
    @State private var showingManageSubscriptions: Bool = false
    @State private var isDisclosureExpanded: Bool = false

    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://lufi000.github.io/cycle-advisor-legal/privacy/")!

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("billing.subscription.title")
                            .font(.system(size: Theme.bodySize, weight: .semibold))
                        Spacer()
                        Text(billing.isSubscriptionActive ? String(localized: "billing.subscription.badge_active") : String(localized: "billing.subscription.badge_inactive"))
                            .font(.system(size: Theme.titleSize, weight: .bold, design: .rounded))
                        Button {
                            isDisclosureExpanded.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: Theme.bodySize + 2))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel(String(localized: "billing.subscription.info_a11y"))
                    }

                    if billing.shouldWarnLowBalance {
                        Text("billing.subscription.required_hint")
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.phaseMenstrual)
                    }

                    if isDisclosureExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(subscriptionInfoLines, id: \.self) { line in
                                Text(line)
                            }

                            Text("billing.subscription.disclosure")
                                .padding(.top, 2)
                        }
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("billing.section.account")
            }

            Section {
                subscribeButton
            } header: {
                Text("billing.section.subscription")
            }
            .listRowBackground(Color.clear)

            Section {
                Button {
                    Task { await restorePurchases() }
                } label: {
                    HStack(spacing: 8) {
                        if isRestoring {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                        Text(isRestoring
                             ? String(localized: "billing.action.restoring")
                             : String(localized: "billing.action.restore"))
                            .font(.system(size: Theme.bodySize))
                    }
                }
                .disabled(isRestoring || billing.isPurchasing)

                Button {
                    showingManageSubscriptions = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard.circle")
                        Text("billing.action.manage")
                            .font(.system(size: Theme.bodySize))
                    }
                }

                HStack(spacing: 16) {
                    Link(String(localized: "billing.legal.terms"), destination: Self.termsURL)
                    Link(String(localized: "billing.legal.privacy"), destination: Self.privacyURL)
                    Spacer()
                }
                .font(.system(size: Theme.captionSize))

                if let purchaseInfoMessage {
                    Text(purchaseInfoMessage)
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let purchaseErrorMessage {
                    Text(purchaseErrorMessage)
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.phaseMenstrual)
                }
            }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        }
        .navigationTitle(String(localized: "subscription.title"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .task {
            await billing.loadStoreProducts()
        }
    }

    @ViewBuilder
    private var subscribeButton: some View {
        Button {
            if billing.isSubscriptionActive {
                showingManageSubscriptions = true
            } else {
                Task { await purchaseSubscription() }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscribePrimaryText)
                        .font(.system(size: Theme.bodySize + 1, weight: .bold))
                        .foregroundStyle(subscribePrimaryColor)
                    Text(subscribeSecondaryText)
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(subscribeSecondaryColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                subscribeButtonTrailingIcon
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(subscribeBackgroundColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        .disabled(billing.isPurchasing || (!billing.isSubscriptionActive && billing.isLoadingStoreProducts))
    }

    private var subscribePrimaryText: String {
        if billing.isSubscriptionActive {
            return String(localized: "billing.subscription.active_title")
        }
        if billing.isPurchasing {
            return String(localized: "billing.action.purchasing_aipro")
        }
        let priceLine = billing.hasLoadedSubscriptionProduct
            ? billing.monthlySubscriptionDisplayPrice
            : BillingManager.monthlySubscriptionFallbackTitle
        return String(format: String(localized: "billing.subscription.monthly_price"), priceLine)
    }

    private var subscribeSecondaryText: String {
        if billing.isSubscriptionActive {
            return String(localized: "billing.subscription.active_detail")
        }
        if billing.isPurchasing {
            return ""
        }
        if billing.isLoadingStoreProducts {
            return String(localized: "billing.subscription.loading")
        }
        return String(localized: "billing.subscription.monthly_detail")
    }

    private var subscribeBackgroundColor: Color {
        billing.isSubscriptionActive ? Theme.cardBackgroundSolid : Theme.accent
    }

    private var subscribePrimaryColor: Color {
        billing.isSubscriptionActive ? Theme.textPrimary : .white
    }

    private var subscribeSecondaryColor: Color {
        billing.isSubscriptionActive ? Theme.textSecondary : .white.opacity(0.85)
    }

    private var subscriptionInfoLines: [String] {
        [
            String(
                format: String(localized: billing.isSubscriptionActive ? "billing.chat.remaining_today" : "billing.free_chat.remaining"),
                billing.isSubscriptionActive ? billing.assistantChatsRemainingToday : billing.freeChatRemaining
            ),
            billing.isSubscriptionActive
                ? String(localized: "billing.subscription.chat_active")
                : String(localized: "billing.subscription.free_plan"),
            billing.subscriptionStatusText
        ]
    }

    @ViewBuilder
    private var subscribeButtonTrailingIcon: some View {
        if billing.isSubscriptionActive {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.accent)
        } else if billing.isPurchasing || billing.isLoadingStoreProducts {
            ProgressView()
                .tint(.white)
        } else {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func purchaseSubscription() async {
        purchaseErrorMessage = nil
        purchaseInfoMessage = nil
        do {
            let outcome = try await billing.purchaseMonthlySubscription()
            purchaseInfoMessage = outcome.message
        } catch {
            purchaseErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func restorePurchases() async {
        purchaseErrorMessage = nil
        purchaseInfoMessage = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            let restored = try await billing.restorePurchases()
            purchaseInfoMessage = restored
                ? String(localized: "billing.action.restored")
                : String(localized: "billing.action.no_purchases")
        } catch {
            purchaseErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
