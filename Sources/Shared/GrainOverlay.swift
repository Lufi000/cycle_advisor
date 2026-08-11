import SwiftUI

// MARK: - Grain Intensity Presets

enum GrainIntensity {
    case subtle   // 0.035 — 指标条、环形背景
    case light    // 0.055 — 建议卡片
    case medium   // 0.080 — 全屏背景面板
    case custom(Double)

    var value: Double {
        switch self {
        case .subtle:        return 0.035
        case .light:         return 0.055
        case .medium:        return 0.080
        case .custom(let v): return v
        }
    }
}

// MARK: - GrainOverlay

/// 基于 SwiftUI Canvas 的噪点/胶片颗粒纹理叠层。
/// 使用播种 LCG 伪随机数生成器，空间稳定（不闪烁）。
/// iOS 15+ 兼容，无需 Metal。
struct GrainOverlay: View {
    var intensity: GrainIntensity = .light
    var dotSize: CGFloat = 1.0
    /// 固定种子产生与视图绑定的稳定颗粒图案；每张卡片传入不同种子避免图案重复。
    var seed: UInt64 = 42

    var body: some View {
        Canvas { context, size in
            let count = Int(size.width * size.height * 0.18)  // ~18% 覆盖密度
            var rng = SeededRNG(seed: seed)

            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let alpha = intensity.value * (0.4 + Double(rng.next()) * 0.6)

                let rect = CGRect(
                    x: x - dotSize / 2,
                    y: y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.black.opacity(alpha))
                )
            }
        }
        .drawingGroup()           // 栅格化为 CALayer 位图，避免每帧重绘
        .allowsHitTesting(false)  // 颗粒层不拦截触摸事件
    }
}

// MARK: - Seeded LCG PRNG

/// 64 位线性同余生成器（Knuth 常数）。确定性、可播种，适合视觉噪点。
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed &+ 1 }

    /// 返回 [0, 1) 范围内的下一个值
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 33) / Double(1 << 31)
    }
}

// MARK: - ViewModifier

struct GrainTextureModifier: ViewModifier {
    var intensity: GrainIntensity
    var dotSize: CGFloat
    var seed: UInt64

    func body(content: Content) -> some View {
        content.overlay(
            GrainOverlay(intensity: intensity, dotSize: dotSize, seed: seed)
                .clipped()
        )
    }
}

extension View {
    /// 在视图上叠加胶片颗粒纹理。默认 `.light` 强度。
    func grainTexture(
        intensity: GrainIntensity = .light,
        dotSize: CGFloat = 1.0,
        seed: UInt64 = 42
    ) -> some View {
        modifier(GrainTextureModifier(intensity: intensity, dotSize: dotSize, seed: seed))
    }
}
