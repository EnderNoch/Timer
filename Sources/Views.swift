import SwiftUI

/// Colors worked out from the system accent; Multicolor keeps the timer's violet.
struct Palette {
    var ring: Color
    var paused: Color
    var icon: Color
    var track: Color
    /// Text on a button filled with `ring`: dark on a light accent (yellow), white otherwise.
    var onTint: Color

    init(accent: SIMD3<Double>?, dark: Bool) {
        let white = SIMD3<Double>(1, 1, 1), black = SIMD3<Double>(0, 0, 0)
        let a = accent ?? (dark ? [0x7A, 0x45, 0xC9] / 255 : [0x6B, 0x4F, 0xBF] / 255)
        let ring = dark ? a + (white - a) * 0.25 : a + (black - a) * 0.12
        let paused = dark ? a + (black - a) * 0.2 : a + (white - a) * 0.35
        let icon = dark ? a + (white - a) * 0.55 : a + (black - a) * 0.1
        self.ring = Color(red: ring.x, green: ring.y, blue: ring.z)
        self.paused = Color(red: paused.x, green: paused.y, blue: paused.z)
        self.icon = Color(red: icon.x, green: icon.y, blue: icon.z)
        track = dark ? .white.opacity(0.16) : Color(red: 60 / 255, green: 40 / 255, blue: 100 / 255).opacity(0.16)
        let luma = 0.2126 * ring.x + 0.7152 * ring.y + 0.0722 * ring.z
        onTint = luma > 0.62 ? Color(red: 0x1B / 255, green: 0x15 / 255, blue: 0x26 / 255) : .white
    }
}

extension EnvironmentValues {
    @Entry var palette = Palette(accent: nil, dark: true)
}

/// Palette, accent tint, language and reading direction for everything below.
struct Themed: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let m = Model.shared
        let p = Palette(accent: m.accent, dark: scheme == .dark)
        content
            .environment(\.palette, p)
            .tint(p.ring)
            .environment(\.locale, Locale(identifier: m.activeLang))
            .environment(\.layoutDirection, Strings.rtl.contains(m.activeLang) ? .rightToLeft : .leftToRight)
    }
}

/// The window, laid out like Screen Light: the dial on top growing with the window, the two
/// buttons under it, then one glass pane per section reaching the margins, rows split by
/// thin lines, an icon leading each row.
struct TimerView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable private var m = Model.shared

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { g in
                Dial(size: min(g.size.width, g.size.height))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 200)

            MainButtons().controlSize(.extraLarge)

            Pane {
                // The speaker says what the row is, as the palette does in Screen Light.
                Row(icon: "speaker.wave.2.fill") {
                    Spacer()
                    SoundPicker()
                }
            }

            if !m.presets.isEmpty {
                Presets()
            }
        }
        .padding(20)
        // Bounds like System Settings: one vertical layout, no full screen.
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 560, minHeight: 750, idealHeight: 820, maxHeight: 1100)
        .background { WindowGlass().ignoresSafeArea() }
        .modifier(Themed())
        .onAppear { m.openMain = { openWindow(id: "main") } }
    }
}

/// The countdown as Screen Light's dial: a glass disc, a tinted glass lens in the middle
/// with the time, the arc is the time left on a kitchen timer's face - one turn is an hour -
/// with a knob at its end. While idle, drag the knob around the ring to set whole minutes,
/// or click the time and type it.
struct Dial: View {
    let size: CGFloat
    @Environment(\.palette) private var p
    private let m = Model.shared
    /// A drag in progress: the time it started from, the knob's angle at the previous step
    /// (in turns) and how many turns it has gone since; nil when not dragging.
    @State private var dragFrom: (total: Int, last: Double, turns: Double)?

    var body: some View {
        let line = max(8, size * 0.04)
        let color: Color = m.mode == .over ? .red : m.mode == .paused ? p.paused : p.ring
        let font = Font.system(size: size * 0.14, weight: .medium, design: .rounded)
        ZStack {
            Color.clear.glassEffect(.regular, in: .circle)
            Color.clear
                .glassEffect(.regular.tint(color.opacity(0.35)), in: .circle)
                .padding(line * 3)
                .shadow(color: color.opacity(0.35), radius: size * 0.06)
            Circle().inset(by: line).stroke(p.track, lineWidth: line)
            Circle()
                .inset(by: line)
                .trim(from: 0, to: m.fraction)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 8)
            // Knob at the end of the arc, like a slider's, so the ring reads as something to grab.
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .frame(width: line * 1.9, height: line * 1.9)
                .offset(y: -(size / 2 - line))
                .rotationEffect(.degrees(m.fraction * 360))
            if m.mode == .idle {
                // Only the band of the ring takes drags; the middle stays the time field.
                Annulus(inner: size / 2 - line * 2.5)
                    .fill(Color.clear)
                    .contentShape(Annulus(inner: size / 2 - line * 2.5), eoFill: true)
                    .pointerStyle(dragFrom == nil ? .grabIdle : .grabActive)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged(drag)
                        .onEnded { _ in dragFrom = nil })
            }
            VStack(spacing: size * 0.015) {
                if m.mode == .idle {
                    TimeEntry(font: font)
                } else {
                    Text(clock(m.left))
                        .font(font)
                        .monospacedDigit()
                        .foregroundStyle(m.mode == .over ? .red : .primary)
                }
                Text(m.stateText)
                    .font(.system(size: size * 0.05))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    /// Turning the knob adds or takes away minutes from the time that was set - hours and
    /// seconds typed in stay - one turn being an hour. A click alone changes nothing.
    private func drag(_ v: DragGesture.Value) {
        let dx = v.location.x - size / 2, dy = v.location.y - size / 2
        var turn = atan2(dx, -dy) / (2 * .pi)
        if turn < 0 { turn += 1 }
        guard var d = dragFrom else {
            dragFrom = (m.total, turn, 0)
            return
        }
        // Crossing the top shows up as a jump of almost a whole turn; it's a small step.
        var step = turn - d.last
        if step > 0.5 { step -= 1 }
        if step < -0.5 { step += 1 }
        d.turns += step
        d.last = turn
        dragFrom = d
        let minutes = Int((d.turns * 60).rounded())
        m.total = min(max(d.total + minutes * 60, 0), 99 * 3600 + 59 * 60 + 59)
    }
}

/// A ring: the circle minus a hole of radius `inner` in the middle.
struct Annulus: Shape {
    let inner: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(ellipseIn: rect)
        p.addEllipse(in: rect.insetBy(dx: rect.width / 2 - inner, dy: rect.height / 2 - inner))
        return p
    }
}

/// Hours, minutes and seconds with fixed colons. Only digits get in: they come in from the
/// right, like on a microwave - 1, 5, 0, 0 is 00:15:00. Delete takes the last one back,
/// Return or Esc ends. The first digit after a click starts over from zero.
struct TimeEntry: View {
    let font: Font
    @Environment(\.palette) private var p
    private let m = Model.shared
    @FocusState private var typing: Bool
    /// Up to six digits, hhmmss, while typing.
    @State private var digits = ""
    @State private var fresh = true

    var body: some View {
        let shown = typing ? String(repeating: "0", count: 6 - digits.count) + digits : Self.digits(m.total)
        let chars = Array(shown)
        Text("\(String(chars[0...1])):\(String(chars[2...3])):\(String(chars[4...5]))")
            .font(font)
            .monospacedDigit()
            .foregroundStyle(typing ? AnyShapeStyle(p.ring) : AnyShapeStyle(.foreground))
            .padding(.horizontal, 12)
            .background {
                if typing {
                    RoundedRectangle(cornerRadius: 12).fill(p.ring.opacity(0.12))
                }
            }
            .contentShape(.rect)
            .focusable(interactions: .edit)
            .focused($typing)
            .focusEffectDisabled()
            .onTapGesture { typing = true }
            .pointerStyle(.horizontalText)
            .onChange(of: typing) {
                fresh = true
                digits = ""
            }
            // Backspace reaches a focused view as the system's delete command, not as a key.
            .onDeleteCommand { backspace() }
            .onKeyPress(phases: .down) { press in
                switch press.key {
                case .return, .escape:
                    typing = false
                    return .handled
                case .delete, .deleteForward:
                    backspace()
                    return .handled
                default:
                    // Backspace is U+007F on a Mac keyboard, U+0008 elsewhere.
                    if press.characters == "\u{7F}" || press.characters == "\u{8}" {
                        backspace()
                        return .handled
                    }
                    guard let c = press.characters.first, c.isASCII, c.isNumber else { return .ignored }
                    if fresh { digits = ""; fresh = false }
                    digits = String((digits + String(c)).suffix(6))
                    commit()
                    return .handled
                }
            }
    }

    /// Takes the last digit back; right after a click, the last digit of the set time.
    private func backspace() {
        if fresh { digits = Self.digits(m.total); fresh = false }
        digits = String(digits.dropLast())
        commit()
    }

    /// hhmmss of a number of seconds, six digits.
    static func digits(_ sec: Int) -> String {
        String(format: "%02d%02d%02d", min(sec / 3600, 99), sec % 3600 / 60, sec % 60)
    }

    /// The typed digits as seconds; 90 in the seconds place is a minute and a half.
    private func commit() {
        let d = Array(String(repeating: "0", count: 6 - digits.count) + digits).map { Int(String($0)) ?? 0 }
        m.total = (d[0] * 10 + d[1]) * 3600 + (d[2] * 10 + d[3]) * 60 + d[4] * 10 + d[5]
    }
}

/// Save and Start while idle, Cancel and Pause (Resume, Stop) while it runs; the main action
/// is filled with the accent, as in Screen Light.
struct MainButtons: View {
    @Environment(\.palette) private var p
    private let m = Model.shared

    var body: some View {
        let s = m.s
        HStack(spacing: 10) {
            if m.mode == .idle {
                Button { m.savePreset() } label: {
                    Label(s.save, systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(s.save)
                .accessibilityIdentifier("save")
                .disabled(m.total == 0 || m.presets.contains(m.total))
            } else {
                Button { m.reset() } label: {
                    Label(s.cancel, systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                // Esc, like Cancel everywhere in the system
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(s.cancel)
                .accessibilityIdentifier("cancel")
            }
            Button { m.main() } label: {
                Label(m.mainTitle, systemImage: mainIcon)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(p.onTint)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(m.mainTitle)
            .accessibilityIdentifier("main")
            // nothing to count down from
            .disabled(m.mode == .idle && m.total == 0)
        }
    }

    private var mainIcon: String {
        switch m.mode {
        case .idle, .paused: "play.fill"
        case .running: "pause.fill"
        case .over: "stop.fill"
        }
    }
}

/// The alarm sound, from the system's ringtones like the Clock app's; picking one plays
/// its first seconds, as System Settings does.
struct SoundPicker: View {
    @Bindable private var m = Model.shared

    var body: some View {
        let s = m.s
        Picker(s.sound, selection: $m.tone) {
            ForEach(Tones.all(lang: m.activeLang), id: \.file) { t in
                Text(t.name).tag(t.file)
            }
        }
        // A control at the row's end, like the values of lists in System Settings: the
        // choice and its chevrons at the right edge, small, sized to fit - the same rule as
        // the switches in Screen Light.
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .onChange(of: m.tone) { m.preview() }
    }
}

/// Saved times; a click sets the time, the cross deletes. Three rows show, more scroll.
struct Presets: View {
    @Environment(\.palette) private var p
    private let m = Model.shared

    var body: some View {
        let rows = VStack(spacing: 0) {
            ForEach(m.presets, id: \.self) { sec in
                if sec != m.presets.first { Divider().padding(.leading, 46) }
                Row(icon: "timer") {
                    Button {
                        m.total = sec
                    } label: {
                        Text(clock(TimeInterval(sec)))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clock(TimeInterval(sec)))
                    .accessibilityIdentifier("preset.\(sec)")
                    Button { m.removePreset(sec) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help(m.s.delete)
                        .accessibilityLabel("\(m.s.delete) \(clock(TimeInterval(sec)))")
                        .accessibilityIdentifier("delete.\(sec)")
                }
                .contextMenu {
                    Button(m.s.delete, role: .destructive) { m.removePreset(sec) }
                }
            }
        }
        Group {
            if m.presets.count > 3 {
                ScrollView { rows }.frame(height: 3 * 40)
            } else {
                rows
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .disabled(m.mode != .idle)
    }
}

/// One section: a single pane of glass, rows split by thin lines like System Settings.
struct Pane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider().padding(.leading, 46) }
                    row
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

struct Row<Content: View>: View {
    let icon: String
    @ViewBuilder var content: Content
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(p.icon).frame(width: 20)
            content
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
    }
}

/// The whole window is one pane of the system's Liquid Glass, title bar included. Being the
/// system's own glass, it follows the Liquid Glass slider in System Settings → Appearance.
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> Holder { Holder() }
    func updateNSView(_ holder: Holder, context: Context) {}

    final class Holder: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.frame = bounds
            glass.autoresizingMask = [.width, .height]
            addSubview(glass)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            // Open with nothing focused; otherwise AppKit puts the caret in the hours field.
            w.initialFirstResponder = nil
            DispatchQueue.main.async { w.makeFirstResponder(nil) }
            // Closing only hides the window, so reopening it from the Dock or the menu bar
            // doesn't come through here again: clear the focus the first time it is key again.
            let center = NotificationCenter.default
            center.removeObserver(self)
            center.addObserver(self, selector: #selector(closed), name: NSWindow.willCloseNotification, object: w)
            center.addObserver(self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: w)
        }

        private var reopened = false

        @objc private func closed() { reopened = true }

        @objc private func becameKey() {
            guard reopened, let w = window else { return }
            reopened = false
            w.makeFirstResponder(nil)
            DispatchQueue.main.async { w.makeFirstResponder(nil) }
        }

        // The glass behind everything gets the clicks that miss the controls: they end
        // typing and still drag the window.
        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) == nil ? nil : self
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)
            window?.performDrag(with: event)
        }
    }
}
