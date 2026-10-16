// The Live Activity's face, one of four views: the line being sung with the next one under it, the
// tracks up next, the player (the cover in a ring of the visualizer's bars, the controls and a bar a tap on
// which seeks there), or the control menu, a tab bar over Controls, Queue and Timer. A tap reaches the
// tweak as an intent and the new state takes over a second to render, so every on/off control is a
// Toggle, whose look the system flips the moment it is tapped, and what only changes after the render
// is marked invalidatable. iOS clips a lock screen Live Activity at 160 points, so every view is kept
// under it. Built with the tweak's LiveActivityShared.swift by scripts/build-extension.sh.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let green = Color(red: 0.12, green: 0.84, blue: 0.38)
private let idle = Color.white.opacity(0.08)

private typealias State = SGLyricsAttributes.ContentState

// The cover's colour, or the green the card had before; dim, for under the white text.
private func coverColour(_ state: State, dim: Bool) -> Color {
    guard state.tint >= 0 else { return dim ? Color.black.opacity(0.75) : green }
    let red = Double((state.tint >> 16) & 0xFF) / 255, greenPart = Double((state.tint >> 8) & 0xFF) / 255, blue = Double(state.tint & 0xFF) / 255
    let scale = dim ? 0.38 : 1
    return Color(red: red * scale, green: greenPart * scale, blue: blue * scale).opacity(dim ? 0.92 : 1)
}

// A thin bar under every view: running on its own while the track plays, standing still while paused.
private struct TrackProgress: View {
    let state: State
    var thin = true

    var body: some View {
        Group {
            if let start = state.trackStart, let end = state.trackEnd, end > start {
                ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: min(max(state.progress, 0), 1))
            }
        }
        .progressViewStyle(.linear)
        .tint(.white.opacity(0.85))
        .scaleEffect(x: 1, y: thin ? 0.6 : 1, anchor: .center)
    }
}
private typealias Tab = SGLyricsAttributes.Tab

@main
struct SGLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SGLyricsLiveActivity()
    }
}

extension SGLyricsAttributes.Tab {
    var symbol: String {
        switch self {
        case .controls: "slider.horizontal.3"
        case .queue: "list.bullet"
        case .timer: "moon.zzz"
        }
    }

    var title: String {
        switch self {
        case .controls: "Controls"
        case .queue: "Queue"
        case .timer: "Timer"
        }
    }
}

struct SGLyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SGLyricsAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                ContentView(state: context.state, upNext: context.state.translation.isEmpty ? 4 : 3)
                // The player view has a bar of its own to seek on.
                if context.state.view != .player {
                    TrackProgress(state: context.state)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, context.state.view == .panel ? 12 : 16)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .activityBackgroundTint(coverColour(context.state, dim: true))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "spotify:"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if context.state.view == .panel {
                            Summary(state: context.state)
                        } else if context.state.view == .player {
                            PlayerView(state: context.state, coverSize: 62)
                        } else {
                            ContentView(state: context.state, upNext: 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if context.state.view == .player, let cover = coverImage(context.state) {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(coverColour(context.state, dim: false))
                }
            } compactTrailing: {
                if let end = context.state.timerEnd, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(green)
                        .frame(maxWidth: 44)
                } else {
                    Image(systemName: context.state.paused ? "pause.fill" : "waveform")
                        .foregroundStyle(green)
                }
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(coverColour(context.state, dim: false))
            }
            .widgetURL(URL(string: "spotify:"))
        }
    }
}

private struct ContentView: View {
    let state: State
    let upNext: Int

    var body: some View {
        switch state.view {
        case .lyrics: LyricsView(state: state)
        case .queue: QueueView(state: state, upNext: upNext)
        case .panel: PanelView(state: state)
        case .player: PlayerView(state: state)
        }
    }
}

// MARK: - Player

// The bars as the app sends them, a hex digit a band, as 0...1; none when it sends none (paused, or the app in
// front, where the card is not seen).
private func levels(_ text: String?) -> [Double] {
    guard let text, !text.isEmpty else { return [] }
    return text.compactMap { $0.hexDigitValue }.map { Double($0) / 15 }
}

private func rgb(_ value: Int) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

// How light a 0xRRGGBB colour is, 0...1, as the app's ring weighs it (SGVisualizerLuminance).
private func luminance(_ value: Int) -> Double {
    0.2126 * Double((value >> 16) & 0xFF) / 255 + 0.7152 * Double((value >> 8) & 0xFF) / 255 + 0.0722 * Double(value & 0xFF) / 255
}

// The Backlight behind bars of these colours, as the app's ring picks it (SGVisualizerBacklightColour): white
// behind dark bars, black behind light ones. A cover's tint stands in when the colours are not known yet.
private func backlightColour(_ state: State) -> Color {
    let values = state.barColours ?? (state.tint >= 0 ? [state.tint] : [])
    let light = values.isEmpty ? 1 : values.map(luminance).reduce(0, +) / Double(values.count)
    return light < 0.45 ? Color.white.opacity(0.42) : Color.black.opacity(0.62)
}

// The cover: the app's file in the App Group when this extension may open the group, else the small picture
// carried in the state.
private func coverImage(_ state: State) -> UIImage? {
    if let group = state.coverGroup, let key = state.coverKey,
       let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
        let file = container.appendingPathComponent(SGLiveActivityCoverFolder).appendingPathComponent("cover-\(key).jpg")
        if let image = UIImage(contentsOfFile: file.path) { return image }
    }
    if let data = state.coverThumbnail, let image = UIImage(data: data) { return image }
    return nil
}

// The cover as a circle in a ring of bars, mirrored as the player's ring is by default, each bar going through
// the cover's colours from the inside out. A new state's bars glide to their new lengths.
private struct CoverRing: View {
    let state: State
    let size: CGFloat

    var body: some View {
        let heard = levels(state.bars)
        let bands = heard.isEmpty ? 24 : heard.count
        let count = bands * 2
        let inner = size * 0.33
        let reach = size * 0.155
        let width = max(1.5, size * 0.03)
        let colours = (state.barColours ?? []).map(rgb)
        let fill: AnyShapeStyle = colours.count > 1
            ? AnyShapeStyle(LinearGradient(colors: colours, startPoint: .bottom, endPoint: .top))
            : AnyShapeStyle(colours.first ?? coverColour(state, dim: false))
        ZStack {
            if state.backlight == true {
                let glow = backlightColour(state)
                let solid = (inner + 2 + reach * 0.6) / (size / 2)
                Circle()
                    .fill(RadialGradient(gradient: Gradient(stops: [
                        .init(color: glow, location: 0),
                        .init(color: glow, location: min(0.95, solid)),
                        .init(color: glow.opacity(0), location: 1),
                    ]), center: .center, startRadius: 0, endRadius: size / 2))
                    .frame(width: size, height: size)
            }
            ForEach(0..<count, id: \.self) { index in
                let band = index < bands ? index : count - 1 - index
                let level = band < heard.count ? heard[band] : 0
                let length = width + reach * level
                Capsule()
                    .fill(fill)
                    .frame(width: width, height: length)
                    .offset(y: -(inner + 2 + length / 2))
                    .rotationEffect(.degrees((Double(index) + 0.5) * 360 / Double(count)))
            }
            Group {
                if let cover = coverImage(state) {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(coverColour(state, dim: false))
                        Image(systemName: "music.note").foregroundStyle(.white)
                    }
                }
            }
            .frame(width: inner * 2, height: inner * 2)
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.45), value: state.bars)
    }
}

private func clock(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", whole / 60, whole % 60)
}

// The bar, with the time in and the time left, cut into stretches each a button: a tap on one seeks to the
// middle of it.
private struct SeekBar: View {
    let state: State
    private let stretches = 24

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                TrackProgress(state: state, thin: false)
                HStack(spacing: 0) {
                    ForEach(0..<stretches, id: \.self) { index in
                        Button(intent: SGLiveActivityActionIntent(String(format: "seek:%.3f", (Double(index) + 0.5) / Double(stretches)))) {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 22)
            HStack {
                if let start = state.trackStart, let end = state.trackEnd, end > start {
                    Text(timerInterval: start...end, countsDown: false)
                    Spacer(minLength: 0)
                    Text(timerInterval: start...end, countsDown: true)
                } else if let duration = state.duration {
                    Text(clock(duration * state.progress))
                    Spacer(minLength: 0)
                    Text("-" + clock(duration * (1 - state.progress)))
                }
            }
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct SmallChip: View {
    let symbol: String
    var lit = false

    var body: some View {
        Image(systemName: symbol)
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? green.opacity(0.22) : idle))
            .foregroundStyle(lit ? green : .white)
    }
}

private struct SmallToggleStyle: ToggleStyle {
    let symbol: String
    let onSymbol: String
    var lights = false

    func makeBody(configuration: Configuration) -> some View {
        SmallChip(symbol: configuration.isOn ? onSymbol : symbol, lit: lights && configuration.isOn)
    }
}

private struct PlayerView: View {
    let state: State
    var coverSize: CGFloat = 76

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                CoverRing(state: state, size: coverSize)
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.title)
                            .font(.subheadline.weight(.semibold))
                        Text(state.artist)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    .invalidatableContent()
                    HStack(spacing: 6) {
                        Button(intent: SGLiveActivityActionIntent("previous")) { SmallChip(symbol: "backward.fill") }
                            .buttonStyle(.plain)
                        Toggle(isOn: !state.paused, intent: SGLiveActivityActionIntent("toggle")) { EmptyView() }
                            .toggleStyle(SmallToggleStyle(symbol: "play.fill", onSymbol: "pause.fill"))
                        Button(intent: SGLiveActivityActionIntent("next")) { SmallChip(symbol: "forward.fill") }
                            .buttonStyle(.plain)
                        Toggle(isOn: state.liked, intent: SGLiveActivityActionIntent("like")) { EmptyView() }
                            .toggleStyle(SmallToggleStyle(symbol: "heart", onSymbol: "heart.fill", lights: true))
                    }
                }
            }
            SeekBar(state: state)
        }
    }
}

// MARK: - Lyrics and queue

private struct LyricsView: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.line)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .direction(of: state.line)
            if !state.translation.isEmpty {
                Text(state.translation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .direction(of: state.translation)
            }
            if !state.nextLine.isEmpty && state.translation.isEmpty {
                Text(state.nextLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .direction(of: state.nextLine)
            }
        }
    }
}

// Whether a line is written right to left, told by its first letter the way the Unicode bidi algorithm
// tells a paragraph's direction. Each line is asked on its own, since a song can mix scripts, and the
// phone's language has no say in it. The tweak's lyrics page asks the same (SGRKaraokeView.m).
private func readsRightToLeft(_ text: String) -> Bool {
    guard let first = text.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return false }
    switch first.value {
    case 0x0590...0x08FF,      // Hebrew, Arabic, Syriac, Thaana, N'Ko and on
         0xFB1D...0xFDFF,      // Hebrew and Arabic presentation forms
         0xFE70...0xFEFF,      // Arabic presentation forms B
         0x10800...0x10FFF,    // the old scripts written right to left
         0x1E800...0x1EFFF:    // Mende Kikakui and Adlam
        return true
    default:
        return false
    }
}

private extension View {
    // A line written right to left is laid out right to left, against the right edge; any other is left
    // the way it was.
    @ViewBuilder func direction(of line: String) -> some View {
        if readsRightToLeft(line) {
            frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            self
        }
    }
}

private struct QueueView: View {
    let state: State
    let upNext: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Up next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            if state.tracks.isEmpty {
                Text("Nothing up next")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(Array(state.tracks.prefix(upNext).enumerated()), id: \.offset) { _, track in
                // A tap skips ahead to the track.
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    (Text(track.title).fontWeight(.semibold) + Text("  " + track.artist).foregroundColor(.white.opacity(0.5)))
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Control menu

// The expanded Dynamic Island has room for one line of the menu.
private struct Summary: View {
    let state: State

    var body: some View {
        Group {
            switch state.tab {
            case .controls:
                Text("\(state.title) · \(state.artist)")
            case .queue:
                Text(state.tracks.first.map { "Next: \($0.title)" } ?? "Nothing up next")
            case .timer:
                if let end = state.timerEnd, end > Date() {
                    Text("Music stops in \(Text(timerInterval: Date()...end, countsDown: true))")
                } else if state.timerEndOfTrack {
                    Text("Music stops at the end of this track")
                } else {
                    Text("No sleep timer")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .invalidatableContent()
    }
}

private struct PanelView: View {
    let state: State

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Toggle(isOn: tab == state.tab, intent: SGLiveActivityActionIntent("tab:\(tab.rawValue)")) {
                        EmptyView()
                    }
                    .toggleStyle(TabStyle(tab: tab))
                }
            }
            Group {
                switch state.tab {
                case .controls: ControlsPage(state: state)
                case .queue: QueuePage(state: state)
                case .timer: TimerPage(state: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TabStyle: ToggleStyle {
    let tab: Tab

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tab.symbol)
            if configuration.isOn {
                Text(tab.title)
            }
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(Capsule().fill(configuration.isOn ? green.opacity(0.22) : idle))
        .foregroundStyle(configuration.isOn ? green : .white.opacity(0.7))
    }
}

private struct ChipLabel: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}

private struct ChipStyle: ToggleStyle {
    let symbol: String
    var onSymbol: String?
    let label: String
    var onLabel: String?
    // Play and pause flips its symbol but is not a setting, so it keeps the idle fill either way.
    var lights = true

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        ChipLabel(symbol: on ? onSymbol ?? symbol : symbol, label: on ? onLabel ?? label : label)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on && lights ? green.opacity(0.22) : idle))
            .foregroundStyle(on && lights ? green : .white)
    }
}

private struct ChipButton: View {
    let action: String
    let symbol: String
    let label: String
    var lit = false

    var body: some View {
        Button(intent: SGLiveActivityActionIntent(action)) {
            ChipLabel(symbol: symbol, label: label)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lit ? green.opacity(0.22) : idle))
                .foregroundStyle(lit ? green : .white)
        }
        .buttonStyle(.plain)
    }
}

private struct ControlsPage: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                Text(state.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .invalidatableContent()
            HStack(spacing: 6) {
                // Dislike skips the track (and takes it out of Liked Songs if the card put it there).
                ChipButton(action: "dislike", symbol: "hand.thumbsdown", label: "Dislike")
                ChipButton(action: "previous", symbol: "backward.fill", label: "Previous")
                Toggle(isOn: !state.paused, intent: SGLiveActivityActionIntent("toggle")) { EmptyView() }
                    .toggleStyle(ChipStyle(symbol: "play.fill", onSymbol: "pause.fill", label: "Play", onLabel: "Pause", lights: false))
                ChipButton(action: "next", symbol: "forward.fill", label: "Next")
                Toggle(isOn: state.liked, intent: SGLiveActivityActionIntent("like")) { EmptyView() }
                    .toggleStyle(ChipStyle(symbol: "heart", onSymbol: "heart.fill", label: "Like", onLabel: "Liked"))
                Toggle(isOn: state.shuffle, intent: SGLiveActivityActionIntent("shuffle")) { EmptyView() }
                    .toggleStyle(ChipStyle(symbol: "shuffle", label: "Shuffle"))
                // Three states, so a button: the new one shows once the render lands.
                ChipButton(action: "repeat", symbol: state.repeatMode == 2 ? "repeat.1" : "repeat",
                           label: "Repeat", lit: state.repeatMode != 0)
                    .invalidatableContent()
            }
        }
    }
}

private struct QueuePage: View {
    let state: State

    var body: some View {
        VStack(spacing: 4) {
            if state.tracks.isEmpty {
                Text("Nothing up next")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(Array(state.tracks.prefix(3).enumerated()), id: \.offset) { _, track in
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(green)
                        Text(track.title)
                            .font(.footnote.weight(.semibold))
                        Text(track.artist)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(idle))
                }
                .buttonStyle(.plain)
            }
        }
        .invalidatableContent()
    }
}

private struct TimerPage: View {
    let state: State

    var body: some View {
        Group {
            if (state.timerEnd.map { $0 > Date() } ?? false) || state.timerEndOfTrack {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Music stops")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        if let end = state.timerEnd {
                            Text(timerInterval: Date()...end, countsDown: true)
                                .font(.system(size: 34, weight: .bold).monospacedDigit())
                                .foregroundStyle(green)
                        } else {
                            Text("End of track")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(green)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        if state.timerEnd != nil {
                            ChipButton(action: "timer:add", symbol: "plus", label: "15 min")
                        }
                        ChipButton(action: "timer:cancel", symbol: "xmark", label: "Cancel")
                    }
                    .frame(width: state.timerEnd != nil ? 140 : 66)
                }
            } else {
                HStack(spacing: 8) {
                    ChipButton(action: "timer:15", symbol: "moon", label: "15 min")
                    ChipButton(action: "timer:30", symbol: "moon", label: "30 min")
                    ChipButton(action: "timer:60", symbol: "moon", label: "1 hour")
                    ChipButton(action: "timer:track", symbol: "music.note", label: "End of track")
                }
            }
        }
        .invalidatableContent()
    }
}
