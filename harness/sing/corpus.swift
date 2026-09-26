// Compare real short-window separation with a supplied reference corpus. All audio stays local.
import Foundation

@main struct Corpus {
    static func read(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count % 8 == 0 else { throw SGStemError.invalidInput }
        return data.withUnsafeBytes { p in
            stride(from: 0, to: p.count, by: 4).map { p.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
    }
    static func score(_ estimate: [Float], _ reference: [Float], _ mix: [Float]) -> [String: Double] {
        // Compare identical samples at either hop length. Leave a whole two-second window
        // at the end, since different strides publish different lengths of the final tail.
        let first = 44100 * 2, last = min(estimate.count, reference.count - 88200 * 2)
        var dot = 0.0, power = 0.0, estimatePower = 0.0, error = 0.0, mixError = 0.0
        for n in first..<last {
            let e = Double(estimate[n]), r = Double(reference[n]), m = Double(mix[n])
            dot += e*r; power += r*r; estimatePower += e*e
            error += (e-r)*(e-r); mixError += (m-r)*(m-r)
        }
        let eps = 1e-12, projected = dot*dot/max(power,eps)
        return ["sdrDB": 10*log10(max(power,eps)/max(error,eps)),
                "siSDRDB": 10*log10(max(projected,eps)/max(estimatePower-projected,eps)),
                "inputSDRDB": 10*log10(max(power,eps)/max(mixError,eps)),
                "evaluationSeconds": Double(last-first)/88200]
    }
    static func main() async throws {
        guard CommandLine.arguments.count == 5 || CommandLine.arguments.count == 6 else { fatalError("corpus <model> <hashes.json> <corpus directory> <output directory> [hop-samples]") }
        let args = CommandLine.arguments, root = URL(fileURLWithPath: args[3]), out = URL(fileURLWithPath: args[4])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let separator = try await SGStemSeparator(modelURL: URL(fileURLWithPath: args[1]), payloadHashes: hashes)
        let size = separator.chunkSamples
        let hop = args.count == 6 ? Int(args[5])! : size * 3 / 4
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [String: Any]
        let tracks = manifest["tracks"] as! [[String: Any]]
        var reports: [[String: Any]] = []
        for (index, track) in tracks.enumerated() {
            let id = track["id"] as! String
            let mix = try read(root.appendingPathComponent(track["mix"] as! String))
            let reference = try read(root.appendingPathComponent(track["vocals"] as! String))
            guard mix.count == reference.count, mix.count > 6*44100 else { throw SGStemError.invalidInput }
            let clock = ContinuousClock(), started = clock.now
            var vocals: [Float] = []
            if size == 352800 {
                let count = mix.count/2
                guard count <= size else { throw SGStemError.invalidInput }
                var padded = mix
                for n in count..<size {
                    let reflected = max(0, 2*count-2-n)
                    padded.append(mix[reflected*2]); padded.append(mix[reflected*2+1])
                }
                vocals = Array(try await separator.vocals(for: padded).prefix(mix.count))
            } else {
                let worker = try SGStemWindowProcessor(chunkSamples: size, hopSamples: hop) { pcm in try await separator.vocals(for: pcm) }
                let generation = UInt64(index+1)
                await worker.reset(generation: generation, track: generation, format: 1)
                for at in stride(from: 0, through: mix.count/2-size, by: hop) {
                    let result = try await worker.process(Array(mix[at*2..<(at+size)*2]), sourceFrame: UInt64(at),
                        generation: generation, track: generation, format: 1)
                    vocals.append(contentsOf: result.vocals)
                }
            }
            guard vocals.count > 2*44100, vocals.allSatisfy(\.isFinite) else { throw SGStemError.invalidOutput }
            try vocals.withUnsafeBytes { try Data($0).write(to: out.appendingPathComponent(id + "-vocals.f32")) }
            let elapsed = clock.now - started
            var report: [String: Any] = score(vocals, reference, mix)
            report["id"] = id; report["track"] = track["track"]
            report["seconds"] = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds)/1e18
            reports.append(report)
            print(id, report["sdrDB"]!, report["siSDRDB"]!)
        }
        let result: [String: Any] = ["chunkSamples": size, "hopSamples": hop, "tracks": reports, "listeningValidated": false,
                                    "scope": "local fixture quality; not Spotify playback"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("report.json"))
    }
}
