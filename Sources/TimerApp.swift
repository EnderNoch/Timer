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
        .defaultLaunchBehavior(.presented)
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
        Model.shared.launch()
    }

    // Closing the window keeps the timer running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // A click on the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Model.shared.openMain?() }
        return true
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
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button(s.quit) { NSApp.terminate(nil) }
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
