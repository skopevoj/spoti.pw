// Sing's worker (SGStemWorker.h): a task per playback generation that reads source packets from the C
// stream, runs whole windows through the separator, and hands each finished hop of vocals back. The loaded
// model outlives the task that loaded it by a minute, so a seek or the next song does not load it again.
import Foundation

public typealias StemRead = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<UInt64>?) -> Int32
public typealias StemWrite = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<Float>?, UInt32, UInt64, UInt64, UInt64, UInt32) -> Int32
public typealias StemStatus = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void

// SGStemWorker.h's SGStemLoading...SGStemFailed, and the stream's packet size (SGSingStreamPacketFrames).
private enum StemState: Int32 { case loading = 1, ready, finished, failed }
private let packetFrames = 1024
private let warmSeconds = 60                    // how long the model outlives the last worker using it
private let idlePoll = Duration.milliseconds(25) // how soon a worker with nothing to read looks again

// One warm model, shared by the workers that follow each other and kept for a while after the last
// one ends. A load in flight is shared too, and one made stale by a purge never becomes the warm model.
@available(iOS 27.0, macOS 27.0, *)
private actor SGStemModels {
    static let shared = SGStemModels()
    private var model: SGStemSeparator?
    private var path: String?
    private var loading: Task<SGStemSeparator, Error>?
    private var epoch: UInt64 = 0
    private var loadEpoch: UInt64 = 0
    private var users = 0

    func acquire(path: String) async throws -> SGStemSeparator {
        epoch &+= 1
        users += 1
        if self.path == path, let model { return model }
        if self.path != path { loading?.cancel(); loading = nil; model = nil }
        self.path = path
        if loading == nil {
            loadEpoch &+= 1
            loading = Task {
                let separator = try await SGStemSeparator(modelURL: URL(fileURLWithPath: path))
                try await separator.warmUp()
                try Task.checkCancellation()
                return separator
            }
        }
        let task = loading!
        let ticket = loadEpoch
        do {
            let value = try await task.value
            guard self.path == path, ticket == loadEpoch else { throw CancellationError() }
            model = value; loading = nil
            return value
        } catch {
            if ticket == loadEpoch { loading = nil }
            throw error
        }
    }
    func release(after seconds: Int) async {
        users -= 1
        guard users == 0 else { return }
        epoch &+= 1
        let ticket = epoch
        if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
        guard ticket == epoch else { return }
        purge()
    }
    func purge() {
        epoch &+= 1
        loadEpoch &+= 1
        loading?.cancel(); loading = nil; model = nil; path = nil
    }
}

// The C owner retains context until the final callback. Only this task invokes the endpoints;
// the render endpoint and the worker exchange PCM through the production SPSC queues.
@available(iOS 27.0, macOS 27.0, *)
private final class SGStemJob: @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    let read: StemRead, write: StemWrite, status: StemStatus
    private let lock = NSLock() // cancellation/control only, never an audio callback
    private var unload = false
    var task: Task<Void, Never>?

    init(context: UnsafeMutableRawPointer?, read: @escaping StemRead, write: @escaping StemWrite, status: @escaping StemStatus) {
        self.context = context; self.read = read; self.write = write; self.status = status
    }
    func cancel(unload: Bool) {
        lock.lock(); self.unload = self.unload || unload; lock.unlock()
        task?.cancel()
        if unload { Task { await SGStemModels.shared.purge() } }
    }
    private func retention() -> Int {
        lock.lock(); defer { lock.unlock() }
        return unload ? 0 : warmSeconds
    }
    private func report(_ value: StemState) { status(context, value.rawValue) }

    func run(path: String, window size: Int, hop: Int) async {
        report(.loading)
        do {
            let separator = try await SGStemModels.shared.acquire(path: path)
            try Task.checkCancellation()
            guard separator.windowFrames == size else { throw SGStemError.invalidModel }
            let worker = try SGStemWindowProcessor(chunkSamples: size, hopSamples: hop) { pcm in
                try await separator.vocals(for: pcm)
            }
            report(.ready)
            let overlap = size - hop
            var window = [Float](repeating: 0, count: size * 2), filled = 0
            var packet = [Float](repeating: 0, count: packetFrames * 2), packetCount = 0, packetOffset = 0
            var metadata = [UInt64](repeating: 0, count: 4), origin: [UInt64]?
            var received: UInt64 = 0, nextWindow: UInt64 = 0
            let clock = ContinuousClock()
            var windows = 0
            while !Task.isCancelled {
                if packetOffset == packetCount {
                    let count = read(context, &packet, &metadata)
                    if count < 0 { break }
                    if count == 0 { try await Task.sleep(for: idlePoll); continue }
                    guard count <= packetFrames else { throw SGStemError.invalidInput }
                    if origin == nil {
                        origin = metadata; received = metadata[2]; nextWindow = received
                        await worker.reset(generation: metadata[0], track: metadata[1], format: UInt32(metadata[3]))
                    }
                    guard metadata[0] == origin![0], metadata[1] == origin![1], metadata[3] == origin![3],
                          metadata[2] == received else { throw SGStemWindowError.outOfOrder }
                    received += UInt64(count)
                    packetCount = Int(count); packetOffset = 0
                }
                let count = min(size - filled, packetCount - packetOffset)
                for n in 0..<count * 2 { window[filled * 2 + n] = packet[packetOffset * 2 + n] }
                filled += count; packetOffset += count
                if filled == size, let origin {
                    let started = clock.now
                    let result = try await worker.process(window, sourceFrame: nextWindow,
                        generation: origin[0], track: origin[1], format: UInt32(origin[3]))
                    let elapsed = started.duration(to: clock.now).components
                    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                    if windows < 3 || windows % 20 == 0 || seconds > 0.5 {
                        NSLog("[spotifyglass] Sing inference %d: %.3f s, thermal %ld", windows, seconds,
                              ProcessInfo.processInfo.thermalState.rawValue)
                    }
                    windows += 1
                    try Task.checkCancellation()
                    let accepted = result.vocals.withUnsafeBufferPointer {
                        write(context, $0.baseAddress, UInt32(hop), result.generation, result.track, result.sourceFrame, result.format)
                    }
                    if accepted == 0 { break } // disabling during inference is an expected retirement
                    guard accepted > 0 else { throw SGStemError.invalidOutput }
                    for n in 0..<overlap * 2 { window[n] = window[hop * 2 + n] }
                    filled = overlap; nextWindow += UInt64(hop)
                }
            }
        } catch {
            if !Task.isCancelled {
                let failure = error as NSError
                NSLog("[spotifyglass] Sing worker failed: %@ (%ld), %@", failure.domain, failure.code,
                      String(describing: error))
                report(.failed)
            }
        }
        let seconds = retention()
        // Schedule retention independently: this task must release the stream/context now.
        Task { await SGStemModels.shared.release(after: seconds) }
        report(.finished)
    }
}

@_cdecl("SGStemWorkerStart")
public func sgStemWorkerStart(_ context: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>?, _ windowFrames: UInt32,
                              _ hopFrames: UInt32, _ read: StemRead?, _ write: StemWrite?, _ status: StemStatus?) -> UnsafeMutableRawPointer? {
    if #available(iOS 27.0, macOS 27.0, *), let path, let read, let write, let status {
        let job = SGStemJob(context: context, read: read, write: write, status: status)
        let modelPath = String(cString: path)
        job.task = Task.detached(priority: .userInitiated) {
            await job.run(path: modelPath, window: Int(windowFrames), hop: Int(hopFrames))
        }
        return Unmanaged.passRetained(job).toOpaque()
    }
    return nil
}

@_cdecl("SGStemWorkerCancel")
public func sgStemWorkerCancel(_ handle: UnsafeMutableRawPointer?, _ unload: Int32) {
    if #available(iOS 27.0, macOS 27.0, *), let handle {
        Unmanaged<SGStemJob>.fromOpaque(handle).takeRetainedValue().cancel(unload: unload != 0)
    }
}

@_cdecl("SGStemWorkerPurge")
public func sgStemWorkerPurge() {
    if #available(iOS 27.0, macOS 27.0, *) {
        Task { await SGStemModels.shared.purge() }
    }
}
