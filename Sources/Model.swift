import SwiftUI
import ServiceManagement

/// The timer's whole state, saved in UserDefaults as soon as it changes.
@Observable
final class Model {
    static let shared = Model()

    enum Mode { case idle, running, paused, over }

    @ObservationIgnored private let ud = Background.defaults
    /// Opens the window; set by any view that has `openWindow`.
    @ObservationIgnored var openMain: (() -> Void)?

    /// Set time in seconds; what Start counts down from.
    var total: Int { didSet { ud.set(total, forKey: "total") } }
    /// Saved times, shortest first; saved with the button next to Start.
    var presets: [Int] { didSet { ud.set(presets, forKey: "presets") } }
    /// The alarm: a file name in the system's ringtones, as the Clock app picks its sounds.
    var tone: String { didSet { ud.set(tone, forKey: "tone") } }

    private(set) var mode = Mode.idle { didSet { saveRun() } }
    private(set) var muted = false { didSet { saveRun() } }
    /// A preview of the alarm is playing.
    private(set) var testing = false
    /// Ticks while counting down or over time; the views read the time from here.
    private(set) var now = Date()

    @ObservationIgnored private var endAt = Date()
    @ObservationIgnored private var pausedLeft: TimeInterval = 0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var player: NSSound?
    /// Ends a preview after a few seconds.
    @ObservationIgnored private var previewEnd: DispatchWorkItem?

    /// Accent from System Settings → Appearance → Color, as sRGB; nil for Multicolor,
    /// which keeps the timer's violet.
    private(set) var accent = Model.readAccent()

    /// The name in the system's language, from the bundle's localized Info.plist (build.sh).
    static let appName = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Timer"

    /// Last resort if a ringtone can't be opened.
    static let fallbackSound = URL(fileURLWithPath: "/System/Library/Sounds/Submarine.aiff")

    private init() {
        // integer(forKey:) also reads "-total 900" from the command line, which comes as text
        total = ud.object(forKey: "total") == nil ? 300 : ud.integer(forKey: "total")
        presets = ud.array(forKey: "presets") as? [Int] ?? []
        // Radar, the timer's sound in the Clock app on iPhone
        tone = ud.string(forKey: "tone") ?? "Radar.m4r"
        restoreRun()
    }

    /// A running timer is saved too, so the helper in the background (Background.swift) and
    /// the app opened again carry on with the same countdown.
    private func saveRun() {
        let name = switch mode { case .idle: "idle"; case .running: "running"; case .paused: "paused"; case .over: "over" }
        ud.set(name, forKey: "runMode")
        ud.set(endAt.timeIntervalSinceReferenceDate, forKey: "runEnd")
        ud.set(pausedLeft, forKey: "runPausedLeft")
        ud.set(muted, forKey: "runMuted")
    }

    /// Quitting for real ends the countdown; only the helper carries it on.
    func forgetRun() {
        ud.set("idle", forKey: "runMode")
    }

    private func restoreRun() {
        // Read before setting anything: every change saves the whole run again.
        let saved = ud.string(forKey: "runMode")
        endAt = Date(timeIntervalSinceReferenceDate: ud.double(forKey: "runEnd"))
        pausedLeft = ud.double(forKey: "runPausedLeft")
        muted = ud.bool(forKey: "runMuted")
        switch saved {
        case "running": mode = endAt > Date() ? .running : .over
        case "paused": mode = .paused
        case "over": mode = .over
        default: return
        }
        if mode != .paused { setTicking(true) }
        if mode == .over, !muted { play(loop: true) }
    }

    /// The system's language, as in any Mac app.
    var activeLang: String { Strings.detected }
    var s: Strings { Strings.for(activeLang) }

    // MARK: time

    /// Seconds left; negative over time.
    var left: TimeInterval {
        switch mode {
        case .idle: TimeInterval(total)
        case .paused: pausedLeft
        case .running, .over: endAt.timeIntervalSince(now)
        }
    }

    /// The ring is a kitchen timer's dial: one full turn is an hour, the arc is the time
    /// left (a full ring for more than an hour). Set, running or paused alike, so nothing
    /// jumps on Start.
    var fraction: Double {
        mode == .over ? 1 : max(0, min(1, left / 3600))
    }

    var stateText: String {
        switch mode {
        case .idle: s.ready
        case .running: s.running
        case .paused: s.paused
        case .over: s.overtime
        }
    }

    var mainTitle: String {
        switch mode {
        case .idle: s.start
        case .running: s.pause
        case .paused: s.resume
        case .over: s.stop
        }
    }

    /// Start, Pause, Resume or Stop, whichever fits.
    func main() {
        switch mode {
        case .idle: start()
        case .running:
            pausedLeft = left
            mode = .paused
            setTicking(false)
        case .paused:
            endAt = Date().addingTimeInterval(pausedLeft)
            mode = .running
            setTicking(true)
        case .over: reset()
        }
    }

    func start(_ seconds: Int? = nil) {
        if let seconds { total = seconds }
        guard total > 0 else { return }
        if mode != .idle { reset() }
        stopTest()
        endAt = Date().addingTimeInterval(TimeInterval(total))
        mode = .running
        setTicking(true)
    }

    func reset() {
        setTicking(false)
        stopSound()
        mode = .idle
        muted = false
    }

    func toggleMute() {
        muted.toggle()
        if muted { stopSound() } else if mode == .over { play(loop: true) }
    }

    private func setTicking(_ on: Bool) {
        ticker?.invalidate()
        ticker = nil
        now = Date()
        guard on else { return }
        // Ten times a second so the ring moves smoothly; nothing ticks while idle or paused.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { Model.shared.tick() }
        }
    }

    private func tick() {
        now = Date()
        if mode == .running, left <= 0 {
            mode = .over
            if !muted { play(loop: true) }
        }
    }

    // MARK: presets

    func savePreset() {
        guard total > 0, !presets.contains(total) else { return }
        presets = (presets + [total]).sorted()
    }

    func removePreset(_ seconds: Int) {
        presets.removeAll { $0 == seconds }
    }

    // MARK: sound

    var soundURL: URL { Tones.folder.appending(path: tone) }

    /// How long a preview plays: as long as the Apex ringtone, the length Witek chose.
    static let previewLength = NSSound(contentsOf: Tones.folder.appending(path: "Apex.m4r"), byReference: true)?
        .duration ?? 4.4

    /// Plays the first seconds of the chosen sound, as System Settings does when you pick one.
    func preview() {
        guard mode != .over else { return }
        play(loop: false)
        testing = player != nil
        let end = DispatchWorkItem { MainActor.assumeIsolated { Model.shared.stopTest() } }
        previewEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Model.previewLength, execute: end)
    }

    func stopTest() {
        guard testing else { return }
        testing = false
        stopSound()
    }

    private func play(loop: Bool) {
        stopSound()
        // A file NSSound can't open (e.g. FLAC) must not silence the alarm.
        let snd = NSSound(contentsOf: soundURL, byReference: true)
            ?? NSSound(contentsOf: Model.fallbackSound, byReference: true)
        snd?.loops = loop
        snd?.delegate = SoundEnd.shared
        snd?.play()
        player = snd
    }

    fileprivate func soundEnded(_ snd: NSSound) {
        guard snd === player else { return }
        player = nil
        testing = false
    }

    private func stopSound() {
        previewEnd?.cancel()
        previewEnd = nil
        player?.stop()
        player = nil
    }

    // MARK: system

    /// Hooks that need NSApp; called once the app has launched.
    func launch() {
        // Opens at login from the first launch. Only once: switching it off is System
        // Settings → General → Login Items' job, and a later launch mustn't undo that.
        if !Background.isHelper, !ud.bool(forKey: "loginSetUp") {
            try? SMAppService.mainApp.register()
            ud.set(true, forKey: "loginSetUp")
        }
        // System Settings writes these to the global domain; key-value observing hears the
        // write the moment it happens, so a new color arrives as fast as the system shows it.
        watcher = DefaultsWatcher(keys: ["AppleAccentColor", "AppleHighlightColor"]) {
            Model.shared.refreshAccent()
        }
        // AppKit may still hold the old accent at that instant; it says when it has the new one.
        NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { Model.shared.refreshAccent() } }
    }

    @ObservationIgnored private var watcher: DefaultsWatcher?

    private func refreshAccent() {
        let a = Model.readAccent()
        if a != accent { accent = a }
    }

    /// Multicolor leaves AppleAccentColor unset.
    private static func readAccent() -> SIMD3<Double>? {
        guard UserDefaults.standard.object(forKey: "AppleAccentColor") != nil,
              let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return nil }
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
    }
}

/// The system's ringtones - the sounds the Clock app offers - with their names in the
/// system's language, from the tone library's own localization tables.
enum Tones {
    static let library = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources")
    static let folder = library.appending(path: "Ringtones")

    struct Tone: Hashable {
        let file: String
        let name: String
    }

    /// All ringtones, sorted by name; one entry per name (Reflection comes in two).
    static func all(lang: String) -> [Tone] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var seen = Set<String>()
        return files.filter { $0.hasSuffix(".m4r") }
            .sorted { !$0.contains("-EncoreInfinitum") && $1.contains("-EncoreInfinitum") }
            .map { Tone(file: $0, name: name(of: $0, lang: lang)) }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func name(of file: String, lang: String) -> String {
        var base = String(file.dropLast(4))
        let encore = base.hasSuffix("-EncoreInfinitum")
        if encore { base.removeLast("-EncoreInfinitum".count) }
        let table = encore ? encoreTable : mainTable
        // The two default ringtones are named under their own keys.
        let keys = ["system:" + base] + (base == "Opening" ? ["RINGTONE_PICKER_DEFAULT_RINGTONE_NAME"]
            : base == "Reflection" ? ["RINGTONE_PICKER_DEFAULT_MODERN_RINGTONE_NAME"] : [])
        for code in [locKey(lang), "en"] {
            for k in keys {
                if let v = (table[code] as? [String: Any])?[k] as? String { return v }
            }
        }
        return base
    }

    /// Our language codes as the system's tables name them.
    private static func locKey(_ lang: String) -> String {
        ["zh-Hans": "zh_CN", "zh-Hant": "zh_TW", "nb": "no", "pt": "pt_PT"][lang] ?? lang
    }

    private static func load(_ name: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: library.appending(path: name)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    private static let mainTable = load("TL.loctable")
    private static let encoreTable = load("TL-EncoreInfinitum.loctable")
}

/// Tells the model when a sound has finished on its own.
final class SoundEnd: NSObject, NSSoundDelegate {
    static let shared = SoundEnd()

    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        MainActor.assumeIsolated { Model.shared.soundEnded(sound) }
    }
}

/// The system's positional format: "05:00", "15:00", "1:15:00" - seconds always there,
/// hours only when there are any. A minus over time.
func clock(_ t: TimeInterval) -> String {
    let neg = t < 0
    let sec = Int(neg ? (-t).rounded(.down) : t.rounded(.up))
    let f = DateComponentsFormatter()
    f.unitsStyle = .positional
    f.allowedUnits = sec >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    f.zeroFormattingBehavior = sec >= 3600 ? .dropLeading : .pad
    return (neg ? "-" : "") + (f.string(from: TimeInterval(sec)) ?? "")
}

/// Calls back on the main thread whenever one of the given defaults changes, in this
/// process or any other.
nonisolated final class DefaultsWatcher: NSObject {
    private let keys: [String]
    private let onChange: @MainActor () -> Void

    init(keys: [String], onChange: @escaping @MainActor () -> Void) {
        self.keys = keys
        self.onChange = onChange
        super.init()
        keys.forEach { UserDefaults.standard.addObserver(self, forKeyPath: $0, options: [], context: nil) }
    }

    deinit {
        keys.forEach { UserDefaults.standard.removeObserver(self, forKeyPath: $0) }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let onChange = onChange
        DispatchQueue.main.async { MainActor.assumeIsolated { onChange() } }
    }
}
