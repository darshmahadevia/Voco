import Foundation

enum AudioMeter {
    static let barCount = 11
    private static let bandEdges = [80.0, 140, 210, 310, 450, 650, 950, 1_400, 2_000, 2_900, 4_200, 6_000]

    static func measure(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> (rms: Double, level: Double, waveform: [Double]) {
        let totalEnergy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = samples.isEmpty ? 0 : sqrt(totalEnergy / Double(samples.count))
        let level = normalize(rms)
        guard level > 0, samples.count > 1 else {
            return (rms, level, Array(repeating: 0, count: barCount))
        }

        var windowEnergy = 0.0
        let count = Double(samples.count)
        let windowed = samples.enumerated().map { index, sample in
            let weight = 0.5 - 0.5 * cos(2 * .pi * Double(index) / count)
            windowEnergy += weight * weight
            return Double(sample) * weight
        }
        let waveform = (0..<barCount).map { bar in
            let firstBin = max(1, Int(ceil(bandEdges[bar] * count / sampleRate)))
            let endBin = min(samples.count / 2, Int(ceil(bandEdges[bar + 1] * count / sampleRate)))
            var energy = 0.0
            for bin in firstBin..<max(firstBin, endBin) {
                let coefficient = 2 * cos(2 * .pi * Double(bin) / count)
                var previous = 0.0
                var beforePrevious = 0.0
                for sample in windowed {
                    let next = sample + coefficient * previous - beforePrevious
                    beforePrevious = previous
                    previous = next
                }
                energy += max(0, previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious)
            }
            let bandRMS = sqrt(2 * energy / (count * windowEnergy))
            let bandLevel = min(1, max(0, (bandRMS - 0.0006) * 30))
            return 0.2 * level + 0.8 * bandLevel
        }
        return (rms, level, waveform)
    }

    private static func normalize(_ rms: Double) -> Double {
        min(1, max(0, (rms - 0.003) * 12))
    }
}
