// The App Shortcuts' parameters are the presets, which Siri has to be told about again when they change
// (SpeedPitchIntents.swift); AppIntents is Swift only, so SpeedPitchIntents.x reaches that through this class.
import AppIntents
import Foundation

@objc(SGSpeedPitchShortcutsBridge)
public final class SGSpeedPitchShortcutsBridge: NSObject {
    @objc public static func refresh() {
        SGSpeedPitchShortcuts.updateAppShortcutParameters()
    }
}
