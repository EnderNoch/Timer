import AppKit

/// Golden Gate's Running in Background. When the user quits, the app quits for real, but a
/// helper it starts - the same program in `Contents/Helpers/Timer.app`, with no window and
/// no Dock icon - keeps the menu bar and the time going. The system shows exactly that state
/// as its own: the app stays in the Dock with a light gray dot, says "Running in Background"
/// on hover, offers Stop Running in Background in the icon's menu, and lists itself under
/// System Settings → General → Login Items → App Background Activity. A click on the icon
/// opens the app again, which stops the helper and carries on from where it was.
enum Background {
    static let mainID = "atyp.makers.timer.app"
    static let helperID = mainID + ".background"
    static let isHelper = Bundle.main.bundleIdentifier == helperID

    /// The app's settings and state, shared with the helper, whose own domain would be empty.
    static let defaults = isHelper ? UserDefaults(suiteName: mainID)! : .standard

    private static var mainURL: URL {
        isHelper
            ? Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            : Bundle.main.bundleURL
    }

    /// Main app, quitting: the helper takes over. It is started as a child, so the system
    /// counts it as the app's own and shows the app as running in the background.
    static func handOver() {
        defaults.set(false, forKey: "handingBack")
        defaults.synchronize()
        let helper = Process()
        helper.executableURL = mainURL.appending(path: "Contents/Helpers/Timer.app/Contents/MacOS/Timer")
        try? helper.run()
    }

    /// Main app, starting: a helper from before steps down; everything it knew is in the
    /// shared defaults.
    static func takeOver() {
        defaults.set(true, forKey: "handingBack")
        defaults.synchronize()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: helperID) {
            app.terminate()
        }
    }

    /// Helper: quitting because the app took over, not because the user ended it.
    static var handingBack: Bool { defaults.bool(forKey: "handingBack") }

    /// Helper: the window lives in the app, so opening it opens the app.
    static func openApp() {
        NSWorkspace.shared.openApplication(at: mainURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Helper: Stop Running in Background ends it with SIGTERM; quit the normal way so
    /// everything it holds is let go.
    static func quitOnSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source
    }

    private static var sigterm: DispatchSourceSignal?
}
