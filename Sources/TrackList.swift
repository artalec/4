import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Список треков выбранного плейлиста.
struct TrackList: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if let playlist = model.selectedPlaylist {
                if playlist.tracks.isEmpty {
                    emptyState
                } else {
                    trackList(playlist)
                }
            } else {
                VStack {
                    Text("Плейлист не выбран")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Панель над списком

    private var topBar: some View {
        HStack(spacing: 10) {
            if let playlist = model.selectedPlaylist {
                RoundedRectangle(cornerRadius: 3)
                    .fill(playlist.color.swiftUIColor)
                    .frame(width: 10, height: 10)
                Text(playlist.name).font(.headline)
            }

            Spacer()

            Text("Пробел — играть/пауза · Esc — стоп · двойной клик — запуск трека")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                model.playFirstTrackOfSelectedPlaylist()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Запустить первый трек")
            .disabled(model.selectedPlaylist?.tracks.isEmpty ?? true)

            Button {
                addTracks()
            } label: {
                Label("Добавить", systemImage: "plus")
            }
            .disabled(model.selectedPlaylist == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Список

    private func trackList(_ playlist: Playlist) -> some View {
        List {
            ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { item in
                TrackRow(
                    track: item.element,
                    isCurrent: model.audioEngine.currentTrack?.id == item.element.id
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.play(track: item.element)
                }
                .contextMenu {
                    Button("Воспроизвести") { model.play(track: item.element) }
                    Button("Удалить трек", role: .destructive) {
                        model.removeTrack(id: item.element.id)
                    }
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
            .onMove { source, destination in
                model.moveTracks(from: source, to: destination)
            }
            .onDelete { offsets in
                model.removeTracks(at: offsets)
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("В плейлисте пока нет треков")
                .foregroundStyle(.secondary)
            Button("Добавить треки") { addTracks() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Импорт файлов

    private func addTracks() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Выберите аудиофайлы"
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK {
            model.addTracks(urls: panel.urls)
        }
    }
}

// MARK: - Строка трека

private struct TrackRow: View {

    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(track.exists ? Color.secondary : Color.red)
                    .lineLimit(1)
            }

            Spacer()

            Text(track.duration.timecode)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        track.exists ? track.url.deletingLastPathComponent().lastPathComponent : "файл не найден"
    }
}
