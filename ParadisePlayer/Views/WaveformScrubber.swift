import SwiftUI

/// Großer Balken zum Wisch-Skippen: Die ganze Fläche ist greifbar.
/// Antippen springt an die Stelle, Wischen spult hörbar mit (wie Scratch-Vorschau),
/// beim Loslassen wird exakt positioniert.
struct WaveformScrubber: View {
    let waveform: Waveform?
    let duration: TimeInterval
    let statusText: String?
    let currentTime: () -> TimeInterval
    let onSeek: (TimeInterval) -> Void

    var height: CGFloat = 180

    @State private var dragFraction: Double?
    @State private var lastLiveSeek = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                let progress = dragFraction ?? (duration > 0 ? currentTime() / duration : 0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .fill(Theme.surface)

                    Canvas { context, size in
                        draw(in: &context, size: size, progress: progress)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))

                    // Abspielposition
                    Capsule()
                        .fill(Theme.text)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .shadow(color: Theme.neonPink.opacity(0.8), radius: 6)
                        .offset(x: max(0, min(geo.size.width - 3, progress * geo.size.width - 1.5)))

                    if let dragFraction {
                        Text(TimeFormat.string(dragFraction * duration))
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.text))
                            .position(x: max(36, min(geo.size.width - 36, dragFraction * geo.size.width)), y: 20)
                    }

                    if let statusText {
                        HStack(spacing: 8) {
                            ProgressView().tint(Theme.text)
                            Text(statusText).font(.subheadline).foregroundStyle(Theme.textBody)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        let fraction = clamp(value.location.x / geo.size.width)
                        dragFraction = fraction
                        if Date().timeIntervalSince(lastLiveSeek) > 0.12 {
                            lastLiveSeek = Date()
                            onSeek(fraction * duration)
                        }
                    }
                    .onEnded { value in
                        guard duration > 0 else { return }
                        let fraction = clamp(value.location.x / geo.size.width)
                        dragFraction = nil
                        onSeek(fraction * duration)
                    }
            )
            .sensoryFeedback(.selection, trigger: dragFraction == nil)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Wellenform und Abspielposition")
        .accessibilityAdjustableAction { direction in
            let step = 10.0
            onSeek(currentTime() + (direction == .increment ? step : -step))
        }
    }

    private func clamp(_ x: Double) -> Double { max(0, min(1, x)) }

    private func draw(in context: inout GraphicsContext, size: CGSize, progress: Double) {
        guard let wf = waveform, !wf.peaks.isEmpty else { return }
        let count = wf.peaks.count
        let barStep: CGFloat = 3
        let barWidth: CGFloat = 2
        let columns = max(1, Int(size.width / barStep))
        let mid = size.height / 2
        let maxHeight = mid - 10

        var playedPeak = Path(), restPeak = Path()
        var playedBody = Path(), restBody = Path()

        for col in 0..<columns {
            let f0 = Double(col) / Double(columns)
            let f1 = Double(col + 1) / Double(columns)
            let b0 = min(count - 1, Int(f0 * Double(count)))
            let b1 = min(count, max(b0 + 1, Int(f1 * Double(count))))
            let peak = CGFloat(wf.peaks[b0..<b1].max() ?? 0)
            let rms = CGFloat(wf.rms[b0..<b1].max() ?? 0)

            let x = CGFloat(col) * barStep
            let ph = max(1, peak * maxHeight)
            let rh = max(1, min(peak, rms * 1.4) * maxHeight)
            let peakRect = CGRect(x: x, y: mid - ph, width: barWidth, height: ph * 2)
            let bodyRect = CGRect(x: x, y: mid - rh, width: barWidth, height: rh * 2)

            if f0 < progress {
                playedPeak.addRoundedRect(in: peakRect, cornerSize: CGSize(width: 1, height: 1))
                playedBody.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: 1, height: 1))
            } else {
                restPeak.addRoundedRect(in: peakRect, cornerSize: CGSize(width: 1, height: 1))
                restBody.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: 1, height: 1))
            }
        }

        let gradient = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Theme.neonOrange, Theme.neonPink, Theme.violet]),
            startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
        )
        context.fill(restPeak, with: .color(Theme.text.opacity(0.14)))
        context.fill(restBody, with: .color(Theme.text.opacity(0.34)))

        var played = context
        played.opacity = 0.45
        played.fill(playedPeak, with: gradient)
        context.fill(playedBody, with: gradient)

        // Mittellinie
        var line = Path()
        line.move(to: CGPoint(x: 0, y: mid))
        line.addLine(to: CGPoint(x: size.width, y: mid))
        context.stroke(line, with: .color(Theme.text.opacity(0.08)), lineWidth: 1)
    }
}
