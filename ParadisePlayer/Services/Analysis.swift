import AVFoundation
import Accelerate
import CryptoKit

// MARK: - Wellenform

nonisolated struct Waveform: Codable, Sendable {
    /// Spitzenpegel pro Abschnitt, 0...1 (1 = 0 dBFS). Nicht normalisiert,
    /// damit leise Masterings und Clipping sichtbar bleiben.
    var peaks: [Float]
    /// RMS pro Abschnitt, 0...1, für die "Dichte" der Wellenform.
    var rms: [Float]
}

nonisolated enum WaveformGenerator {
    static let bucketCount = 1_000

    static func cacheKey(id: String, size: Int64?) -> String {
        let digest = SHA256.hash(data: Data("\(id)|\(size ?? 0)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func loadOrGenerate(url: URL, cacheKey: String) throws -> Waveform {
        let dir = URL.cachesDirectory.appending(path: "Waveforms", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cacheURL = dir.appending(path: cacheKey + ".json")

        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(Waveform.self, from: data) {
            return cached
        }
        let waveform = try generate(url: url)
        if let data = try? JSONEncoder().encode(waveform) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return waveform
    }

    static func generate(url: URL) throws -> Waveform {
        let file = try AVAudioFile(forReading: url)
        let total = file.length
        let buckets = bucketCount
        guard total > 0 else { return Waveform(peaks: [], rms: []) }

        let framesPerBucket = max(1, Double(total) / Double(buckets))
        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
            return Waveform(peaks: [], rms: [])
        }
        let channels = Int(file.processingFormat.channelCount)

        var peaks = [Float](repeating: 0, count: buckets)
        var sumSquares = [Float](repeating: 0, count: buckets)
        var counts = [Int](repeating: 0, count: buckets)
        var position: AVAudioFramePosition = 0

        while position < total {
            try file.read(into: buffer, frameCount: chunk)
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }

            var i = 0
            while i < n {
                let globalFrame = position + AVAudioFramePosition(i)
                let bucket = min(buckets - 1, Int(Double(globalFrame) / framesPerBucket))
                let length: Int
                if bucket == buckets - 1 {
                    length = n - i
                } else {
                    let bucketEnd = AVAudioFramePosition(Double(bucket + 1) * framesPerBucket)
                    length = max(1, min(n - i, Int(bucketEnd - globalFrame)))
                }
                for c in 0..<channels {
                    let p = data[c] + i
                    var peak: Float = 0
                    var squares: Float = 0
                    vDSP_maxmgv(p, 1, &peak, vDSP_Length(length))
                    vDSP_svesq(p, 1, &squares, vDSP_Length(length))
                    peaks[bucket] = max(peaks[bucket], peak)
                    sumSquares[bucket] += squares / Float(channels)
                }
                counts[bucket] += length
                i += length
            }
            position += AVAudioFramePosition(n)
        }

        let rms = (0..<buckets).map { counts[$0] > 0 ? sqrt(sumSquares[$0] / Float(counts[$0])) : 0 }
        return Waveform(peaks: peaks.map { min($0, 1) }, rms: rms.map { min($0, 1) })
    }
}

// MARK: - BPM

/// Tempoerkennung für elektronische Musik mit geradem Beat.
/// Vorgehen: Bassdrum-Energie (Tiefpass ~150 Hz) -> Anstiege (Onsets)
/// -> Autokorrelation -> Kammfilter über 8 Vielfache für Genauigkeit im Zehntelbereich.
/// Der Suchbereich umfasst genau eine Oktave (z. B. 80–160 BPM), damit es
/// keine Halb-/Doppelt-Fehler gibt.
nonisolated enum BPMDetector {
    static func detect(url: URL, minBPM: Double) throws -> Double? {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let total = file.length
        let analysisSeconds = 90.0

        // Bei längeren Tracks das Intro überspringen
        let start: AVAudioFramePosition = total > AVAudioFramePosition(sampleRate * (analysisSeconds + 60))
            ? AVAudioFramePosition(sampleRate * 45) : 0
        let length = min(total - start, AVAudioFramePosition(sampleRate * analysisSeconds))
        guard length > AVAudioFramePosition(sampleRate * 8) else { return nil }
        file.framePosition = start

        let hop = max(64, Int((sampleRate / 172).rounded()))
        let fps = sampleRate / Double(hop)
        let alpha = Float(1 - exp(-2 * Double.pi * 150 / sampleRate))
        let channels = Int(format.channelCount)

        var lp1: Float = 0, lp2: Float = 0
        var accLow: Float = 0, accFull: Float = 0, accCount = 0
        var lowEnergy: [Float] = []
        var fullEnergy: [Float] = []
        lowEnergy.reserveCapacity(Int(length) / hop + 1)
        fullEnergy.reserveCapacity(Int(length) / hop + 1)

        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return nil }
        var remaining = length

        while remaining > 0 {
            let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining))
            try file.read(into: buffer, frameCount: toRead)
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            for i in 0..<n {
                var x: Float = 0
                for c in 0..<channels { x += data[c][i] }
                x /= Float(channels)
                lp1 += alpha * (x - lp1)
                lp2 += alpha * (lp1 - lp2)
                accLow += lp2 * lp2
                accFull += x * x
                accCount += 1
                if accCount == hop {
                    lowEnergy.append(accLow)
                    fullEnergy.append(accFull)
                    accLow = 0; accFull = 0; accCount = 0
                }
            }
            remaining -= AVAudioFramePosition(n)
        }

        // Onset-Kurve: Bassdrum stark gewichtet, Gesamtsignal leicht dazu
        let low = onsetCurve(lowEnergy)
        let full = onsetCurve(fullEnergy)
        var onset = zip(low, full).map { $0 + 0.3 * $1 }
        guard onset.count > 64 else { return nil }

        // leicht glätten, Mittelwert abziehen
        var smoothed = onset
        for i in 1..<(onset.count - 1) {
            smoothed[i] = 0.25 * onset[i - 1] + 0.5 * onset[i] + 0.25 * onset[i + 1]
        }
        let mean = smoothed.reduce(0, +) / Float(smoothed.count)
        onset = smoothed.map { $0 - mean }

        let maxBPM = minBPM * 2
        let lagMin = 60 * fps / maxBPM
        let lagMax = 60 * fps / minBPM
        let multiples = 8
        let maxLag = Int(lagMax * Double(multiples)) + 2
        let n = onset.count
        guard n > maxLag + 16 else { return nil }

        // Autokorrelation
        var acf = [Float](repeating: 0, count: maxLag + 1)
        onset.withUnsafeBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for lag in 1...maxLag {
                var r: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &r, vDSP_Length(n - lag))
                acf[lag] = r / Float(n - lag)
            }
        }

        func acfAt(_ x: Double) -> Float {
            let i = Int(x)
            guard i >= 0, i + 1 <= maxLag else { return 0 }
            let f = Float(x - Double(i))
            return acf[i] * (1 - f) + acf[i + 1] * f
        }

        func score(_ period: Double) -> Float {
            var s: Float = 0
            for k in 1...multiples { s += acfAt(period * Double(k)) }
            return s
        }

        // Grobsuche, dann Feinsuche
        var best = lagMin
        var bestScore = -Float.infinity
        var p = lagMin
        while p <= lagMax {
            let s = score(p)
            if s > bestScore { bestScore = s; best = p }
            p += 0.05
        }
        var fine = best - 0.1
        while fine <= best + 0.1 {
            let s = score(fine)
            if s > bestScore { bestScore = s; best = fine }
            fine += 0.005
        }
        guard bestScore > 0 else { return nil }

        let bpm = 60 * fps / best
        // Elektronische Tracks haben fast immer ganzzahlige BPM
        if abs(bpm - bpm.rounded()) < 0.15 { return bpm.rounded() }
        return (bpm * 10).rounded() / 10
    }

    private static func onsetCurve(_ energy: [Float]) -> [Float] {
        guard energy.count > 1 else { return energy }
        let compressed = energy.map { log1p($0 * 100) }
        var onset = [Float](repeating: 0, count: energy.count)
        for i in 1..<energy.count {
            onset[i] = max(0, compressed[i] - compressed[i - 1])
        }
        let peak = onset.max() ?? 1
        return peak > 0 ? onset.map { $0 / peak } : onset
    }
}
