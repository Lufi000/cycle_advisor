import SwiftUI

// MARK: - Block Types

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case bulletItem(text: String)
    case orderedItem(index: Int, text: String)
    case paragraph(text: String)
}

// MARK: - Parser

private enum MarkdownParser {
    static func parse(_ raw: String, isStreaming: Bool) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: "\n")
            if !joined.isEmpty {
                blocks.append(.paragraph(text: joined))
            }
            paragraphLines = []
        }

        let allLines = raw.components(separatedBy: "\n")
        // During streaming, the last line may be incomplete — treat it as plain paragraph
        let rawEndsWithNewline = raw.hasSuffix("\n")
        let processedLines: [String]
        let trailingFragment: String?

        if isStreaming && !rawEndsWithNewline && allLines.count > 0 {
            processedLines = Array(allLines.dropLast())
            trailingFragment = allLines.last
        } else {
            processedLines = allLines
            trailingFragment = nil
        }

        for line in processedLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bulletItem(text: String(trimmed.dropFirst(2))))
            } else if let match = orderedListMatch(trimmed) {
                flushParagraph()
                blocks.append(.orderedItem(index: match.index, text: match.text))
            } else {
                paragraphLines.append(trimmed)
            }
        }

        flushParagraph()

        // Append incomplete trailing fragment as a paragraph
        if let fragment = trailingFragment, !fragment.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks.append(.paragraph(text: fragment))
        }

        return blocks
    }

    private static func orderedListMatch(_ line: String) -> (index: Int, text: String)? {
        // Match "1. ", "12. " etc.
        var i = line.startIndex
        while i < line.endIndex && line[i].isNumber {
            i = line.index(after: i)
        }
        guard i > line.startIndex,
              i < line.endIndex,
              line[i] == ".",
              line.index(after: i) < line.endIndex,
              line[line.index(after: i)] == " " else {
            return nil
        }
        let numStr = String(line[line.startIndex..<i])
        guard let num = Int(numStr) else { return nil }
        let textStart = line.index(i, offsetBy: 2)
        return (index: num, text: String(line[textStart...]))
    }
}

// MARK: - MarkdownTextView

struct MarkdownTextView: View {
    let content: String
    var isStreaming: Bool = false

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(content, isStreaming: isStreaming)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineAttributed(text))
                .font(Theme.itim(size: headingSize(level)))
                .foregroundStyle(Theme.textPrimary.opacity(0.70))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level == 1 ? 6 : 4)
                .padding(.bottom, 2)

        case .bulletItem(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(Theme.itim(size: 18))
                    .foregroundStyle(Theme.textPrimary.opacity(0.70))
                    .padding(.top, 1)
                Text(inlineAttributed(text))
                    .font(Theme.itim(size: 18))
                    .foregroundStyle(Theme.textPrimary.opacity(0.70))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .orderedItem(let index, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(index).")
                    .font(Theme.itim(size: 18))
                    .foregroundStyle(Theme.textPrimary.opacity(0.70))
                    .frame(minWidth: 18, alignment: .trailing)
                    .padding(.top, 1)
                Text(inlineAttributed(text))
                    .font(Theme.itim(size: 18))
                    .foregroundStyle(Theme.textPrimary.opacity(0.70))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .paragraph(let text):
            Text(inlineAttributed(text))
                .font(Theme.itim(size: 18))
                .foregroundStyle(Theme.textPrimary.opacity(0.70))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 18
        case 2: return 18
        default: return 18
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownTextView(content: """
        ## 卵泡期建议
        这个阶段雌激素上升，身体状态好，适合：
        - **高强度训练**（如 HIIT）
        - 力量训练 `PR` 尝试
        1. 优先保证睡眠质量
        2. 增加*蛋白质*摄入

        ### 饮食提示
        多吃富含铁质的食物，如菠菜和红肉。
        """)
        .padding()
    }
    .background(Theme.background)
}
