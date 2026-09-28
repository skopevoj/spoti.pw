// The STFT around Sing's model, the one PyTorch took when the model was trained: centred, the ends
// reflected, a periodic Hann window, an unscaled forward transform and the inverse divided by N once,
// overlap-added with the window's own weight taken out. The plans and the scratch are made once and reused
// window after window; the separator's actor is the only one to use them.
import Accelerate
import Foundation

@available(iOS 27.0, macOS 27.0, *)
final class SGStemSpectralDSP {
    static let samples = SGStemShape.windowFrames
    private let size = SGStemShape.fftSize, hop = SGStemShape.stftHop, frames = SGStemShape.stftFrames
    private let pad = SGStemShape.fftSize / 2
    private let forward: vDSP_DFT_Setup
    private let inverse: vDSP_DFT_Setup
    private let window: [Float]
    private let normalization: [Float]
    private var real = [Float](repeating: 0, count: SGStemShape.fftSize)
    private var imaginary = [Float](repeating: 0, count: SGStemShape.fftSize)
    private var outputReal = [Float](repeating: 0, count: SGStemShape.fftSize)
    private var outputImaginary = [Float](repeating: 0, count: SGStemShape.fftSize)
    private var accumulator = [Float](repeating: 0, count: SGStemShape.fftSize + samples)

    init() throws {
        let size = SGStemShape.fftSize, hop = SGStemShape.stftHop
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD) else { throw SGStemError.invalidModel }
        guard let inverse = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .INVERSE) else {
            vDSP_DFT_DestroySetup(forward)
            throw SGStemError.invalidModel
        }
        self.forward = forward; self.inverse = inverse
        let window = (0..<size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size))) }
        self.window = window
        var weights = [Float](repeating: 0, count: size + Self.samples)
        for frame in 0..<SGStemShape.stftFrames {
            for n in 0..<size { weights[frame * hop + n] += window[n] * window[n] }
        }
        normalization = weights
    }
    deinit { vDSP_DFT_DestroySetup(forward); vDSP_DFT_DestroySetup(inverse) }

    func encode(_ pcm: [Float]) throws -> [Float] {
        var spectrum = [Float](repeating: 0, count: SGStemShape.spectrumCount)
        try spectrum.withUnsafeMutableBufferPointer { try encode(pcm, into: $0) }
        return spectrum
    }

    func encode(_ pcm: [Float], into spectrum: UnsafeMutableBufferPointer<Float>) throws {
        guard pcm.count == Self.samples * 2, pcm.allSatisfy(\.isFinite),
              spectrum.count == SGStemShape.spectrumCount else { throw SGStemError.invalidInput }
        for n in 0..<size { imaginary[n] = 0 }
        for channel in 0..<2 {
            for frame in 0..<frames {
                for n in 0..<size {
                    let index = frame * hop - pad + n
                    let reflected = index < 0 ? -index : index >= Self.samples ? 2 * Self.samples - 2 - index : index
                    real[n] = pcm[reflected * 2 + channel] * window[n]
                }
                vDSP_DFT_Execute(forward, real, imaginary, &outputReal, &outputImaginary)
                for bin in 0...size/2 {
                    let at = ((bin * 2 + channel) * frames + frame) * 2
                    spectrum[at] = outputReal[bin]; spectrum[at + 1] = outputImaginary[bin]
                }
            }
        }
    }

    func decode(_ spectrum: UnsafeBufferPointer<Float>) throws -> [Float] {
        guard spectrum.count == SGStemShape.spectrumCount, spectrum.allSatisfy(\.isFinite) else { throw SGStemError.invalidOutput }
        var result = [Float](repeating: 0, count: Self.samples * 2)
        for channel in 0..<2 {
            accumulator.withUnsafeMutableBufferPointer { vDSP_vclr($0.baseAddress!, 1, vDSP_Length($0.count)) }
            for frame in 0..<frames {
                for bin in 0...size/2 {
                    let at = ((bin * 2 + channel) * frames + frame) * 2
                    real[bin] = spectrum[at]; imaginary[bin] = spectrum[at + 1]
                    if bin > 0 && bin < size/2 {
                        real[size-bin] = real[bin]; imaginary[size-bin] = -imaginary[bin]
                    }
                }
                imaginary[0] = 0; imaginary[size/2] = 0
                vDSP_DFT_Execute(inverse, real, imaginary, &outputReal, &outputImaginary)
                for n in 0..<size { accumulator[frame * hop + n] += outputReal[n] * window[n] / Float(size) }
            }
            for n in 0..<Self.samples { result[n*2+channel] = accumulator[n+pad] / max(normalization[n+pad], 1e-8) }
        }
        guard result.allSatisfy(\.isFinite) else { throw SGStemError.invalidOutput }
        return result
    }
}
