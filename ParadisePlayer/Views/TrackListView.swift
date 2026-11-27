import SwiftUI

struct TrackListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Filter", selection: $model.filter) {
                    ForEach(TrackFilter.cases(for: model.settings.ratingStyle)) {
                        Text($0.label(for: model.settings.ratingStyle)).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                Button { Task { await model.reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surfaceRaised))
                        .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                }
                .accessibilityLabel("Ordner neu einlesen")

                Menu {
                    Picker("Sortierung", selection: $model.sort) {
                        ForEach(TrackSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surfaceRaised))
                        .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollViewReader { proxy in
                List(model.visibleTracks) { track in
                    row(track)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: model.currentID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .overlay { emptyOverlay }
        }
    }

    private func row(_ track: Track) -> some View {
        let isCurrent = track.id == model.currentID
        return TrackRow(
            title: model.title(for: track),
            artist: model.artist(for: track),
            info: model.store.info(track.id),
            isCurrent: isCurrent,
            isCompatible: model.isCompatibleWithCurrent(track),
            isDownloaded: track.isDownloaded,
            heartMode: model.settings.ratingStyle == .heart
        )
        .contentShape(Rectangle())
        .onTapGesture { model.select(track) }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous)
                .fill(isCurrent ? Theme.surfaceRaised : Color.clear)
                .padding(.horizontal, 8)
        )
        .listRowSeparatorTint(Theme.border)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { model.trash(track) } label: {
                Label("Papierkorb", systemImage: "trash")
            }
            .tint(Theme.danger)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: model.settings.ratingStyle == .heart) {
            if model.settings.ratingStyle == .heart {
                let hearted = model.store.info(track.id).isHearted
                Button { model.toggleHeart(for: track) } label: {
                    Label(hearted ? "Herz weg" : "Herz", systemImage: hearted ? "heart.slash" : "heart.fill")
                }
                .tint(Theme.neonPink)
            } else {
                ForEach([5, 4, 3], id: \.self) { stars in
                    Button { model.setRating(stars, for: track) } label: {
                        Label("\(stars)", systemImage: "star.fill")
                    }
                    .tint(stars == 5 ? Theme.neonOrange : stars == 4 ? Theme.neonPink : Theme.violet)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if model.isScanning && model.tracks.isEmpty {
            ProgressView("Ordner wird gelesen …")
                .tint(Theme.text)
                .foregroundStyle(Theme.textBody)
        } else if !model.isScanning && model.visibleTracks.isEmpty {
            ContentUnavailableView(
                model.tracks.isEmpty ? "Keine Tracks" : "Nichts in diesem Filter",
                systemImage: "music.note.list",
                description: Text(model.tracks.isEmpty
                    ? "Im gewählten Ordner wurden keine Audiodateien gefunden."
                    : "Wähle oben einen anderen Filter.")
            )
            .foregroundStyle(Theme.textBody)
        }
    }
}

struct TrackRow: View {
    let title: String
    let artist: String?
    let info: TrackInfo
    let isCurrent: Bool
    let isCompatible: Bool
    let isDownloaded: Bool
    var heartMode = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "waveform").foregroundStyle(Theme.neonPink)
                } else if !isDownloaded {
                    Image(systemName: "icloud").foregroundStyle(Theme.textSecondary)
                } else {
                    Color.clear
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let artist {
                        Text(artist).lineLimit(1)
                    }
                    if heartMode {
                        if info.isHearted {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.neonPink)
                        }
                    } else if info.rating > 0 {
                        HStack(spacing: 1) {
                            ForEach(0..<info.rating, id: \.self) { _ in
                                Image(systemName: "star.fill").font(.system(size: 8))
                            }
                        }
                        .foregroundStyle(Theme.star)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            if let bpm = info.bpm {
                Text(String(format: "%.1f", bpm))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.textBody)
            }
            if let key = info.camelot {
                CamelotBadge(key: key, compact: true)
                    .opacity(isCompatible || isCurrent ? 1 : 0.45)
            }
        }
        .padding(.vertical, 4)
    }
}
