import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showFolderPicker = false
    @State private var showSettings = false
    @State private var showEQ = false
    @State private var showList = false
    @State private var listDetent: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if model.folder.rootURL == nil {
                    onboarding
                } else if horizontalSizeClass == .regular {
                    // iPad: Liste links, Player rechts
                    HStack(spacing: 0) {
                        TrackListView().frame(maxWidth: 440)
                        ScrollView { PlayerView(showEQ: $showEQ) }
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // iPhone: Player über den ganzen Bildschirm, Liste als eigenes Fenster
                    VStack(spacing: 12) {
                        PlayerView(showEQ: $showEQ)
                        Spacer(minLength: 0)
                        UpNextBar { showList = true }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                    // Wischgesten am unteren Rand (Home, Einhandmodus) erst beim zweiten Wischen
                    .defersSystemGestures(on: .bottom)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showFolderPicker = true } label: { Image(systemName: "folder") }
                        .accessibilityLabel("Ordner wählen")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("PARADISE PLAYER")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.textSecondary)
                        Text(model.folder.rootURL?.lastPathComponent ?? "Paradise Player")
                            .font(Theme.title(17))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.chooseFolder(url) }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().presentationBackground(Theme.background)
            }
            .sheet(isPresented: $showList) {
                NavigationStack {
                    TrackListView()
                        .background(Theme.background)
                        .navigationTitle("Trackliste")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fertig") { showList = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large], selection: $listDetent)
                .presentationBackground(Theme.background)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
            }
            .sheet(isPresented: $showEQ) {
                EQView()
                    .presentationDetents([.height(340)])
                    .presentationBackground(Theme.background)
            }
            .alert("Hinweis", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .task { await model.reloadIfNeeded() }
            .onChange(of: model.engine.isPlaying) { _, playing in
                // Display bleibt beim Durchhören an
                UIApplication.shared.isIdleTimerDisabled = playing
            }
        }
        .tint(Theme.text)
    }

    private var onboarding: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("THE RADIO")
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.textSecondary)
            Text("PARADISE PLAYER")
                .font(Theme.title(40))
                .tracking(-1.5)
                .foregroundStyle(Theme.text)
            Text("Wähle den iCloud-Ordner mit deinen Tracks. Die App spielt direkt daraus und lädt Dateien nur bei Bedarf.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textBody)
                .padding(.horizontal, 32)
            Button("Ordner wählen") { showFolderPicker = true }
                .buttonStyle(PillButtonStyle(tint: Theme.text, foreground: Theme.background))
                .padding(.top, 8)
            Spacer()
            Rectangle()
                .fill(Theme.neonGradient)
                .frame(height: 3)
                .clipShape(Capsule())
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
        }
    }
}

/// Leiste unter dem Player: öffnet die Trackliste und zeigt den nächsten Track.
struct UpNextBar: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surfaceRaised))
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRACKLISTE · \(model.visibleTracks.count)")
                        .font(.caption2.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                    Text(model.upcomingTrack.map { "Als Nächstes: " + model.title(for: $0) } ?? "Keine weiteren Tracks")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }
}
