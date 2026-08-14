import SwiftUI

/// 首屏推荐问题按钮
struct SuggestedQuestionChip: View {
    let question: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                Text(question)
                    .font(Theme.itim(size: 18))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.cardBackgroundSolid)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(
                color: Theme.textPrimary.opacity(0.05),
                radius: 4,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 8) {
        SuggestedQuestionChip(question: "今天适合高强度训练吗？") {}
        SuggestedQuestionChip(question: "卵泡期应该怎么调整饮食？") {}
    }
    .padding()
    .background(Theme.background)
}
