import Foundation

enum SGStemWindowError: Error { case invalidWindow, outOfOrder, stale, busy }

struct SGStemWindowResult: Sendable {
    let generation: UInt64, track: UInt64, sourceFrame: UInt64
    let format: UInt32
    let vocals: [Float] // one hop of stereo interleaved PCM
}

// A serial worker feeds consecutive overlapping model windows. Only a completed hop
// is published; its source index never changes to conceal missing or late inference output.
actor SGStemWindowProcessor {
    let chunkSamples: Int
    let hopSamples: Int
    private let infer: @Sendable ([Float]) async throws -> [Float]
    private var generation: UInt64 = 0, track: UInt64 = 0, epoch: UInt64 = 0
    private var format: UInt32 = 0
    private var expectedFrame: UInt64?
    private var tail: [Float]?
    private var pending = false

    init(chunkSamples: Int, hopSamples: Int? = nil, infer: @escaping @Sendable ([Float]) async throws -> [Float]) throws {
        guard chunkSamples >= 2, chunkSamples <= 352800, chunkSamples % 2 == 0 else { throw SGStemWindowError.invalidWindow }
        let hop = hopSamples ?? chunkSamples / 2
        guard hop >= chunkSamples / 2, hop <= chunkSamples * 3 / 4 else { throw SGStemWindowError.invalidWindow }
        self.hopSamples = hop
        self.chunkSamples = chunkSamples
        self.infer = infer
    }

    func reset(generation: UInt64, track: UInt64, format: UInt32) {
        epoch &+= 1
        self.generation = generation; self.track = track; self.format = format
        expectedFrame = nil; tail = nil
        // An old in-flight inference still owns the model until it completes. Its result expires.
    }

    func process(_ pcm: [Float], sourceFrame: UInt64, generation: UInt64, track: UInt64, format: UInt32) async throws -> SGStemWindowResult {
        guard generation == self.generation, track == self.track, format == self.format else { throw SGStemWindowError.stale }
        guard !pending else { throw SGStemWindowError.busy }
        let hop = hopSamples, overlap = chunkSamples - hop
        guard pcm.count == chunkSamples * 2, sourceFrame <= UInt64.max - UInt64(hop) else { throw SGStemWindowError.invalidWindow }
        guard expectedFrame == nil || expectedFrame == sourceFrame else { throw SGStemWindowError.outOfOrder }
        let ticket = epoch
        pending = true
        defer { pending = false }
        let vocals = try await infer(pcm)
        try Task.checkCancellation()
        guard ticket == epoch else { throw SGStemWindowError.stale }
        guard vocals.count == pcm.count, vocals.allSatisfy(\.isFinite) else { throw SGStemWindowError.invalidWindow }
        var output = Array(vocals.prefix(hop * 2))
        if let tail {
            for i in 0..<overlap {
                let headWeight = Float(i + 1) / Float(overlap + 1)
                for c in 0..<2 {
                    let at = i * 2 + c
                    output[at] = tail[at] * (1 - headWeight) + output[at] * headWeight
                }
            }
        }
        tail = Array(vocals.suffix(overlap * 2))
        expectedFrame = sourceFrame + UInt64(hop)
        return SGStemWindowResult(generation: generation, track: track, sourceFrame: sourceFrame, format: format, vocals: output)
    }
}
