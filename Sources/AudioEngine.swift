import Foundation
import AVFoundation
import Combine

/// Аудиодвижок плеера.
///
/// Внутри всегда существует два независимых канала (A и B). Это нужно,
/// чтобы crossfade был честным: пока один трек затухает, второй уже звучит.
/// У каждого канала своя цепочка player -> EQ -> mainMixer. EQ используется
/// для эффекта High-cut (плавное закрытие верхов, как ручка фильтра на
/// диджейском контроллере).
final class AudioEngine: ObservableObject {

    // MARK: - Публикуемое состояние

    @Published private(set) var isPlaying = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var waveform: [Float] = []

    // MARK: - Настройки (приходят из AppModel)

    var settings = AppSettings()

    // MARK: - Внутренние узлы

    private final class Channel {
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        var file: AVAudioFile?
        var generation = 0
    }

    private let engine = AVAudioEngine()
    private var channels: [Channel] = []
    private var activeIndex = 0
    private var activeStartOffset: TimeInterval = 0

    private var rampTimer: Timer?
    private var timeTimer: Timer?
    private var rampGeneration = 0

    private let lowPassOpenFrequency: Float = 20000
    private let lowPassClosedFrequency: Float = 180
    private let rampStepsPerSecond: Double = 30

    // MARK: - Инициализация

    init() {
        channels = [Channel(), Channel()]

        for channel in channels {
            engine.attach(channel.player)
            engine.attach(channel.eq)

            let band = channel.eq.bands[0]
            band.filterType = .lowPass
            band.frequency = lowPassOpenFrequency
            band.bypass = true
            channel.eq.bypass = false

            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
            engine.connect(channel.player, to: channel.eq, format: format)
            // К главному микшеру подключаемся без явного формата: пусть движок
            // сам подберёт частоту устройства вывода. Явный формат здесь может
            // конфликтовать с 48 кГц на некоторых Mac.
            engine.connect(channel.eq, to: engine.mainMixerNode, format: nil)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("DJPlayer: не удалось запустить аудиодвижок — \(error.localizedDescription)")
        }
    }

    // MARK: - Основное управление

    func play(track: Track) {
        guard track.exists else {
            NSLog("DJPlayer: файл не найден — \(track.path)")
            return
        }

        if isPlaying && currentTrack != nil {
            // Трек уже играет: выбираем способ перехода.
            if settings.highCutEnabled {
                transitionWithHighCut(to: track)
            } else if settings.crossfadeEnabled {
                transitionWithCrossfade(to: track)
            } else {
                // Без эффектов: предыдущий просто останавливается.
                hardSwitch(to: track)
            }
        } else {
            hardSwitch(to: track)
        }
    }

    func stop() {
        cancelRamp()
        for channel in channels {
            channel.generation += 1
            channel.player.stop()
            channel.player.volume = 1.0
            resetLowPass(channel)
            channel.file = nil
        }
        stopTimeTimer()
        isPlaying = false
        isTransitioning = false
        currentTime = 0
        currentTrack = nil
        waveform = []
    }

    func pause() {
        guard isPlaying, !isTransitioning else { return }
        channels[activeIndex].player.pause()
        stopTimeTimer()
        isPlaying = false
    }

    func resume() {
        guard !isPlaying, currentTrack != nil, !isTransitioning else { return }
        let channel = channels[activeIndex]
        guard channel.file != nil else { return }
        channel.player.play()
        isPlaying = true
        startTimeTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if currentTrack != nil {
            resume()
        }
    }

    // MARK: - Переключение треков

    private func hardSwitch(to track: Track) {
        cancelRamp()

        // Гасим все каналы, затем стартуем на свободном.
        for channel in channels {
            channel.generation += 1
            channel.player.stop()
            channel.player.volume = 1.0
            resetLowPass(channel)
        }

        let index = 0
        activeIndex = index
        if start(track: track, onChannel: index) {
            isPlaying = true
        }
    }

    private func transitionWithCrossfade(to track: Track) {
        let oldIndex = activeIndex
        let newIndex = 1 - activeIndex
        cancelRamp()

        guard start(track: track, onChannel: newIndex, startVolume: 0) else { return }

        activeIndex = newIndex
        isTransitioning = true
        isPlaying = true

        let duration = max(0.3, settings.crossfadeDuration)
        let steps = max(2, Int(duration * rampStepsPerSecond))
        let interval = duration / Double(steps)
        rampGeneration += 1
        let generation = rampGeneration
        var step = 0

        let oldChannel = channels[oldIndex]
        let newChannel = channels[newIndex]

        rampTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self, generation == self.rampGeneration else {
                timer.invalidate()
                return
            }

            step += 1
            let progress = Float(min(step, steps)) / Float(steps)

            oldChannel.player.volume = 1 - progress
            newChannel.player.volume = progress

            if step >= steps {
                timer.invalidate()
                self.rampTimer = nil
                oldChannel.generation += 1
                oldChannel.player.stop()
                oldChannel.player.volume = 1.0
                oldChannel.file = nil
                self.isTransitioning = false
            }
        }
    }

    /// Эффект High-cut: у играющего трека плавно закрываются верхи.
    /// Следующий трек запускается только после полного завершения эффекта.
    private func transitionWithHighCut(to track: Track) {
        cancelRamp()

        let oldIndex = activeIndex
        let oldChannel = channels[oldIndex]

        isTransitioning = true
        isPlaying = true

        let duration = max(0.2, settings.highCutDuration)
        let steps = max(2, Int(duration * rampStepsPerSecond))
        let interval = duration / Double(steps)
        rampGeneration += 1
        let generation = rampGeneration
        var step = 0

        // Стартовое значение фильтра — открытый верх.
        if let band = oldChannel.eq.bands.first {
            band.bypass = false
            band.frequency = lowPassOpenFrequency
        }

        rampTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self, generation == self.rampGeneration else {
                timer.invalidate()
                return
            }

            step += 1
            let progress = Float(min(step, steps)) / Float(steps)

            if let band = oldChannel.eq.bands.first {
                // Экспоненциальная кривая звучит естественнее линейной.
                let curve = pow(progress, 1.5)
                band.frequency = self.lowPassOpenFrequency * pow(self.lowPassClosedFrequency / self.lowPassOpenFrequency, curve)
            }
            oldChannel.player.volume = max(0, 1 - progress * 0.6)

            if step >= steps {
                timer.invalidate()
                self.rampTimer = nil

                // Эффект закончился — только теперь запускаем следующий трек.
                oldChannel.generation += 1
                oldChannel.player.stop()
                oldChannel.player.volume = 1.0
                oldChannel.file = nil
                self.resetLowPass(oldChannel)

                let newIndex = 1 - oldIndex
                self.activeIndex = newIndex
                if self.start(track: track, onChannel: newIndex) {
                    self.isPlaying = true
                }
                self.isTransitioning = false
            }
        }
    }

    /// Запуск трека на конкретном канале. Возвращает false при ошибке чтения файла.
    @discardableResult
    private func start(track: Track, onChannel index: Int, startVolume: Float = 1.0) -> Bool {
        guard index >= 0, index < channels.count else { return false }
        let channel = channels[index]

        do {
            let file = try AVAudioFile(forReading: track.url)
            let format = file.processingFormat

            channel.generation += 1
            let generation = channel.generation

            channel.player.stop()
            channel.player.volume = startVolume
            resetLowPass(channel)

            // Переподключаем канал под формат конкретного файла.
            engine.disconnectNodeOutput(channel.player)
            engine.connect(channel.player, to: channel.eq, format: format)
            engine.connect(channel.eq, to: engine.mainMixerNode, format: format)

            if !engine.isRunning {
                try engine.start()
            }

            channel.file = file
            channel.player.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard channel.generation == generation else { return }
                    // Файл доиграл сам, без вмешательства пользователя.
                    if self.activeIndex == index && !self.isTransitioning {
                        self.stopTimeTimer()
                        self.isPlaying = false
                        self.currentTime = self.currentTrack?.duration ?? 0
                    }
                }
            }
            channel.player.play()

            currentTrack = track
            currentTime = 0
            activeStartOffset = 0
            startTimeTimer()
            if track.duration > 0 {
                loadWaveform(for: track)
            } else {
                Task { await self.ensureDurationAndWaveform(for: track) }
            }
            return true
        } catch {
            NSLog("DJPlayer: не удалось открыть файл \(track.path) — \(error.localizedDescription)")
            return false
        }
    }

    private func resetLowPass(_ channel: Channel) {
        if let band = channel.eq.bands.first {
            band.frequency = lowPassOpenFrequency
            band.bypass = true
        }
    }

    private func cancelRamp() {
        rampGeneration += 1
        rampTimer?.invalidate()
        rampTimer = nil
    }

    // MARK: - Отсчёт времени

    private func startTimeTimer() {
        stopTimeTimer()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimeTimer() {
        timeTimer?.invalidate()
        timeTimer = nil
    }

    private func tick() {
        guard isPlaying, !isTransitioning else { return }
        let channel = channels[activeIndex]
        guard let nodeTime = channel.player.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = channel.player.playerTime(forNodeTime: nodeTime) else {
            return
        }
        let rate = channel.file?.processingFormat.sampleRate ?? 44100
        guard rate > 0 else { return }
        currentTime = Double(playerTime.sampleTime) / rate + activeStartOffset
    }

    // MARK: - Длительность и waveform

    private func ensureDurationAndWaveform(for track: Track) async {
        let updated = await WaveformGenerator.load(for: track)
        await MainActor.run {
            var trackWithDuration = track
            trackWithDuration.duration = updated.duration
            self.currentTrack = trackWithDuration
            self.waveform = updated.peaks
        }
    }

    private func loadWaveform(for track: Track) {
        Task { @MainActor [weak self] in
            let result = await WaveformGenerator.load(for: track)
            guard let self else { return }
            // Показываем только если трек всё ещё актуален.
            if self.currentTrack?.path == track.path {
                self.waveform = result.peaks
            }
        }
    }
}
