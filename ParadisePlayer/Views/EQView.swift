import SwiftUI

struct EQView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var engine = model.engine
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Equalizer")
                    .font(Theme.title(24))
                    .foregroundStyle(Theme.text)
                Spacer()
                Toggle("", isOn: $engine.eqEnabled)
                    .labelsHidden()
                    .tint(Theme.neonPink)
            }

            ForEach(AudioEngine.eqBandNames.indices, id: \.self) { i in
                HStack(spacing: 14) {
                    Text(AudioEngine.eqBandNames[i].uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, alignment: .leading)

                    Slider(value: $engine.eqGains[i], in: AudioEngine.eqGainRange, step: 0.5)
                        .tint(Theme.neonPink)
                        .disabled(engine.eqKills[i])
                        .opacity(engine.eqKills[i] ? 0.4 : 1)

                    Text(engine.eqKills[i] ? "KILL" : String(format: "%+.1f", engine.eqGains[i]))
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(engine.eqKills[i] ? Theme.danger : Theme.text)
                        .frame(width: 44, alignment: .trailing)

                    Button { engine.eqKills[i].toggle() } label: {
                        Image(systemName: engine.eqKills[i] ? "speaker.slash.fill" : "speaker.slash")
                            .foregroundStyle(engine.eqKills[i] ? Theme.danger : Theme.text)
                    }
                    .buttonStyle(CircleIconButtonStyle(size: 36))
                }
                .disabled(!engine.eqEnabled)
                .opacity(engine.eqEnabled ? 1 : 0.4)
            }

            HStack {
                Button("Zurücksetzen") { engine.resetEQ() }
                    .buttonStyle(PillButtonStyle())
                Spacer()
                Button("Fertig") { dismiss() }
                    .buttonStyle(PillButtonStyle(tint: Theme.text, foreground: Theme.background))
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }
}
