// Local-only Mel Band RoFormer adapter. Core ML uses worker-side FFTs and CPU background
// inference; Core AI includes its transforms. No downloads or calls from RemoteIO.
// Graph contract/provenance: harness/sing/README.md and harness/sing/model.json.
import Foundation
import CryptoKit
#if canImport(CoreAI)
import CoreAI
#endif

@available(iOS 27.0, macOS 27.0, *)
enum SGStemError: Error {
    case invalidModel, hashMismatch, invalidInput, invalidOutput, cancelled
}

@available(iOS 27.0, macOS 27.0, *)
actor SGStemSeparator {
    static let sampleRate = 44_100
    #if canImport(CoreAI)
    private let function: InferenceFunction?
    private let input: NDArrayDescriptor?
    #endif
    private let coreML: SGStemCoreMLSeparator?
    let chunkSamples: Int
    private let frameCount: Int
    private let normalization: [Float]
    private var generation: UInt64 = 0
    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let fftSize = 2048, hop = 441, pad = 1024

    // Verify the graph's payload before its runtime sees it. Hashing and model specialization happen
    // on this actor, outside playback-critical paths. An AOT profile must verify all its payloads.
    init(modelURL: URL, payloadHashes: [String: String], preferForegroundGPU: Bool = false) async throws {
        guard !payloadHashes.isEmpty else { throw SGStemError.invalidModel }
        for (relative, expected) in payloadHashes {
            guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
                throw SGStemError.invalidModel
            }
            let url = modelURL.appendingPathComponent(relative)
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var digest = SHA256()
            while let data = try file.read(upToCount: 1 << 20), !data.isEmpty { digest.update(data: data) }
            let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw SGStemError.hashMismatch }
        }
        try Task.checkCancellation()
        if modelURL.pathExtension == "mlmodelc" {
            let coreML = try await SGStemCoreMLSeparator(modelURL: modelURL, preferForegroundGPU: preferForegroundGPU)
            // Core ML's first prediction can allocate/specialize beyond model loading. Pay
            // that cost before announcing Ready, while Spotify still plays its original audio.
            // The warm model store shares this work; seeks do not repeat it.
            try await coreML.warmUp()
            try Task.checkCancellation()
            self.coreML = coreML
            #if canImport(CoreAI)
            self.function = nil; self.input = nil
            #endif
            self.frameCount = 201; self.chunkSamples = 88200; self.normalization = []
            return
        }
        self.coreML = nil
        #if canImport(CoreAI)
        let model = try await AIModel(contentsOf: modelURL, options: SpecializationOptions(preferredComputeUnitKind: .gpu))
        try Task.checkCancellation()
        guard let descriptor = model.functionDescriptor(for: "main"), descriptor.stateNames.isEmpty,
              case .ndArray(let input) = descriptor.inputDescriptor(of: "frames"),
              case .ndArray(let output) = descriptor.outputDescriptor(of: "recon"),
              input.shape.count == 4, input.shape[0] == 1, input.shape[1] == 2,
              input.shape[3] == 2048, input.shape[2] >= 101, input.shape[2] <= 801,
              input.shape == output.shape, input.scalarType == .float16 || input.scalarType == .float32,
              let function = try model.loadFunction(named: "main") else { throw SGStemError.invalidModel }
        self.function = function
        self.input = input
        self.frameCount = input.shape[2]
        self.chunkSamples = (input.shape[2] - 1) * 441
        let total = 2048 + (input.shape[2] - 1) * 441
        var weights = [Float](repeating: 0, count: total)
        for f in 0..<input.shape[2] {
            for n in 0..<2048 {
                let window = 0.5 - 0.5 * cos(2 * Float.pi * Float(n) / 2048)
                weights[f * 441 + n] += window * window
            }
        }
        self.normalization = weights
        #else
        throw SGStemError.invalidModel
        #endif
    }

    func invalidate() { generation &+= 1 }

    private func acquire() async {
        if running { await withCheckedContinuation { waiters.append($0) } }
        else { running = true }
    }
    private func release() {
        if waiters.isEmpty { running = false }
        else { waiters.removeFirst().resume() }
    }

    // Stereo interleaved PCM in and vocals out. Instrumental is mix - vocals, without normalization.
    // This is one native graph window; the streaming host must do a second overlap-add between
    // windows. It must not pass an eight-second window off as a low-latency live separator.
    func vocals(for pcm: [Float]) async throws -> [Float] {
        guard pcm.count == chunkSamples * 2, pcm.allSatisfy(\.isFinite) else { throw SGStemError.invalidInput }
        // Actor methods can reenter during run(). A new seek generation must wait asynchronously
        // for the old inference to finish before reusing this warm function.
        await acquire()
        defer { release() }
        let ticket = generation
        try Task.checkCancellation()
        if let coreML {
            let result = try await coreML.vocals(for: pcm)
            try Task.checkCancellation()
            guard ticket == generation else { throw SGStemError.cancelled }
            return result
        }
        #if canImport(CoreAI)
        guard let input, let function else { throw SGStemError.invalidModel }
        let count = 2 * frameCount * fftSize
        var framed = [Float](repeating: 0, count: count)
        for channel in 0..<2 {
            for frame in 0..<frameCount {
                let origin = frame * hop - pad
                for n in 0..<fftSize {
                    let index = origin + n
                    let reflected = index < 0 ? -index : index >= chunkSamples ? 2 * chunkSamples - 2 - index : index
                    framed[(channel * frameCount + frame) * fftSize + n] = pcm[reflected * 2 + channel]
                }
            }
        }
        var tensor = NDArray(descriptor: input)
        if input.scalarType == .float16 {
            var view = tensor.mutableView(as: Float16.self)
            view.copyElements(fromContentsOf: framed.map(Float16.init))
        } else {
            var view = tensor.mutableView(as: Float.self)
            view.copyElements(fromContentsOf: framed)
        }
        var result = try await function.run(inputs: ["frames": tensor])
        try Task.checkCancellation()
        guard ticket == generation else { throw SGStemError.cancelled }
        guard let recon = result.remove("recon")?.ndArray, recon.shape == input.shape else { throw SGStemError.invalidOutput }
        let values: [Float]
        switch recon.scalarType {
        case .float16:
            values = recon.view(as: Float16.self).withUnsafePointer { pointer, _, _ in
                UnsafeBufferPointer(start: pointer, count: count).map(Float.init)
            }
        case .float32:
            values = recon.view(as: Float.self).withUnsafePointer { pointer, _, _ in
                Array(UnsafeBufferPointer(start: pointer, count: count))
            }
        default: throw SGStemError.invalidOutput
        }
        guard values.allSatisfy(\.isFinite) else { throw SGStemError.invalidOutput }
        var vocals = [Float](repeating: 0, count: pcm.count)
        for channel in 0..<2 {
            var accumulator = [Float](repeating: 0, count: normalization.count)
            for frame in 0..<frameCount {
                for n in 0..<fftSize {
                    accumulator[frame * hop + n] += values[(channel * frameCount + frame) * fftSize + n]
                }
            }
            for n in 0..<chunkSamples {
                vocals[n * 2 + channel] = accumulator[n + pad] / max(normalization[n + pad], 1e-8)
            }
        }
        return vocals
        #else
        throw SGStemError.invalidModel
        #endif
    }
}
