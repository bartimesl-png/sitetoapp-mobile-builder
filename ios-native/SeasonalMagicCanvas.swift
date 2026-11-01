import SwiftUI

/// Lightweight, procedural seasonal motion. No GIFs, video, network images or new asset weight.
/// Time-based drawing keeps moving objects independent from the app's navigation/data state.
struct SeasonalMagicCanvas: View {
    enum Stage {
        case feature
        case ambient
    }

    let theme: NativeSeasonalTheme
    let stage: Stage
    var burstTime: TimeInterval = -1000

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var isFeature: Bool { stage == .feature }

    private var performers: [String] {
        switch theme.id {
        case "halloween": return ["👻", "🦇", "👻", "🦇", "🕷️"]
        case "noel": return ["🦌", "🛷", "🎅", "🎁", "❄️"]
        case "nouvel-an": return ["🎆", "🥳", "✨", "🥂", "🎇"]
        case "paques": return ["🐰", "🐣", "🦋", "🥚", "🌷"]
        case "printemps": return ["🦋", "🐝", "🌸", "🦋", "🌼"]
        case "fete-des-meres": return ["💐", "💝", "🌸", "💕", "🌷"]
        case "fete-des-peres": return ["🏆", "🎁", "⭐", "🎈", "💙"]
        case "14-juillet": return ["🎆", "🇫🇷", "🎇", "✨", "🎉"]
        case "ete": return ["🦋", "☀️", "🐬", "🌴", "🍉"]
        case "rentree": return ["🍁", "✏️", "📚", "🍂", "🎒"]
        case "octobre-rose": return ["🎀", "💗", "🌸", "🩷", "💞"]
        case "armistice": return ["🕊️", "🌺", "🕊️", "🍃", "🌹"]
        case "movember": return ["🧔", "🎗️", "💙", "⭐", "🩵"]
        case "saint-valentin": return ["❤️", "💌", "💘", "🌹", "💕"]
        case "black-friday": return ["✨", "🏷️", "🛍️", "⚡", "💎"]
        default: return ["✨", "🌟", "🎉", "⭐", "💫"]
        }
    }

    private var particleGlyphs: [String] {
        switch theme.id {
        case "halloween": return ["✦", "✧", "✦", "⋆"]
        case "noel": return ["❄", "❅", "❆", "✦"]
        case "nouvel-an", "14-juillet": return ["✦", "✧", "✷", "✦"]
        case "paques", "printemps", "fete-des-meres", "octobre-rose": return ["🌸", "✧", "✿", "✦"]
        case "ete": return ["✧", "☀", "✦", "✧"]
        case "rentree": return ["🍂", "✦", "🍁", "✧"]
        case "armistice": return ["✧", "🍃", "✦", "✧"]
        case "movember": return ["✧", "✦", "💙", "✧"]
        case "saint-valentin": return ["💕", "♥", "✦", "💗"]
        case "black-friday": return ["✦", "✧", "✷", "⭐"]
        default: return ["✧", "✦", "✧", "✦"]
        }
    }

    var body: some View {
        TimelineView(
            .animation(minimumInterval: isFeature ? 1.0 / 20.0 : 1.0 / 12.0,
                       paused: reduceMotion || scenePhase != .active)
        ) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let time = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
                let width = Double(size.width)
                let height = Double(size.height)
                guard width > 0, height > 0 else { return }

                // Deliberately restrained across the page; vivid inside the event artwork.
                let particleCount = isFeature ? 35 : 12
                for index in 0..<particleCount {
                    let i = Double(index)
                    let speed = (isFeature ? 0.012 : 0.007) + Double(index % 7) * 0.0018
                    let progress = positiveFraction(time * speed + i * 0.179)
                    let rawX = positiveFraction(i * 0.6180339 + sin(time * 0.14 + i) * 0.024)
                    let x = rawX * width
                    let y = (1.10 - progress * 1.25) * height
                    let drift = sin(time * 0.7 + i * 1.8) * (isFeature ? 8.0 : 4.0)
                    let scale = isFeature ? 1.0 : 0.70
                    let font = (9.0 + Double(index % 4) * 4.0) * scale
                    let alpha = (isFeature ? 0.38 : 0.16) + 0.13 * sin(time * 0.8 + i)
                    drawGlyph(particleGlyphs[index % particleGlyphs.count],
                              fontSize: font, at: CGPoint(x: x + drift, y: y),
                              alpha: max(0.09, alpha), in: context)
                }

                // Three large, staggered actors cross the scene. Ghosts and bats
                // fly independently; each other festival has its own performers.
                let actors = isFeature ? 5 : 2
                let visualScale = min(1.60, max(0.85, width / (isFeature ? 450.0 : 650.0)))
                for index in 0..<actors {
                    let i = Double(index)
                    let speed = (isFeature ? 0.075 : 0.046) + i * 0.011
                    let progress = positiveFraction(time * speed + i * 0.25 + 0.12)
                    let forwards = index % 3 != 1
                    let x = forwards
                        ? -95.0 + progress * (width + 190.0)
                        : width + 95.0 - progress * (width + 190.0)
                    let baseY: Double
                    if isFeature {
                        baseY = [0.22, 0.45, 0.70, 0.84, 0.29][index] * height
                    } else {
                        baseY = [0.22, 0.76][index] * height
                    }
                    let y = baseY + sin(time * (0.95 + i * 0.14) + i) * (isFeature ? 20.0 : 13.0)
                    let font = (isFeature ? 58.0 + Double(index % 3) * 15.0 : 54.0) * visualScale
                    let fade = isFeature ? 0.95 : 0.44
                    // Suppress flying shapes when Reduce Motion is enabled; particles rest.
                    if !reduceMotion {
                        drawGlyph(performers[index % performers.count],
                                  fontSize: font, at: CGPoint(x: x, y: y),
                                  alpha: fade, in: context)
                    }
                }

                if isFeature && (theme.id == "nouvel-an" || theme.id == "14-juillet") {
                    drawFireworks(time: time, width: width, height: height, in: context)
                }

                let elapsed = time - burstTime
                if isFeature && !reduceMotion && elapsed >= 0 && elapsed < 2.2 {
                    drawCelebration(elapsed: elapsed, width: width, height: height, in: context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func positiveFraction(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 1.0)
        return result < 0 ? result + 1.0 : result
    }

    private func drawGlyph(_ glyph: String, fontSize: Double, at point: CGPoint,
                           alpha: Double, in context: GraphicsContext) {
        var graphics = context
        graphics.opacity = min(1, max(0, alpha))
        let text = Text(glyph).font(.system(size: fontSize, weight: .bold, design: .rounded))
        let resolved = graphics.resolve(text)
        graphics.draw(resolved, at: point, anchor: .center)
    }

    private func drawFireworks(time: Double, width: Double, height: Double,
                               in context: GraphicsContext) {
        let colors: [Color] = [theme.accent, theme.secondary, .white, .yellow]
        for burst in 0..<3 {
            let i = Double(burst)
            let life = positiveFraction(time * 0.31 + i * 0.34)
            let radius = 12 + life * min(width, height) * 0.27
            let center = CGPoint(x: width * [0.62, 0.83, 0.47][burst],
                                 y: height * [0.27, 0.45, 0.58][burst])
            for spoke in 0..<14 {
                let angle = Double(spoke) * .pi * 2 / 14 + i * 0.35
                var line = Path()
                line.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.61,
                                      y: center.y + sin(angle) * radius * 0.61))
                line.addLine(to: CGPoint(x: center.x + cos(angle) * radius,
                                         y: center.y + sin(angle) * radius))
                context.stroke(line,
                               with: .color(colors[(spoke + burst) % colors.count].opacity((1 - life) * 0.87)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }

    private func drawCelebration(elapsed: Double, width: Double, height: Double,
                                 in context: GraphicsContext) {
        let progress = min(1.0, elapsed / 1.55)
        let alpha = max(0, 1.0 - elapsed / 2.2)
        let origin = CGPoint(x: width * 0.73, y: height * 0.59)
        for index in 0..<30 {
            let i = Double(index)
            let angle = i * (2 * .pi / 30) + sin(i * 9.1) * 0.15
            let distance = progress * min(width, height) * (0.35 + Double(index % 4) * 0.08)
            let location = CGPoint(x: origin.x + cos(angle) * distance,
                                   y: origin.y + sin(angle) * distance + progress * progress * 32)
            let glyph = index % 5 == 0 ? performers[index % performers.count] : particleGlyphs[index % particleGlyphs.count]
            drawGlyph(glyph, fontSize: index % 5 == 0 ? 29 : 19,
                      at: location, alpha: alpha, in: context)
        }
        var ring = Path()
        ring.addEllipse(in: CGRect(x: origin.x - progress * 104, y: origin.y - progress * 104,
                                   width: progress * 208, height: progress * 208))
        context.stroke(ring, with: .color(.white.opacity(alpha * 0.55)), lineWidth: 2.4)
    }
}
