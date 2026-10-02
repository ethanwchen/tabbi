import Foundation

/// Measurements shared by the focus sound tests.
enum FocusSignalAnalysis {
    static let sampleRate = 48_000.0

    static func rms(_ x: [Float]) -> Float {
        (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
    }

    static func mean(_ x: [Float]) -> Float {
        x.reduce(0, +) / Float(x.count)
    }

    static func peak(_ x: [Float]) -> Float {
        x.map(abs).max() ?? 0
    }

    static func decibels(_ ratio: Double) -> Double { 10 * log10(ratio) }

    /// Average spectral power near `frequency`, via Hann-windowed Goertzel
    /// over consecutive blocks and a few neighbouring bins.
    static func power(of x: [Float], near frequency: Double) -> Double {
        let n = 2048
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n - 1)) }
        let centerBin = Int((frequency * Double(n) / sampleRate).rounded())
        var total = 0.0
        var count = 0
        var start = 0
        while start + n <= x.count {
            for bin in (centerBin - 2)...(centerBin + 2) {
                let coefficient = 2 * cos(2 * Double.pi * Double(bin) / Double(n))
                var s1 = 0.0, s2 = 0.0
                for i in 0..<n {
                    let s0 = Double(x[start + i]) * window[i] + coefficient * s1 - s2
                    s2 = s1; s1 = s0
                }
                total += s1 * s1 + s2 * s2 - coefficient * s1 * s2
                count += 1
            }
            start += n
        }
        return total / Double(count)
    }

    /// Kurtosis (4th moment over squared variance): 3 for Gaussian noise,
    /// much higher when the signal is mostly quiet with sharp transients.
    static func kurtosis(_ x: [Float]) -> Double {
        let m = Double(mean(x))
        var m2 = 0.0, m4 = 0.0
        for v in x {
            let d = Double(v) - m
            m2 += d * d
            m4 += d * d * d * d
        }
        m2 /= Double(x.count); m4 /= Double(x.count)
        return m4 / (m2 * m2)
    }

    /// Coefficient of variation of the RMS over consecutive windows: near 0
    /// for steady noise, larger when the level ebbs and flows.
    static func levelVariation(_ x: [Float], windowSeconds: Double) -> Double {
        let n = Int(sampleRate * windowSeconds)
        let levels = stride(from: 0, to: x.count - n, by: n).map { Double(rms(Array(x[$0..<$0 + n]))) }
        let average = levels.reduce(0, +) / Double(levels.count)
        let variance = levels.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(levels.count)
        return variance.squareRoot() / average
    }
}
