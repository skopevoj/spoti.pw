// Spectral RoFormer backend. CPU inference is always available for background playback.
// An optional foreground GPU model shares the same PCM contract and actor-confined FFT scratch.
import Accelerate
import CoreML
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 27.0, macOS 27.0, *)
actor SGStemCoreMLSeparator {
    private let model: MLModel
    private var foregroundModel: MLModel?
    private var foregroundFailed = false
    private var lastAccelerated: Bool?
    private let dsp: SGStemSpectralDSP
    private let tensor: MLMultiArray
    private let provider: MLDictionaryFeatureProvider
    private let shape: [NSNumber] = [1, 2050, 201, 2]
    private let strides = [824100, 402, 2, 1]

    init(modelURL: URL, preferForegroundGPU: Bool = false) async throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        try Task.checkCancellation()
        let description = model.modelDescription
        guard description.stateDescriptionsByName.isEmpty,
              description.inputDescriptionsByName.count == 1, description.outputDescriptionsByName.count == 1,
              let input = description.inputDescriptionsByName["spectrum"]?.multiArrayConstraint,
              let output = description.outputDescriptionsByName["vocals_spectrum"]?.multiArrayConstraint,
              input.shape == shape, output.shape == shape,
              input.dataType == .float32, output.dataType == .float32 else { throw SGStemError.invalidModel }
        let tensor = try MLMultiArray(shape: shape, dataType: .float32)
        guard tensor.strides.map(\.intValue) == strides else { throw SGStemError.invalidInput }
        self.tensor = tensor
        self.provider = try MLDictionaryFeatureProvider(dictionary: ["spectrum": tensor])
        self.model = model
        self.dsp = try SGStemSpectralDSP()
        if preferForegroundGPU {
            let accelerated = MLModelConfiguration()
            accelerated.computeUnits = .cpuAndGPU
            // Failure to prepare the optional accelerator must leave the CPU model usable.
            do { self.foregroundModel = try await MLModel.load(contentsOf: modelURL, configuration: accelerated) }
            catch {
                try Task.checkCancellation()
                NSLog("[spotifyglass] Sing foreground acceleration unavailable: %@", String(describing: error))
            }
        }
    }

    private func foreground() async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run { UIApplication.shared.applicationState == .active }
        #else
        return true
        #endif
    }

    func warmUp() async throws {
        try encode([Float](repeating: 0, count: SGStemSpectralDSP.samples * 2))
        // Specialize both paths before publishing Ready. A lifecycle transition must not
        // incur a cold CPU prediction while already playing the reduced mix.
        _ = try predict(accelerated: false)
        if foregroundModel != nil, await foreground() { _ = try predict(accelerated: true) }
    }

    func vocals(for pcm: [Float]) async throws -> [Float] {
        try Task.checkCancellation()
        // A CPU-only bundle never consults UIKit and never loads or submits GPU work.
        let active = foregroundModel != nil ? await foreground() : false
        if !active { foregroundFailed = false }
        try encode(pcm)
        let accelerated = active && !foregroundFailed
        if lastAccelerated != accelerated {
            NSLog("[spotifyglass] Sing Core ML compute policy: %@", accelerated ? "foreground CPU/GPU" : "CPU only")
            lastAccelerated = accelerated
        }
        return try predict(accelerated: accelerated)
    }

    private func encode(_ pcm: [Float]) throws {
        try dsp.encode(pcm, into: UnsafeMutableBufferPointer(
            start: tensor.dataPointer.assumingMemoryBound(to: Float.self), count: tensor.count))
    }

    private func predict(accelerated: Bool) throws -> [Float] {
        try Task.checkCancellation()
        let result: MLFeatureProvider
        if accelerated, let foregroundModel {
            do { result = try foregroundModel.prediction(from: provider) }
            catch {
                try Task.checkCancellation()
                // Backgrounding can race with submission after the foreground check. Retry
                // this exact window on the already warm CPU model, preserving its timestamp.
                // Do not repeatedly submit a failing GPU plan until another inactive period.
                foregroundFailed = true
                NSLog("[spotifyglass] Sing using CPU after foreground prediction failed: %@", String(describing: error))
                result = try model.prediction(from: provider)
            }
        } else { result = try model.prediction(from: provider) }
        try Task.checkCancellation()
        guard let output = result.featureValue(for: "vocals_spectrum")?.multiArrayValue,
              output.shape == shape, output.dataType == .float32,
              output.strides.map(\.intValue) == strides else { throw SGStemError.invalidOutput }
        let values = UnsafeBufferPointer(start: output.dataPointer.assumingMemoryBound(to: Float.self), count: output.count)
        return try dsp.decode(values)
    }
}

// Actor-confined reusable FFT plans and scratch. PyTorch's centered, reflected STFT uses a
// periodic Hann window and an unscaled forward transform. The inverse is divided by N once.
@available(iOS 27.0, macOS 27.0, *)
final class SGStemSpectralDSP {
    static let samples = 88200
    private let size = 2048, hop = 441, pad = 1024, frames = 201
    private let forward: vDSP_DFT_Setup
    private let inverse: vDSP_DFT_Setup
    private let window: [Float]
    private let normalization: [Float]
    private var real = [Float](repeating: 0, count: 2048)
    private var imaginary = [Float](repeating: 0, count: 2048)
    private var outputReal = [Float](repeating: 0, count: 2048)
    private var outputImaginary = [Float](repeating: 0, count: 2048)
    private var accumulator = [Float](repeating: 0, count: 2048 + 88200)

    init() throws {
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, 2048, .FORWARD) else { throw SGStemError.invalidModel }
        guard let inverse = vDSP_DFT_zop_CreateSetup(nil, 2048, .INVERSE) else {
            vDSP_DFT_DestroySetup(forward)
            throw SGStemError.invalidModel
        }
        self.forward = forward; self.inverse = inverse
        let window = (0..<2048).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / 2048)) }
        self.window = window
        var weights = [Float](repeating: 0, count: 2048 + 88200)
        for frame in 0..<201 {
            for n in 0..<2048 { weights[frame * 441 + n] += window[n] * window[n] }
        }
        normalization = weights
    }
    deinit { vDSP_DFT_DestroySetup(forward); vDSP_DFT_DestroySetup(inverse) }

    func encode(_ pcm: [Float]) throws -> [Float] {
        var spectrum = [Float](repeating: 0, count: 2050 * frames * 2)
        try spectrum.withUnsafeMutableBufferPointer { try encode(pcm, into: $0) }
        return spectrum
    }

    func encode(_ pcm: [Float], into spectrum: UnsafeMutableBufferPointer<Float>) throws {
        guard pcm.count == Self.samples * 2, pcm.allSatisfy(\.isFinite),
              spectrum.count == 2050 * frames * 2 else { throw SGStemError.invalidInput }
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
        guard spectrum.count == 2050 * frames * 2, spectrum.allSatisfy(\.isFinite) else { throw SGStemError.invalidOutput }
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
