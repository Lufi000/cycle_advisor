import SwiftUI

struct ChatInputBarView: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            TextField(
                String(localized: "assistant.input_placeholder"),
                text: $text,
                prompt: Text(String(localized: "assistant.input_placeholder"))
                    .font(Theme.itim(size: 18))
                    .foregroundStyle(Color.black.opacity(0.30)),
                axis: .vertical
            )
                .font(Theme.itim(size: 18))
                .foregroundStyle(Color.black.opacity(0.30))
                .tint(Theme.accent)
                .lineLimit(1...5)
                .padding(.horizontal, 32)
                .frame(width: 295, height: 46)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 23))
                .onSubmit { if !isStreaming { onSend() } }

            Button {
                onSend()
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(
                        isStreaming
                            ? Theme.textSecondary
                            : (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               ? Color.clear
                               : Theme.accent)
                    )
                    .frame(width: 58, height: 46)
                    .background(Theme.cardBackgroundSolid)
                    .clipShape(RoundedRectangle(cornerRadius: 23))
                    .animation(.easeInOut(duration: 0.15), value: isStreaming)
            }
            .disabled(!isStreaming && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 15)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background(
            Theme.background
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

#Preview {
    @Previewable @State var text = ""
    ChatInputBarView(text: $text, isStreaming: false) {}
        .background(Theme.background)
}
