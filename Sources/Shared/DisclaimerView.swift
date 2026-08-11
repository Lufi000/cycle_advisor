import SwiftUI

struct DisclaimerView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
            Text("disclaimer.text")
                .font(.system(size: Theme.captionSize))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
}

struct CitationLinksView: View {
    let sources: [CitationSource]
    var compact: Bool = false
    @State private var isExpanded = false

    private var uniqueSources: [CitationSource] {
        var seen = Set<String>()
        return sources.filter { source in
            guard !seen.contains(source.id) else { return false }
            seen.insert(source.id)
            return true
        }
    }

    var body: some View {
        let items = uniqueSources
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(String(localized: "citation.sources.title"), systemImage: "book.closed.fill")
                            .font(.system(size: Theme.captionSize, weight: .semibold))

                        Text(String(format: String(localized: "citation.sources.count_format"), items.count))
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.textSecondary.opacity(0.72))

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "citation.toggle_sources_a11y"))

                if isExpanded {
                    VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                        ForEach(items) { source in
                            citationLink(for: source)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(compact ? 10 : Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackgroundSolid.opacity(compact ? 0.72 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(Theme.textSecondary.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private func citationLink(for source: CitationSource) -> some View {
        Link(destination: source.url) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: compact ? Theme.captionSize : Theme.bodySize, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)

                    if !compact {
                        Text("\(source.publisher) · \(source.summary)")
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(String(localized: "citation.open_source_a11y")) \(source.title)")
    }
}

#Preview {
    VStack {
        DisclaimerView()
        CitationLinksView(sources: ReferenceLibrary.coreHealth)
    }
    .padding()
}
