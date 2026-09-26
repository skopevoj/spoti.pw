// Standalone model measurements on iPhone. This does not run Spotify or validate live audio.
import UIKit
#if canImport(CoreAI)
import CoreAI
#endif
import Darwin
import os

@main
@MainActor final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Benchmark", sessionRole: session.role)
        config.delegateClass = Scene.self
        return config
    }
}
@MainActor final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var statusLabel: UILabel?
    private var started = false
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        let controller = UIViewController()
        let label = UILabel()
        label.numberOfLines = 0
        label.text = "Sing model benchmark\nPreparing local model…"
        label.textAlignment = .center
        label.frame = window.bounds.insetBy(dx: 24, dy: 80)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(label)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        statusLabel = label
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !started, let label = statusLabel else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                do { return try await Benchmark.run() }
                catch { return "FAILED: \(error)" }
            }.value
            label.text = result
            NSLog("SING_DEVICE_RESULT %@", result)
            try? result.write(to: URL.documentsDirectory.appendingPathComponent("result.json"), atomically: true, encoding: .utf8)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
enum Benchmark {
    static func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
    static func floats(_ path: URL) throws -> [Float] {
        let data = try Data(contentsOf: path)
        return data.withUnsafeBytes { p in
            stride(from: 0, to: p.count, by: 4).map { p.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
    }
    static func run() async throws -> String {
        for name in ["result.json", "progress.json"] {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(name))
        }
        if UserDefaults.standard.bool(forKey: "waitForCool") {
            let clock = ContinuousClock(), deadline = clock.now + .seconds(600)
            while ProcessInfo.processInfo.thermalState != .nominal && clock.now < deadline {
                let active = await MainActor.run { UIApplication.shared.applicationState == .active }
                guard active else { return "Cooling interrupted: app left the foreground." }
                let progress: [String: Any] = ["status": "cooling", "thermalState": ProcessInfo.processInfo.thermalState.rawValue]
                try JSONSerialization.data(withJSONObject: progress).write(to: URL.documentsDirectory.appendingPathComponent("progress.json"), options: .atomic)
                try await Task.sleep(for: .seconds(5))
            }
            guard ProcessInfo.processInfo.thermalState == .nominal else { return "Thermal hold: did not reach Nominal within ten minutes." }
        }
        let initialThermal = ProcessInfo.processInfo.thermalState.rawValue
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard initialThermal < 2 else { return "Thermal hold: device is already Serious or Critical before loading the model." }
        let root = Bundle.main.bundleURL.appendingPathComponent("Assets")
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("hashes.json")))
        let cpu = FileManager.default.fileExists(atPath: root.appendingPathComponent("separator.mlmodelc").path)
        let modelURL = root.appendingPathComponent(cpu ? "separator.mlmodelc" : "separator.aimodelc")
        let sourceHash = hashes[cpu ? "model.mil" : "main.hash"] ?? "unknown"
        let requestedHop = UserDefaults.standard.object(forKey: "hopSeconds") == nil ? 1.5 : UserDefaults.standard.double(forKey: "hopSeconds")
        guard requestedHop.isFinite, requestedHop >= 0.5, requestedHop <= 2 else { throw SGStemError.invalidInput }
        let clock = ContinuousClock(), start = clock.now
        let preferForegroundGPU = cpu && UserDefaults.standard.bool(forKey: "foregroundGPU")
        let backend = cpu ? (preferForegroundGPU ? "CoreMLAdaptive" : "CoreMLCPU") : "CoreAI"
        let separator = try await SGStemSeparator(modelURL: modelURL, payloadHashes: hashes,
            preferForegroundGPU: preferForegroundGPU)
        let load = seconds(clock.now - start)
        let minimumMemoryBefore = os_proc_available_memory()
        var minimumMemory = minimumMemoryBefore
        let count = separator.chunkSamples
        let raw = try floats(root.appendingPathComponent("golden_raw.f32"))
        let reference = try floats(root.appendingPathComponent("golden_vocals.f32"))
        guard raw.count == count * 2, reference.count == raw.count else { throw SGStemError.invalidInput }
        var pcm = [Float](repeating: 0, count: raw.count)
        for i in 0..<count { pcm[i*2] = raw[i]; pcm[i*2+1] = raw[count+i] }
        var times: [Double] = [], cosine = 0.0, rms = 0.0
        var status = "running", missedDeadlines = 0
        let started = clock.now
        var nextReport = 10
        let requested = UserDefaults.standard.integer(forKey: "duration")
        let windows = requested > 0 ? Int(Double(min(requested, 1800)) / requestedHop) + 1 : 8
        for i in 0..<windows {
            if i > 0 { try await Task.sleep(for: .seconds(max(0, Double(i) * requestedHop - seconds(clock.now - started)))) }
            guard ProcessInfo.processInfo.thermalState.rawValue < 2 else { status = "thermal-stop"; break }
            let active = await MainActor.run { UIApplication.shared.applicationState == .active }
            guard active else { status = "inactive-stop"; break }
            let start = clock.now
            let vocals = try await separator.vocals(for: pcm)
            times.append(seconds(clock.now - start))
            minimumMemory = min(minimumMemory, os_proc_available_memory())
            if i > 0 && seconds(clock.now - started) > Double(i + 1) * requestedHop { missedDeadlines += 1 }
            var aa = 0.0, bb = 0.0, dot = 0.0
            for n in 0..<count {
                for c in 0..<2 {
                    let a = Double(vocals[n*2+c]), b = Double(reference[c*count+n])
                    aa += a*a; bb += b*b; dot += a*b
                }
            }
            cosine = dot/sqrt(aa*bb); rms = sqrt(aa/bb)
            guard cosine >= 0.999, abs(rms-1) < 0.01 else { throw SGStemError.invalidOutput }
            NSLog("SING_DEVICE run %d: %.3fs cosine %.7f", i, times.last!, cosine)
            if i >= nextReport {
                let progress: [String: Any] = ["status": status, "completedWindows": i + 1,
                    "hopSeconds": requestedHop, "modelSourceHash": sourceHash, "backend": backend,
                    "elapsedSeconds": seconds(clock.now - started), "lastInferenceSeconds": times.last!,
                    "worstWarmInferenceSeconds": times.dropFirst().max()!, "missedHopDeadlines": missedDeadlines,
                    "minimumAvailableMemoryBytes": minimumMemory,
                    "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                    "initialThermalState": initialThermal, "scope": "model-only; not Spotify playback", "liveValidated": false]
                let data = try JSONSerialization.data(withJSONObject: progress, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL.documentsDirectory.appendingPathComponent("progress.json"), options: .atomic)
                nextReport += 10
            }
            if i == windows - 1 { status = "complete" }
        }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        #if canImport(CoreAI)
        let architecture = AIModel.deviceArchitectureName
        #else
        let architecture = "unavailable"
        #endif
        #if targetEnvironment(simulator)
        let platform = "iOS Simulator"
        #else
        let platform = "iOS device"
        #endif
        let report: [String: Any] = ["architecture": architecture, "platform": platform,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "hopSeconds": requestedHop, "modelSourceHash": sourceHash, "backend": backend,
            "status": status, "scope": "model-only; not Spotify playback", "completedWindows": times.count,
            "elapsedSeconds": seconds(clock.now - started), "missedHopDeadlines": missedDeadlines,
            "minimumAvailableMemoryBytes": minimumMemory,
            "chunkSamples": count, "loadSeconds": load, "inferenceSeconds": times, "cosine": cosine, "rmsRatio": rms,
            "peakResidentBytes": usage.ru_maxrss, "initialThermalState": initialThermal,
            "lowPowerMode": lowPower, "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "causalActivationLowerBoundSeconds": Double(count)/44100 + (times.dropFirst().max() ?? 0), "liveValidated": false]
        return String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
    }
}
