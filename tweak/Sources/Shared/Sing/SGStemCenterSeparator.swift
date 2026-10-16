// Sing's built-in separator, for an iPhone without the Core ML voice model (SGSingModel.h): it needs no
// download and no neural network. It takes the same two-second spectrum the model does (SGStemSpectralDSP.swift)
// and keeps of it what sits in the middle of the stereo image, where a lead voice is mixed: how alike the left
// and the right of each frequency are (in phase, and as loud) makes a mask, smoothed over time and over
// frequency, that is multiplied into the mid signal, and only above about 150 Hz, so the kick and the bass,
// centred too, stay with the instrumental. What is panned to a side, or wide, is left alone entirely.
// It is not as clean as the model: another centred instrument (a snare, a solo) goes with the voice, a song
// in mono has no middle to tell the voice from, and the voice's reverb, spread wide, stays in the music.
// harness/sing/center_test.py is the same arithmetic in numpy, to try a change in before a phone.
import Foundation

@available(iOS 18.0, macOS 15.0, *)
actor SGStemCenterSeparator: SGStemSeparating {
    let windowFrames = SGStemShape.windowFrames
    private let dsp: SGStemSpectralDSP
    private let band: [Float]
    private var mask: [Float]
    private var smoothed: [Float]

    // A mask below this likeness of the two channels is nothing, above that one it is everything.
    private static let lowLikeness: Float = 0.55, highLikeness: Float = 0.95

    init() throws {
        dsp = try SGStemSpectralDSP()
        let bins = SGStemShape.bins
        func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
            let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
            return t * t * (3 - 2 * t)
        }
        band = (0..<bins).map { bin in
            let hertz = Double(bin) * 44100 / Double(SGStemShape.fftSize)
            return Float(smoothstep(90, 200, hertz) * (1 - 0.3 * smoothstep(6500, 12000, hertz)))
        }
        let blank = [Float](repeating: 0, count: bins * SGStemShape.stftFrames)
        mask = blank
        smoothed = blank
    }

    // Nothing to load or specialise.
    func warmUp() async throws {}

    func vocals(for pcm: [Float]) async throws -> [Float] {
        guard pcm.count == windowFrames * 2, pcm.allSatisfy(\.isFinite) else { throw SGStemError.invalidInput }
        try Task.checkCancellation()
        var spectrum = try dsp.encode(pcm)
        let bins = SGStemShape.bins, frames = SGStemShape.stftFrames
        // The layout is SGStemSpectralDSP's: [bin, channel, frame, real or imaginary].
        func at(_ bin: Int, _ channel: Int, _ frame: Int) -> Int { ((bin * 2 + channel) * frames + frame) * 2 }

        for bin in 0..<bins {
            for frame in 0..<frames {
                let i = at(bin, 0, frame), j = at(bin, 1, frame)
                let lr = spectrum[i], li = spectrum[i + 1], rr = spectrum[j], ri = spectrum[j + 1]
                let energy = lr * lr + li * li + rr * rr + ri * ri
                let likeness = 2 * (lr * rr + li * ri) / (energy + 1e-9)
                let t = min(max((likeness - Self.lowLikeness) / (Self.highLikeness - Self.lowLikeness), 0), 1)
                mask[bin * frames + frame] = t * t * (3 - 2 * t)
            }
        }
        // Over time, then over frequency: three taps, the ends kept.
        for bin in 0..<bins {
            let row = bin * frames
            for frame in 0..<frames {
                let before = mask[row + max(frame - 1, 0)], after = mask[row + min(frame + 1, frames - 1)]
                smoothed[row + frame] = 0.25 * before + 0.5 * mask[row + frame] + 0.25 * after
            }
        }
        for bin in 0..<bins {
            let up = max(bin - 1, 0) * frames, here = bin * frames, down = min(bin + 1, bins - 1) * frames
            for frame in 0..<frames {
                mask[here + frame] = (0.25 * smoothed[up + frame] + 0.5 * smoothed[here + frame] + 0.25 * smoothed[down + frame]) * band[bin]
            }
        }
        // The vocals are the mid signal under the mask, the same in both channels.
        for bin in 0..<bins {
            for frame in 0..<frames {
                let i = at(bin, 0, frame), j = at(bin, 1, frame)
                let gain = 0.5 * mask[bin * frames + frame]
                let real = gain * (spectrum[i] + spectrum[j]), imaginary = gain * (spectrum[i + 1] + spectrum[j + 1])
                spectrum[i] = real; spectrum[i + 1] = imaginary
                spectrum[j] = real; spectrum[j + 1] = imaginary
            }
        }
        try Task.checkCancellation()
        return try spectrum.withUnsafeBufferPointer { try dsp.decode($0) }
    }
}
