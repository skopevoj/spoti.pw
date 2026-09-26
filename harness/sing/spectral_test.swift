import Foundation

@main struct SpectralTest {
    static func main() throws {
        let dsp = try SGStemSpectralDSP()
        let count = SGStemSpectralDSP.samples
        // Separate stereo content, DC, Nyquist and impulses at both reflected boundaries.
        var pcm = [Float](repeating: 0, count: count * 2)
        for n in 0..<count {
            pcm[n*2] = Float(0.13 + 0.2 * sin(Double(n) * 0.023))
            pcm[n*2+1] = Float((n % 2 == 0 ? 0.08 : -0.08) + 0.3 * cos(Double(n) * 0.051))
        }
        pcm[0] = 0.9; pcm[pcm.count-1] = -0.9
        for _ in 0..<2 {
            let spectrum = try dsp.encode(pcm)
            let decoded = try spectrum.withUnsafeBufferPointer { try dsp.decode($0) }
            let error = zip(pcm, decoded).map { abs($0-$1) }.max()!
            precondition(error < 1e-5, "FFT scale, reflection, window or stereo layout changed: \(error)")
        }
        // Reusing the Core ML input and inverse scratch must not leave samples from a
        // prior window, including a transition from music to exact silence.
        var reused = [Float](repeating: .nan, count: 824100)
        for input in [pcm, [Float](repeating: 0, count: pcm.count), pcm] {
            try reused.withUnsafeMutableBufferPointer { try dsp.encode(input, into: $0) }
            let decoded = try reused.withUnsafeBufferPointer { try dsp.decode($0) }
            precondition(zip(input, decoded).allSatisfy { abs($0 - $1) < 1e-5 })
        }
        var short = [Float](repeating: 0, count: 2)
        do {
            try short.withUnsafeMutableBufferPointer { try dsp.encode(pcm, into: $0) }
            preconditionFailure("short output storage accepted")
        } catch SGStemError.invalidInput { }
        var invalid = pcm; invalid[1024] = .nan
        do { _ = try dsp.encode(invalid); preconditionFailure("non-finite input accepted") }
        catch SGStemError.invalidInput { }
        do { _ = try dsp.encode([]); preconditionFailure("short input accepted") }
        catch SGStemError.invalidInput { }
        let invalidSpectrum = [Float](repeating: .infinity, count: 824100)
        do { _ = try invalidSpectrum.withUnsafeBufferPointer { try dsp.decode($0) }; preconditionFailure("invalid spectrum accepted") }
        catch SGStemError.invalidOutput { }
        print("spectral DSP: repeated stereo round trips, boundary impulses, DC/Nyquist and invalid input passed")
    }
}
