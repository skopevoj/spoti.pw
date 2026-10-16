// Speed and pitch for Siri and the Shortcuts app (SpeedPitchPresets.h): the saved presets as App Entities,
// intents to use one, to set any speed and pitch and to put them back, and App Shortcuts, which are what
// lets Siri run them by voice with no setup ("Use Nightcore in Spotify").
//
// This file is compiled into the tweak, which is where an intent runs (in Spotify's process, in the
// background when Spotify is not open), and scripts/build-extension.sh hands it to the App Intents metadata
// processor as well, so Spotify's own Metadata.appintents lists it (scripts/merge-appintents.py). It has to
// stand alone: only AppIntents and Foundation. What an intent does is done by posting a notification the
// tweak acts on (SpeedPitchIntents.x); the presets are read straight from the defaults the tweak stores them
// in, as property lists, under the key and with the fields SpeedPitchPresets.h lists.
import AppIntents
import Foundation

let SGSpeedPitchIntentPresetNotification = Notification.Name("SGSpeedPitchIntentPreset")
let SGSpeedPitchIntentSetNotification = Notification.Name("SGSpeedPitchIntentSet")
let SGSpeedPitchIntentResetNotification = Notification.Name("SGSpeedPitchIntentReset")

private func sgStoredPresets() -> [SGSpeedPitchPresetEntity] {
    guard let list = UserDefaults.standard.array(forKey: "spotifyglass.speedPitch.presets") as? [[String: Any]] else { return [] }
    return list.compactMap { entry in
        guard let id = entry["id"] as? String, let name = entry["name"] as? String, !id.isEmpty, !name.isEmpty else { return nil }
        let speed = (entry["speed"] as? NSNumber)?.doubleValue ?? 1
        let pitch = (entry["pitch"] as? NSNumber)?.doubleValue ?? 0
        let follows = (entry["follows"] as? NSNumber)?.boolValue ?? false
        return SGSpeedPitchPresetEntity(id: id, name: name, summary: sgSpeedPitchSummary(speed: speed, pitch: pitch, follows: follows))
    }
}

private func sgSpeedPitchSummary(speed: Double, pitch: Double, follows: Bool) -> String {
    let speedText = String(format: "%.2f×", speed)
    if follows { return speed == 1 ? "Normal" : speedText + ", pitch follows" }
    if pitch == 0 { return speed == 1 ? "Normal" : speedText }
    return speedText + String(format: ", %+.0f st", pitch)
}

struct SGSpeedPitchPresetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Speed and pitch preset")
    static let defaultQuery = SGSpeedPitchPresetQuery()

    var id: String
    var name: String
    var summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }
}

// Siri matches what is said to the names, so this is a string query as well.
struct SGSpeedPitchPresetQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SGSpeedPitchPresetEntity] {
        sgStoredPresets().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SGSpeedPitchPresetEntity] {
        let wanted = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sgStoredPresets().filter { wanted.isEmpty || $0.name.lowercased().contains(wanted) }
    }

    func suggestedEntities() async throws -> [SGSpeedPitchPresetEntity] {
        sgStoredPresets()
    }
}

struct SGApplySpeedPitchPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Use speed and pitch preset"

    @Parameter(title: "Preset")
    var preset: SGSpeedPitchPresetEntity

    init() {}

    init(preset: SGSpeedPitchPresetEntity) {
        self.preset = preset
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: SGSpeedPitchIntentPresetNotification, object: preset.id)
        return .result(dialog: IntentDialog(stringLiteral: "\(preset.name): \(preset.summary)"))
    }
}

struct SGSetSpeedPitchIntent: AppIntent {
    static let title: LocalizedStringResource = "Set speed and pitch"

    @Parameter(title: "Speed (0.5 to 2)", default: 1.0)
    var speed: Double

    @Parameter(title: "Pitch in semitones (-12 to 12)", default: 0)
    var semitones: Int

    @Parameter(title: "Pitch follows speed", default: false)
    var follows: Bool

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: SGSpeedPitchIntentSetNotification, object: nil,
                                        userInfo: ["speed": speed, "pitch": Double(semitones), "follows": follows])
        return .result(dialog: IntentDialog(stringLiteral: sgSpeedPitchSummary(speed: speed, pitch: Double(semitones), follows: follows)))
    }
}

struct SGResetSpeedPitchIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset speed and pitch"

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: SGSpeedPitchIntentResetNotification, object: nil)
        return .result(dialog: IntentDialog(stringLiteral: "Normal speed and pitch"))
    }
}

// The phrases Siri answers to with no setup. Each has to name the app. The presets in the first are the
// ones the query offers, which the tweak tells Siri about again whenever they change.
struct SGSpeedPitchShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SGApplySpeedPitchPresetIntent(),
            phrases: [
                "Use \(\.$preset) in \(.applicationName)",
                "Set \(\.$preset) in \(.applicationName)",
                "Switch to \(\.$preset) in \(.applicationName)",
            ],
            shortTitle: "Use a preset",
            systemImageName: "slider.horizontal.3")
        AppShortcut(
            intent: SGResetSpeedPitchIntent(),
            phrases: [
                "Reset speed and pitch in \(.applicationName)",
                "Normal speed and pitch in \(.applicationName)",
            ],
            shortTitle: "Normal speed and pitch",
            systemImageName: "gauge.with.dots.needle.0percent")
    }
}
