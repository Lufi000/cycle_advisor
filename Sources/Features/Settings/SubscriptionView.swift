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
                    }

                    HStack(spacing: 12) {
                        Text(String(format: String(localized: "billing.free_chat.remaining"), billing.freeChatRemaining))
                        Spacer()
                        Text(String(format: String(localized: "billing.suggestion.remaining"), billing.suggestionRefreshRemainingToday()))
                    }
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)

                    Text(billing.subscriptionStatusText)
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.textSecondary)

                    if billing.shouldWarnLowBalance {
                        Text("billing.subscription.required_hint")
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.phaseMenstrual)
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

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDisclosureExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: Theme.bodySize + 2))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(String(localized: "billing.subscription.info_a11y"))

                if isDisclosureExpanded {
                    Text("billing.subscription.disclosure")
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            Task { await purchaseSubscription() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscribePrimaryText)
                        .font(.system(size: Theme.bodySize + 1, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subscribeSecondaryText)
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(.white.opacity(0.85))
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .disabled(billing.isPurchasing)
    }

    private var subscribePrimaryText: String {
        if billing.isPurchasing {
            return String(localized: "billing.action.purchasing_aipro")
        }
        let priceLine = billing.hasLoadedSubscriptionProduct
            ? billing.monthlySubscriptionDisplayPrice
            : BillingManager.monthlySubscriptionFallbackTitle
        return String(format: String(localized: "billing.subscription.monthly_price"), priceLine)
    }

    private var subscribeSecondaryText: String {
        if billing.isPurchasing {
            return ""
        }
        if billing.isLoadingStoreProducts {
            return String(localized: "billing.subscription.loading")
        }
        return String(localized: "billing.subscription.monthly_detail")
    }

    @ViewBuilder
    private var subscribeButtonTrailingIcon: some View {
        if billing.isPurchasing || billing.isLoadingStoreProducts {
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
