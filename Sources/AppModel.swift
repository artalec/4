import Foundation
import SwiftUI
import Combine

/// Единая модель приложения: состояние (плейлисты, настройки) + аудиодвижок.
/// Сделана синглтоном, потому что к ней обращается и SwiftUI-дерево, и
/// AppDelegate (перехват клавиш, сохранение при выходе).
final class AppModel: ObservableObject {

    static let shared = AppModel()

    @Published var state: AppState
    @Published var selectedPlaylistID: UUID?

    let audioEngine = AudioEngine()

    private let storage = StorageManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var autosaveWorkItem: DispatchWorkItem?

    private init() {
        let loaded = storage.load()
        self.state = loaded
        self.selectedPlaylistID = loaded.selectedPlaylistID ?? loaded.playlists.first?.id

        audioEngine.settings = loaded.settings

        // AudioEngine — отдельный ObservableObject. Без пересылки SwiftUI не узнает
        // об изменении времени, состояния и waveform, поэтому пробрасываем сигнал дальше.
        audioEngine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Любое изменение состояния — планируем автосохранение.
        $state
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleAutosave() }
            .store(in: &cancellables)

        $selectedPlaylistID
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleAutosave() }
            .store(in: &cancellables)
    }

    // MARK: - Текущий плейлист

    var playlistsSorted: [Playlist] {
        state.playlists.sorted { $0.order < $1.order }
    }

    var selectedPlaylist: Playlist? {
        guard let id = selectedPlaylistID else { return nil }
        return state.playlists.first { $0.id == id }
    }

    var selectedPlaylistIndex: Int? {
        guard let id = selectedPlaylistID else { return nil }
        return state.playlists.firstIndex { $0.id == id }
    }

    // MARK: - Плейлисты

    func addPlaylist(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Плейлист \(state.playlists.count + 1)" : trimmed
        let nextOrder = (state.playlists.map(\.order).max() ?? -1) + 1
        let color = RGBAColor.palette[state.playlists.count % RGBAColor.palette.count]
        let playlist = Playlist(name: title, color: color, order: nextOrder)
        state.playlists.append(playlist)
        selectedPlaylistID = playlist.id
        save()
    }

    func renamePlaylist(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = state.playlists.firstIndex(where: { $0.id == id }) else { return }
        state.playlists[index].name = trimmed
        save()
    }

    func setColor(_ color: RGBAColor, for id: UUID) {
        guard let index = state.playlists.firstIndex(where: { $0.id == id }) else { return }
        state.playlists[index].color = color
        save()
    }

    func deletePlaylist(id: UUID) {
        audioEngine.stop()
        state.playlists.removeAll { $0.id == id }
        if state.playlists.isEmpty {
            state.playlists = [Playlist(name: "Плейлист 1", order: 0)]
        }
        reindexPlaylists()
        if selectedPlaylistID == id {
            selectedPlaylistID = playlistsSorted.first?.id
        }
        save()
    }

    func movePlaylists(from source: IndexSet, to destination: Int) {
        var sorted = playlistsSorted
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, playlist) in sorted.enumerated() {
            if let i = state.playlists.firstIndex(where: { $0.id == playlist.id }) {
                state.playlists[i].order = index
            }
        }
        save()
    }

    private func reindexPlaylists() {
        let sorted = playlistsSorted
        for (index, playlist) in sorted.enumerated() {
            if let i = state.playlists.firstIndex(where: { $0.id == playlist.id }) {
                state.playlists[i].order = index
            }
        }
    }

    // MARK: - Треки

    func addTracks(urls: [URL]) {
        guard let playlistID = selectedPlaylistID,
              let index = state.playlists.firstIndex(where: { $0.id == playlistID }) else { return }

        let existingPaths = Set(state.playlists[index].tracks.map(\.path))
        var added: [Track] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            guard !existingPaths.contains(standardized.path) else { continue }
            added.append(Track(url: standardized))
        }

        guard !added.isEmpty else { return }
        state.playlists[index].tracks.append(contentsOf: added)
        save()

        // Длительности в фоне.
        Task { @MainActor [weak self] in
            for track in added {
                let result = await WaveformGenerator.load(for: track)
                self?.updateDuration(for: track.id, duration: result.duration)
            }
        }
    }

    private func updateDuration(for trackID: UUID, duration: TimeInterval) {
        guard duration > 0 else { return }
        for pIndex in state.playlists.indices {
            if let tIndex = state.playlists[pIndex].tracks.firstIndex(where: { $0.id == trackID }) {
                state.playlists[pIndex].tracks[tIndex].duration = duration
                scheduleAutosave()
                return
            }
        }
    }

    func removeTracks(at offsets: IndexSet) {
        guard let index = selectedPlaylistIndex else { return }
        let removing = offsets.map { state.playlists[index].tracks[$0] }

        if let current = audioEngine.currentTrack, removing.contains(where: { $0.id == current.id }) {
            audioEngine.stop()
        }
        state.playlists[index].tracks.remove(atOffsets: offsets)
        save()
    }

    func removeTrack(id: UUID) {
        guard let index = selectedPlaylistIndex else { return }
        if audioEngine.currentTrack?.id == id {
            audioEngine.stop()
        }
        state.playlists[index].tracks.removeAll { $0.id == id }
        save()
    }

    func moveTracks(from source: IndexSet, to destination: Int) {
        guard let index = selectedPlaylistIndex else { return }
        state.playlists[index].tracks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Воспроизведение

    func play(track: Track) {
        audioEngine.play(track: track)
    }

    /// Пробел: играет — пауза, на паузе — продолжить, иначе — первый трек плейлиста.
    func togglePlayPause() {
        if audioEngine.isPlaying {
            audioEngine.pause()
        } else if audioEngine.currentTrack != nil {
            audioEngine.resume()
        } else {
            playFirstTrackOfSelectedPlaylist()
        }
    }

    func playFirstTrackOfSelectedPlaylist() {
        guard let playlist = selectedPlaylist, let first = playlist.tracks.first else { return }
        play(track: first)
    }

    // MARK: - Настройки

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&state.settings)
        audioEngine.settings = state.settings
        // Отложенная запись: слайдер длительности вызывает это десятки раз
        // за одно перетаскивание, писать файл каждый раз не нужно.
        scheduleAutosave()
    }

    // MARK: - Сохранение

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        autosaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func save() {
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
        state.selectedPlaylistID = selectedPlaylistID
        storage.save(state)
    }

    // MARK: - Экспорт / импорт

    func exportSelectedPlaylist(to url: URL) {
        guard let playlist = selectedPlaylist else { return }
        do { try storage.export(playlist, to: url) }
        catch { NSLog("DJPlayer: экспорт не удался — \(error.localizedDescription)") }
    }

    func importPlaylist(from url: URL) {
        do {
            var playlist = try storage.`import`(from: url)
            playlist.order = (state.playlists.map(\.order).max() ?? -1) + 1
            state.playlists.append(playlist)
            selectedPlaylistID = playlist.id
            save()
        } catch {
            NSLog("DJPlayer: импорт не удался — \(error.localizedDescription)")
        }
    }
}
