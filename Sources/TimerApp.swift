import SwiftUI

@main
struct TimerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private let m = Model.shared

    var body: some Scene {
        Window(Text(Model.appName), id: "main") {
            TimerView()
                .windowFullScreenBehavior(.disabled)
        }
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 460, height: 820)
        // The helper that runs in the background has no window of its own.
        .defaultLaunchBehavior(Background.isHelper ? .suppressed : .presented)
        // The app menu as in Photo Booth: About, Hide, Hide Others, Show All, Quit -
        // without Services, which a timer has nothing to offer to.
        .commands { CommandGroup(replacing: .systemServices) {} }

        // Always there; hiding it is System Settings → Menu Bar's job, and it keeps its place.
        MenuBarExtra {
            MenuPanel()
        } label: {
            // The time while it runs, the timer symbol while idle. The label says the name and
            // the state, like the system's own menu bar items ("Wi-Fi, connected"); without it
            // the system reads the symbol's name.
            if m.mode == .idle {
                Image(systemName: "timer")
                    .accessibilityLabel(Model.appName)
            } else {
                Text(clock(m.left)).monospacedDigit()
                    .accessibilityLabel("\(Model.appName), \(clock(m.left)), \(m.stateText)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Background.isHelper {
            Background.quitOnSignal()
        } else {
            Background.takeOver()
            // Opening the app opens its window, also when it was closed at the last quit.
            DispatchQueue.main.async { self.showWindow() }
        }
        Model.shared.launch()
    }

    /// The panel's Quit, which ends the timer too, not just the window.
    static var quitNow = false

    // Quit from the Dock or with ⌘Q: the helper carries on in the background (Background.swift).
    // Not from the panel, nor at logout, restart or shutdown, which put 'why?' on the quit
    // event; those end the timer, and so does Stop Running in Background.
    func applicationWillTerminate(_ notification: Notification) {
        let why = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: 0x7768_793F)
        if Background.isHelper {
            if !Background.handingBack { Model.shared.forgetRun() }
        } else if !Self.quitNow, why == nil {
            Background.handOver()
        } else {
            Model.shared.forgetRun()
        }
    }

    // Closing the window keeps the timer running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // A click on the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    private func showWindow() {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        // The Window menu's own item for the window, as clicking it would: SwiftUI's openWindow
        // does nothing when the app was launched without showing it.
        if let menu = NSApp.windowsMenu,
           let i = menu.items.firstIndex(where: { $0.title == Model.appName }) {
            menu.performActionForItem(at: i)
        } else {
            Model.shared.openMain?()
        }
    }
}

/// The menu bar panel, like Control Center's: the time with a small ring, Cancel and
/// Start, the saved times while idle, and a way back to the window.
struct MenuPanel: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.palette) private var p
    private let m = Model.shared

    var body: some View {
        let s = m.s
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(p.track, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: m.fraction)
                        .stroke(m.mode == .over ? .red : m.mode == .paused ? p.paused : p.ring,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clock(m.left))
                        .font(.system(.title, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(m.mode == .over ? .red : .primary)
                    Text(m.stateText).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if m.mode == .over {
                    Button { m.toggleMute() } label: {
                        Image(systemName: m.muted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .buttonStyle(.glass)
                    .help(m.muted ? s.unmute : s.mute)
                }
            }

            HStack(spacing: 10) {
                Button { m.reset() } label: { Text(s.cancel).frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .disabled(m.mode == .idle)
                Button { m.main() } label: {
                    Text(m.mainTitle)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(p.onTint)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
            }
            .controlSize(.large)

            if m.mode == .idle && !m.presets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(m.presets.prefix(6), id: \.self) { sec in
                            Button { m.start(sec) } label: {
                                Text(clock(TimeInterval(sec))).monospacedDigit().frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Button(s.open) {
                    if Background.isHelper {
                        Background.openApp()
                    } else {
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                }
                Spacer()
                Button(s.quit) {
                    AppDelegate.quitNow = true
                    NSApp.terminate(nil)
                }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
        .modifier(Themed())
        .onAppear { m.openMain = { openWindow(id: "main") } }
    }
}
