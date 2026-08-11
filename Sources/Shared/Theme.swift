import SwiftUI

/// 暖蜜桃（Warm Peach）设计系统
enum Theme {
    // MARK: - Palette

    /// #F7E6DC
    static let warmShell = Color(red: 247/255, green: 230/255, blue: 220/255)

    /// #FF9354
    static let sunsetOrange = Color(red: 255/255, green: 147/255, blue: 84/255)

    /// #FFE0CE
    static let peachBlush = Color(red: 255/255, green: 224/255, blue: 206/255)

    /// #FFF4EB
    static let cream = Color(red: 255/255, green: 244/255, blue: 235/255)

    /// #FFFBF7
    static let creamBright = Color(red: 255/255, green: 251/255, blue: 247/255)

    // MARK: - 背景与表面色

    /// 页面背景 — #F7E6DC
    static let background = warmShell

    /// 卡片背景（半透明）— #FFF4EB
    static let cardBackground = cream.opacity(0.94)

    /// 卡片背景（不透明，用于颗粒纹理叠加）— #FFF4EB
    static let cardBackgroundSolid = cream

    // MARK: - 强调色

    /// 主强调色 — #FF9354
    static let accent = sunsetOrange

    /// 浅强调色 — 用于图标背景、选中态
    static let accentLight = sunsetOrange.opacity(0.16)

    // MARK: - 文字色

    /// 文字主色 — #413036
    static let textPrimary = Color(red: 65/255, green: 48/255, blue: 54/255)

    /// 文字副色 — rgba(0, 0, 0, 0.50)
    static let textSecondary = Color.black.opacity(0.50)

    // MARK: - 周期相位色

    static let phaseMenstrual  = sunsetOrange
    static let phaseFollicular = sunsetOrange
    static let phaseOvulation  = sunsetOrange
    static let phaseLuteal     = sunsetOrange

    // MARK: - 卡片形状

    static let cardCornerRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 8
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowY: CGFloat = 3
    static let cardShadowOpacity: Double = 0

    // MARK: - 字体尺寸

    static let titleSize: CGFloat = 22
    static let cardTitleSize: CGFloat = 15
    static let bodySize: CGFloat = 13
    static let captionSize: CGFloat = 11
    static let lineSpacing: CGFloat = 4

    // MARK: - Fonts

    static func itim(size: CGFloat) -> Font {
        .custom("Itim", size: size)
    }

    // MARK: - 渐变

    /// CTA 按钮渐变 — #FF9354 → #FFE0CE
    static let ctaGradient = LinearGradient(
        colors: [
            sunsetOrange,
            peachBlush
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - CardStyle（基础，无颗粒）

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .background(Theme.cardBackgroundSolid)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .shadow(
                color: Theme.textPrimary.opacity(Theme.cardShadowOpacity),
                radius: Theme.cardShadowRadius,
                y: Theme.cardShadowY
            )
    }
}

// MARK: - GrainCardStyle（带颗粒纹理的卡片样式）

/// 颗粒纹理卡片样式。颗粒置于 background 内，被圆角矩形裁剪，不会溢出到阴影。
struct GrainCardStyle: ViewModifier {
    var seed: UInt64 = 42

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.cardPadding)
            .background(
                Theme.cardBackgroundSolid
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .shadow(
                color: Theme.textPrimary.opacity(Theme.cardShadowOpacity),
                radius: Theme.cardShadowRadius,
                y: Theme.cardShadowY
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    /// 应用带颗粒纹理的卡片样式。为每张卡片传入唯一 seed 以产生不同图案。
    func grainCardStyle(seed: UInt64 = 42) -> some View {
        modifier(GrainCardStyle(seed: seed))
    }
}
