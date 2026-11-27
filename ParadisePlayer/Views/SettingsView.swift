import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEmptyTrash = false
    @State private var trashMessage: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("Startposition", selection: $model.settings.startMode) {
                        ForEach(StartMode.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Sprungweite", selection: $model.settings.jumpBeats) {
                        Text("8 Beats").tag(8)
                        Text("16 Beats").tag(16)
                        Text("32 Beats").tag(32)
                    }
                    Picker("Pitch-Bereich", selection: $model.settings.pitchRange) {
                        Text("± 8 %").tag(8.0)
                        Text("± 16 %").tag(16.0)
                    }
                    Toggle("Am Trackende weiter", isOn: $model.settings.autoPlayNext)
                } header: {
                    Text("Wiedergabe")
                } footer: {
                    Text("Ohne BPM-Wert springt die App 10 Sekunden statt der eingestellten Beats.")
                }

                Section {
                    Picker("Bewertung", selection: $model.settings.ratingStyle) {
                        ForEach(RatingStyle.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Bewertung")
                } footer: {
                    Text(model.settings.ratingStyle == .heart
                        ? "Herz an oder aus. Tracks ohne Herz bleiben in der Liste, aussortiert wird nur über den Papierkorb. Tracks mit 4 oder 5 Sternen erscheinen mit Herz."
                        : "Erneutes Tippen auf denselben Stern entfernt die Bewertung. Herzen erscheinen hier als 5 Sterne.")
                }

                Section {
                    Picker("Tempobereich", selection: $model.settings.minBPM) {
                        Text("70–140").tag(70.0)
                        Text("80–160").tag(80.0)
                        Text("85–170").tag(85.0)
                        Text("90–180").tag(90.0)
                    }
                } header: {
                    Text("BPM-Analyse")
                } footer: {
                    Text("Gilt nur für Tracks ohne BPM-Tag. Werte aus den Tags (z. B. von Mixed In Key) haben immer Vorrang.")
                }

                Section {
                    if let name = model.folder.rootURL?.lastPathComponent {
                        LabeledContent("Ordner", value: name)
                    }
                    Button("Papierkorb leeren", role: .destructive) { confirmEmptyTrash = true }
                    if let trashMessage {
                        Text(trashMessage).foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("Papierkorb")
                } footer: {
                    Text("Aussortierte Tracks landen im Unterordner „_Papierkorb“ deines Musikordners und können dort bis zum Leeren wiederhergestellt werden.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Alle Dateien im Papierkorb endgültig löschen?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
                Button("Endgültig löschen", role: .destructive) {
                    trashMessage = model.emptyTrash()
                }
            }
        }
    }
}
