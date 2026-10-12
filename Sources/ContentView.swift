import SwiftUI
import AppKit

/// Главное окно.
///
/// Раскладка:
///   слева  — список плейлистов
///   справа — верхняя полоса с waveform (место зарезервировано всегда),
///            строка управления справа вверху, ниже — список треков.
struct ContentView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            PlaylistSidebar()
                .frame(minWidth: 210, idealWidth: 250, maxWidth: 340)

            VStack(spacing: 0) {
                WaveformPanel()
                Divider()
                TrackList()
            }
            .frame(minWidth: 560)
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

// MARK: - Верхняя полоса: управление + waveform

private struct WaveformPanel: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                trackInfo
                Spacer(minLength: 12)
                controls
            }

            WaveformView(
                peaks: model.audioEngine.waveform,
                progress: progress,
                accent: model.selectedPlaylist?.color ?? RGBAColor(red: 0.2, green: 0.55, blue: 1.0)
            )
            .frame(height: 84)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var progress: Double {
        guard let duration = model.audioEngine.currentTrack?.duration, duration > 0 else { return 0 }
        return min(max(model.audioEngine.currentTime / duration, 0), 1)
    }

    // MARK: Информация о треке

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let track = model.audioEngine.currentTrack {
                Text(track.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(model.audioEngine.currentTime.timecode)
                    Text("/")
                    Text(track.duration.timecode)
                    if model.audioEngine.isTransitioning {
                        Text("· переход…")
                            .foregroundStyle(Color.orange)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            } else {
                Text("Ничего не играет")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Выберите трек и нажмите Пробел")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    // MARK: Переключатели эффектов (правый верхний угол)

    private var controls: some View {
        HStack(spacing: 14) {

            // --- Crossfade ---
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Crossfade", isOn: Binding(
                    get: { model.state.settings.crossfadeEnabled },
                    set: { value in
                        model.updateSettings { $0.crossfadeEnabled = value }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Плавный переход между треками")

                durationStepper(
                    label: "переход",
                    value: model.state.settings.crossfadeDuration,
                    range: 0.5...15,
                    enabled: model.state.settings.crossfadeEnabled && !model.state.settings.highCutEnabled
                ) { newValue in
                    model.updateSettings { $0.crossfadeDuration = newValue }
                }
            }

            Divider().frame(height: 34)

            // --- High-cut filter ---
            VStack(alignment: .leading, spacing: 3) {
                Toggle("High-cut", isOn: Binding(
                    get: { model.state.settings.highCutEnabled },
                    set: { value in
                        model.updateSettings { $0.highCutEnabled = value }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.state.settings.crossfadeEnabled)
                .help("Плавно «уводит» верхи у играющего трека, затем запускает следующий")

                durationStepper(
                    label: "эффект",
                    value: model.state.settings.highCutDuration,
                    range: 0.3...10,
                    enabled: model.state.settings.highCutEnabled
                ) { newValue in
                    model.updateSettings { $0.highCutDuration = newValue }
                }
            }

            Divider().frame(height: 34)

            Button {
                model.audioEngine.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .help("Остановить (Esc)")
            .disabled(model.audioEngine.currentTrack == nil)
        }
    }

    private func durationStepper(label: String,
                                 value: Double,
                                 range: ClosedRange<Double>,
                                 enabled: Bool,
                                 onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: range
            )
            .frame(width: 86)
            .controlSize(.mini)
            .disabled(!enabled)

            Text(String(format: "%.1fs", value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}
