import Foundation

actor Predictor {
    var calls = 0
    var delayed = false
    var continuation: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    func setDelayed() { delayed = true }
    func waitUntilRunning() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
    func run(_ pcm: [Float]) async -> [Float] {
        calls += 1
        let number = calls
        if delayed {
            await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
            delayed = false
        }
        return [Float](repeating: Float(number), count: pcm.count)
    }
}

@main struct WindowTest {
    static func main() async throws {
        let fake = Predictor()
        let worker = try SGStemWindowProcessor(chunkSamples: 8) { await fake.run($0) }
        await worker.reset(generation: 1, track: 2, format: 3)
        let pcm = [Float](repeating: 0, count: 16)
        let first = try await worker.process(pcm, sourceFrame: 100, generation: 1, track: 2, format: 3)
        precondition(first.vocals == [Float](repeating: 1, count: 8) && first.sourceFrame == 100)
        let next = try await worker.process(pcm, sourceFrame: 104, generation: 1, track: 2, format: 3)
        for i in 0..<4 { for c in 0..<2 { precondition(abs(next.vocals[i*2+c] - (1 + Float(i+1)/5)) < 1e-6) } }
        do {
            _ = try await worker.process(pcm, sourceFrame: 109, generation: 1, track: 2, format: 3)
            preconditionFailure("accepted a source gap")
        } catch SGStemWindowError.outOfOrder {}
        await fake.setDelayed()
        let pending = Task { try await worker.process(pcm, sourceFrame: 108, generation: 1, track: 2, format: 3) }
        await fake.waitUntilRunning()
        await worker.reset(generation: 2, track: 9, format: 3)
        do {
            _ = try await worker.process(pcm, sourceFrame: 0, generation: 2, track: 9, format: 3)
            preconditionFailure("ran two inferences at once")
        } catch SGStemWindowError.busy {}
        await fake.release()
        do { _ = try await pending.value; preconditionFailure("published stale in-flight audio") }
        catch SGStemWindowError.stale {}
        let reset = try await worker.process(pcm, sourceFrame: 0, generation: 2, track: 9, format: 3)
        precondition(reset.generation == 2 && reset.track == 9 && reset.sourceFrame == 0)
        precondition(reset.vocals == [Float](repeating: 4, count: 8), "retained an old overlap tail")
        let efficient = try SGStemWindowProcessor(chunkSamples: 8, hopSamples: 6) { await fake.run($0) }
        await efficient.reset(generation: 3, track: 9, format: 3)
        let wide = try await efficient.process(pcm, sourceFrame: 0, generation: 3, track: 9, format: 3)
        precondition(wide.vocals == [Float](repeating: 5, count: 12))
        let joined = try await efficient.process(pcm, sourceFrame: 6, generation: 3, track: 9, format: 3)
        for i in 0..<6 { for c in 0..<2 {
            let expected: Float = i < 2 ? 5 + Float(i+1)/3 : 6
            precondition(abs(joined.vocals[i*2+c] - expected) < 1e-6)
        } }
        precondition(joined.sourceFrame == 6 && joined.vocals.count == 12)
        print("sing windows: complementary overlap, source indices, serial inference and stale completion rejection passed")
    }
}
