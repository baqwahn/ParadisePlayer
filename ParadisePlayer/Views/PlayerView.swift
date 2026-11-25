import SwiftUI

struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @Binding var showEQ: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            WaveformScrubber(
                waveform: model.waveform,
                duration: model.engine.duration,
                statusText: statusText,
                currentTime: { model.engine.currentTime },
                onSeek: { model.engine.seek(to: $0) }
            )

            timeRow
            transport
            pitchRow
            actionRow
        }
        .card(padding: 20)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var statusText: String? {
        switch model.loadState {
        case .downloading: "Lädt aus iCloud …"
        case .loading: model.waveform == nil && model.currentTrack != nil ? "Wird geladen …" : nil
        case .ready: model.waveform == nil ? "Wellenform wird berechnet …" : nil
        case .failed: "Laden fehlgeschlagen"
        case .idle: model.currentTrack == nil ? "Track aus der Liste wählen" : nil
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOW CHECKING")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text(model.currentTrack.map { model.title(for: $0) } ?? "Kein Track gewählt")
                    .font(Theme.title(26))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let track = model.currentTrack, let artist = model.artist(for: track) {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                bpmBadge
                if let key = model.currentInfo?.camelot {
                    CamelotBadge(key: key)
                }
            }
        }
    }

    @ViewBuilder
    private var bpmBadge: some View {
        if let bpm = model.currentInfo?.bpm {
            let pitched = bpm * (1 + model.engine.pitchPercent / 100)
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.1f", pitched))
                    .font(Theme.title(30))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(model.currentInfo?.bpmFromTag == true ? "BPM · TAG" : "BPM · ANALYSE")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else if model.currentTrack != nil {
            Text("BPM …")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Zeit

    private var timeRow: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let t = model.engine.currentTime
            let d = model.engine.duration
            HStack {
                Text(TimeFormat.string(t))
                Spacer()
                Text("−" + TimeFormat.string(max(0, d - t)))
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, -8)
    }

    // MARK: Transport

    private var transport: some View {
        HStack {
            Button { model.previous() } label: { Image(systemName: "backward.end.fill") }
                .buttonStyle(CircleIconButtonStyle(size: 48))
            Spacer()
            jumpButton(forward: false)
            Spacer()
            Button { model.togglePlay() } label: {
                Image(systemName: model.engine.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(CircleIconButtonStyle(size: 76, filled: true))
            .sensoryFeedback(.impact(weight: .light), trigger: model.engine.isPlaying)
            Spacer()
            jumpButton(forward: true)
            Spacer()
            Button { model.next() } label: { Image(systemName: "forward.end.fill") }
                .buttonStyle(CircleIconButtonStyle(size: 48))
        }
    }

    private func jumpButton(forward: Bool) -> some View {
        Button { model.jump(forward: forward) } label: {
            VStack(spacing: 1) {
                Image(systemName: forward ? "goforward" : "gobackward")
                Text(model.jumpLabel)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
            }
        }
        .buttonStyle(CircleIconButtonStyle(size: 56))
        .accessibilityLabel(forward ? "Vorspringen" : "Zurückspringen")
    }

    // MARK: Tempo

    /// Der Regler ändert immer das Tempo. Key Lock entscheidet, ob die Tonhöhe mitwandert
    /// (offen, wie am Plattenspieler) oder die Tonart erhalten bleibt (zu).
    private var pitchRow: some View {
        @Bindable var engine = model.engine
        let range = model.settings.pitchRange
        let changed = abs(engine.pitchPercent) >= 0.05
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("TEMPO")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)

                Text(pitchInfo(percent: engine.pitchPercent, keyLock: engine.keyLock))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(changed && !engine.keyLock ? Theme.neonOrange : Theme.textSecondary)
                    .lineLimit(1)
                    .opacity(changed ? 1 : 0)

                Spacer(minLength: 4)

                Button { engine.keyLock.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: engine.keyLock ? "lock.fill" : "lock.open")
                        Text("Key Lock")
                    }
                }
                .buttonStyle(PillButtonStyle(
                    tint: engine.keyLock ? Theme.neonPink : Theme.surfaceRaised,
                    foreground: engine.keyLock ? Theme.background : Theme.text
                ))
                .sensoryFeedback(.selection, trigger: engine.keyLock)
                .accessibilityLabel("Key Lock")
                .accessibilityValue(engine.keyLock ? "an, Tonart bleibt gleich" : "aus, Tonhöhe ändert sich mit dem Tempo")
            }

            HStack(spacing: 12) {
                Slider(value: $engine.pitchPercent, in: -range...range, step: 0.1)
                    .tint(Theme.neonPink)
                    .accessibilityLabel("Tempo")

                Text(Self.decimal(engine.pitchPercent, signed: true) + " %")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(changed ? Theme.text : Theme.textSecondary)
                    .frame(width: 58, alignment: .trailing)

                Button("0") { engine.pitchPercent = 0 }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityLabel("Tempo zurücksetzen")
            }
        }
    }

    /// Kurzer Hinweis neben „TEMPO“: bei offenem Schloss die Tonhöhenverschiebung in Halbtönen.
    private func pitchInfo(percent: Double, keyLock: Bool) -> String {
        if keyLock { return "Tonart bleibt" }
        let semitones = 12 * log2(1 + percent / 100)
        return "Tonhöhe " + Self.decimal(semitones, signed: true) + " HT"
    }

    private static func decimal(_ value: Double, signed: Bool) -> String {
        var rounded: Double = (value * 10).rounded() / 10
        if rounded == 0 { rounded = 0 } // −0,0 vermeiden
        let text = String(format: signed ? "%+.1f" : "%.1f", locale: Locale(identifier: "de_DE"), rounded)
        return rounded == 0 ? text.replacingOccurrences(of: "+", with: "±") : text
    }

    // MARK: Bewertung, EQ, Papierkorb

    private var actionRow: some View {
        let rating = model.currentInfo?.rating ?? 0
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button { model.rate(star) } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 24))
                        .foregroundStyle(star <= rating ? Theme.star : Theme.textSecondary)
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) Sterne")
            }

            Spacer()

            Button { showEQ = true } label: {
                Image(systemName: "slider.vertical.3")
                    .foregroundStyle(model.engine.isEQActive ? Theme.neonPink : Theme.text)
            }
            .buttonStyle(CircleIconButtonStyle(size: 44))
                .accessibilityLabel("Equalizer")

            Button { model.trashCurrent() } label: {
                Image(systemName: "trash.fill").foregroundStyle(Theme.danger)
            }
            .buttonStyle(CircleIconButtonStyle(size: 44))
            .accessibilityLabel("In den Papierkorb")
        }
        .sensoryFeedback(.selection, trigger: rating)
        .disabled(model.currentTrack == nil)
    }
}

struct CamelotBadge: View {
    let key: String
    var compact = false

    var body: some View {
        Text(key)
            .font((compact ? Font.caption : Font.headline).monospacedDigit().weight(.bold))
            .foregroundStyle(Theme.background)
            .padding(.horizontal, compact ? 7 : 12)
            .padding(.vertical, compact ? 2 : 5)
            .frame(minWidth: compact ? 34 : 48)
            .background(Capsule().fill(Camelot.color(for: key)))
    }
}

extension Camelot {
    /// Farbe je Position im Camelot-Rad, A (Moll) etwas gedeckter.
    static func color(for key: String) -> Color {
        guard let c = components(key) else { return Theme.textSecondary }
        return Color(hue: Double(c.number - 1) / 12, saturation: c.letter == "A" ? 0.5 : 0.7, brightness: 0.95)
    }
}
