import SwiftUI
import AppKit

/// Waveform трека с индикатором прогресса.
/// Верхняя часть окна зарезервирована под этот вид всегда — когда трек не
/// играет, показывается пустое состояние той же высоты.
struct WaveformView: View {

    let peaks: [Float]
    let progress: Double
    let accent: RGBAColor

    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            let capacity = max(1, Int(width / (barWidth + barSpacing)))
            let values = downsample(peaks, to: capacity)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.18))

                if values.isEmpty {
                    Text("Waveform появится при запуске трека")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .center, spacing: barSpacing) {
                        ForEach(Array(values.enumerated()), id: \.offset) { item in
                            let played = Double(item.offset) / Double(max(1, values.count - 1)) <= progress
                            let barHeight = max(2, CGFloat(item.element) * (height - 12))
                            RoundedRectangle(cornerRadius: 1)
                                .fill(played ? accent.swiftUIColor : Color.secondary.opacity(0.45))
                                .frame(width: barWidth, height: barHeight)
                        }
                    }
                    .frame(width: width, height: height, alignment: .leading)
                    .clipped()

                    // Курсор воспроизведения
                    Rectangle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: CGFloat(min(max(progress, 0), 1)) * width)
                }
            }
        }
    }

    private func downsample(_ source: [Float], to count: Int) -> [Float] {
        guard !source.isEmpty, count > 0 else { return [] }
        if source.count <= count { return source }

        var result: [Float] = []
        result.reserveCapacity(count)
        let ratio = Double(source.count) / Double(count)

        for i in 0..<count {
            let start = Int(Double(i) * ratio)
            let end = min(source.count, max(start + 1, Int(Double(i + 1) * ratio)))
            var peak: Float = 0
            for j in start..<end { peak = max(peak, source[j]) }
            result.append(peak)
        }
        return result
    }
}
