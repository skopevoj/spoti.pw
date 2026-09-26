import Foundation

// Compare short, overlapping windows to the pinned long-window reference. This measures the effect
// of lost context, not separation quality against isolated ground-truth stems.
@main struct Overlap {
    static func floats(_ path: URL) throws -> [Float] {
        let data = try Data(contentsOf: path)
        return data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
    }
    static func main() async throws {
        guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 5 else { fatalError("overlap <short-assets> <reference-assets> <report.json> [hop-samples]") }
        let short = URL(fileURLWithPath: CommandLine.arguments[1])
        let reference = URL(fileURLWithPath: CommandLine.arguments[2])
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: short.appendingPathComponent("hashes.json")))
        let separator = try await SGStemSeparator(modelURL: short.appendingPathComponent("mbr_full_fp16.aimodel"), payloadHashes: hashes)
        let chunk = separator.chunkSamples
        let hop = CommandLine.arguments.count == 5 ? Int(CommandLine.arguments[4])! : chunk * 3 / 4
        let worker = try SGStemWindowProcessor(chunkSamples: chunk, hopSamples: hop) { try await separator.vocals(for: $0) }
        await worker.reset(generation: 1, track: 1, format: 1)
        let raw = try floats(reference.appendingPathComponent("golden_raw.f32"))
        let golden = try floats(reference.appendingPathComponent("golden_vocals.f32"))
        let count = raw.count / 2
        guard raw.count == golden.count, count > 2 * chunk else { fatalError("wrong reference shape") }
        var sum = [Float](repeating: 0, count: raw.count)
        for origin in stride(from: 0, through: count - chunk, by: hop) {
            var input = [Float](repeating: 0, count: chunk * 2)
            for i in 0..<chunk { input[i*2] = raw[origin+i]; input[i*2+1] = raw[count+origin+i] }
            let result = try await worker.process(input, sourceFrame: UInt64(origin), generation: 1, track: 1, format: 1)
            for i in 0..<hop {
                for c in 0..<2 { sum[c*count+origin+i] = result.vocals[i*2+c] }
            }
        }
        var aa = 0.0, bb = 0.0, dot = 0.0, error = 0.0, reconstruction = 0.0
        // Compare the same central region for every overlap, excluding partial edge windows.
        for i in chunk..<(count-chunk) {
            for c in 0..<2 {
                let at = c*count+i
                let vocal = Double(sum[at]), target = Double(golden[at])
                guard vocal.isFinite else { fatalError("nonfinite stem") }
                aa += vocal*vocal; bb += target*target; dot += vocal*target
                error += pow(vocal-target, 2)
                let original = Double(raw[at]), instrumental = original-vocal
                reconstruction = max(reconstruction, abs(vocal+instrumental-original))
            }
        }
        let report: [String: Any] = ["windowSamples": chunk, "hopSamples": hop,
            "comparedSeconds": Double(count-2*chunk)/44100, "cosineToLongWindow": dot/sqrt(aa*bb),
            "rmsRatioToLongWindow": sqrt(aa/bb), "relativeRMSError": sqrt(error/bb),
            "stemSumMaximumError": reconstruction, "listeningValidated": false]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        print(String(decoding: json, as: UTF8.self))
    }
}
