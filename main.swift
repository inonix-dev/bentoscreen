// BentoScreen — one hotkey arranges every window of a layout.
// Layouts live in ~/.config/bentoscreen/layouts.json (written on first run).
import AppKit
import Carbon.HIToolbox

struct Slot: Codable { let apps: [String]; let x, y, w, h: Double }  // fractions of the screen, origin top-left
struct Layout: Codable { let name: String; let hotkey: String; let slots: [Slot] }

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/bentoscreen/layouts.json")

let defaultLayouts = [
    Layout(name: "Agent", hotkey: "ctrl+opt+1", slots: [
        Slot(apps: ["Arc", "Google Chrome", "Safari"], x: 0, y: 0, w: 0.5, h: 2.0 / 3),
        Slot(apps: ["LINE", "Discord", "Telegram"], x: 0, y: 2.0 / 3, w: 0.5, h: 1.0 / 3),
        Slot(apps: ["Claude", "Zed", "iTerm2"], x: 0.5, y: 0, w: 0.5, h: 1),
    ]),
    Layout(name: "Half / Half", hotkey: "ctrl+opt+2", slots: [
        Slot(apps: ["Arc", "Google Chrome", "Safari"], x: 0, y: 0, w: 0.5, h: 1),
        Slot(apps: ["Claude", "Zed", "iTerm2"], x: 0.5, y: 0, w: 0.5, h: 1),
    ]),
]

func loadLayouts() -> [Layout] {
    if let data = try? Data(contentsOf: configURL) {
        do { return try JSONDecoder().decode([Layout].self, from: data) } catch {
            alert("layouts.json is broken, using defaults.\n\n\(error)")
            return defaultLayouts
        }
    }
    try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? enc.encode(defaultLayouts).write(to: configURL)
    return defaultLayouts
}

func alert(_ text: String) {
    let a = NSAlert(); a.messageText = "BentoScreen"; a.informativeText = text; a.runModal()
}

// Cocoa screens are bottom-left origin; AX wants top-left origin of the primary screen.
func axRect(_ s: Slot, in visible: CGRect, primaryHeight: CGFloat) -> CGRect {
    let w = visible.width * s.w, h = visible.height * s.h
    let x = visible.minX + visible.width * s.x
    let top = visible.maxY - visible.height * s.y
    return CGRect(x: x.rounded(), y: (primaryHeight - top).rounded(), width: w.rounded(), height: h.rounded())
}

func matches(_ app: NSRunningApplication, _ name: String) -> Bool {
    let n = name.lowercased()
    return app.localizedName?.lowercased() == n || app.bundleIdentifier?.lowercased() == n
        || app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() == n
}

func place(_ win: AXUIElement, _ r: CGRect) {
    var origin = r.origin, size = r.size
    let pos = AXValueCreate(.cgPoint, &origin)!, sz = AXValueCreate(.cgSize, &size)!
    // size → position → size: a window moved across displays may clamp its size on the first try
    AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sz)
    AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pos)
    AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sz)
}

func apply(_ layout: Layout) {
    guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else { return }
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
          let primaryHeight = NSScreen.screens.first?.frame.height else { return }
    let running = NSWorkspace.shared.runningApplications
    for slot in layout.slots {
        let r = axRect(slot, in: screen.visibleFrame, primaryHeight: primaryHeight)
        for name in slot.apps {
            // ponytail: apps that aren't running are skipped, not launched
            for app in running where matches(app, name) {
                let el = AXUIElementCreateApplication(app.processIdentifier)
                var ref: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &ref)
                for win in (ref as? [AXUIElement]) ?? [] {
                    var sub: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &sub)
                    if (sub as? String) == kAXStandardWindowSubrole { place(win, r) }
                }
            }
        }
    }
}

// MARK: snap the focused window (ShiftIt-style)

enum Snap: Int, CaseIterable { case left, right, up, down, fill, topLeft, topRight, bottomLeft, bottomRight, center, nextScreen }
let snapKeys: [Snap: String] = [.left: "left", .right: "right", .up: "up", .down: "down", .fill: "m",
                                .topLeft: "1", .topRight: "2", .bottomLeft: "3", .bottomRight: "4", .center: "c", .nextScreen: "n"]
let snapMods = "ctrl+opt+cmd"
let steps: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]  // pressing the same key again cycles through these

// vis and win are AX (top-left origin) rects. ←/→ take a width share at full height,
// ↑/↓ keep the window's column and take a height share.
func snapRect(_ snap: Snap, step: Int, vis: CGRect, win: CGRect) -> CGRect {
    let f = steps[step % steps.count]
    let r: CGRect
    switch snap {
    case .left: r = CGRect(x: vis.minX, y: vis.minY, width: vis.width * f, height: vis.height)
    case .right: r = CGRect(x: vis.maxX - vis.width * f, y: vis.minY, width: vis.width * f, height: vis.height)
    case .up: r = CGRect(x: win.minX, y: vis.minY, width: win.width, height: vis.height * f)
    case .down: r = CGRect(x: win.minX, y: vis.maxY - vis.height * f, width: win.width, height: vis.height * f)
    case .fill: r = vis
    case .topLeft, .topRight, .bottomLeft, .bottomRight:
        let w = vis.width * f, h = vis.height * f
        let x = snap == .topLeft || snap == .bottomLeft ? vis.minX : vis.maxX - w
        let y = snap == .topLeft || snap == .topRight ? vis.minY : vis.maxY - h
        r = CGRect(x: x, y: y, width: w, height: h)
    case .nextScreen: r = win  // handled by moveRect, needs the other screen
    case .center:  // keeps its size (clamped to the screen), no cycling
        let w = min(win.width, vis.width), h = min(win.height, vis.height)
        r = CGRect(x: vis.midX - w / 2, y: vis.midY - h / 2, width: w, height: h)
    }
    return r.integral
}

// Same place and share of the screen, on another screen (clamped so it fits).
func moveRect(_ win: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
    let w = min(win.width / a.width * b.width, b.width), h = min(win.height / a.height * b.height, b.height)
    let x = b.minX + (win.minX - a.minX) / a.width * b.width, y = b.minY + (win.minY - a.minY) / a.height * b.height
    return CGRect(x: min(max(x, b.minX), b.maxX - w), y: min(max(y, b.minY), b.maxY - h), width: w, height: h).integral
}

var lastSnap: (win: AXUIElement, snap: Snap, step: Int)?

func snapFocused(_ snap: Snap) {
    guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary),
          let primaryHeight = NSScreen.screens.first?.frame.height else { return }
    var app: CFTypeRef?, winRef: CFTypeRef?, posRef: CFTypeRef?, sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &app)
    guard let app else { return }
    AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &winRef)
    guard let winRef else { return }
    let win = winRef as! AXUIElement
    AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
    var pos = CGPoint.zero, size = CGSize.zero
    if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &pos) }
    if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }
    let frame = CGRect(origin: pos, size: size)
    let full = Slot(apps: [], x: 0, y: 0, w: 1, h: 1)
    // the screen the window's centre is on, else the one under the mouse
    let screen = NSScreen.screens.first { axRect(full, in: $0.frame, primaryHeight: primaryHeight).contains(CGPoint(x: frame.midX, y: frame.midY)) }
        ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
    // ponytail: remembers the last press instead of matching frames — apps like iTerm2 round sizes to their grid
    let vis = { (s: NSScreen) in axRect(full, in: s.visibleFrame, primaryHeight: primaryHeight) }
    if snap == .nextScreen {
        let all = NSScreen.screens, i = all.firstIndex(of: screen) ?? 0
        place(win, moveRect(frame, from: vis(screen), to: vis(all[(i + 1) % all.count])))
        return
    }
    let step = lastSnap.map { CFEqual($0.win, win) && $0.snap == snap ? $0.step + 1 : 0 } ?? 0
    lastSnap = (win, snap, step)
    place(win, snapRect(snap, step: step, vis: vis(screen), win: frame))
}

// MARK: hotkeys

let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
]
let modifiers: [String: Int] = ["ctrl": controlKey, "opt": optionKey, "alt": optionKey, "cmd": cmdKey, "shift": shiftKey]

func parseHotkey(_ s: String) -> (key: UInt32, mods: UInt32)? {
    var key: Int?, mods = 0
    for part in s.lowercased().split(separator: "+").map(String.init) {
        if let m = modifiers[part] { mods |= m } else if key == nil, let k = keyCodes[part] { key = k } else { return nil }
    }
    guard let key, mods != 0 else { return nil }
    return (UInt32(key), UInt32(mods))
}

var hotkeyRefs: [EventHotKeyRef] = []

func registerHotkeys(_ layouts: [Layout]) {
    hotkeyRefs.forEach { UnregisterEventHotKey($0) }
    hotkeyRefs = []
    for (i, l) in layouts.enumerated() {
        guard let hk = parseHotkey(l.hotkey) else { alert("Bad hotkey \"\(l.hotkey)\" in layout \(l.name)"); continue }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(hk.key, hk.mods, EventHotKeyID(signature: 0x42454E54, id: UInt32(i)), GetApplicationEventTarget(), 0, &ref)
        if let ref { hotkeyRefs.append(ref) }
    }
    for snap in Snap.allCases {
        let hk = parseHotkey("\(snapMods)+\(snapKeys[snap]!)")!
        var ref: EventHotKeyRef?
        RegisterEventHotKey(hk.key, hk.mods, EventHotKeyID(signature: 0x42454E54, id: UInt32(snapIDBase + snap.rawValue)), GetApplicationEventTarget(), 0, &ref)
        if let ref { hotkeyRefs.append(ref) }
    }
}
let snapIDBase = 1000

// MARK: menu bar app

final class App: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var layouts: [Layout] = []

    func applicationDidFinishLaunching(_: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuIcon()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let app = NSApp.delegate as! App
            if let snap = Snap(rawValue: Int(id.id) - snapIDBase) { snapFocused(snap) }
            else if Int(id.id) < app.layouts.count { apply(app.layouts[Int(id.id)]) }
            return noErr
        }, 1, &spec, nil, nil)
        reload()
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    @objc func reload() {
        layouts = loadLayouts()
        registerHotkeys(layouts)
        let menu = NSMenu()
        for (i, l) in layouts.enumerated() {
            let mi = NSMenuItem(title: "\(l.name)    \(l.hotkey)", action: #selector(pick(_:)), keyEquivalent: "")
            mi.tag = i; mi.target = self; menu.addItem(mi)
        }
        menu.addItem(.separator())
        for hint in ["⌃⌥⌘ ← →   left / right  ½ → ⅔ → ⅓", "⌃⌥⌘ ↑ ↓   top / bottom  ½ → ⅔ → ⅓", "⌃⌥⌘ 1 2 3 4   corners  ½ → ⅔ → ⅓",
                     "⌃⌥⌘ M      fill screen", "⌃⌥⌘ C      center", "⌃⌥⌘ N      next display"] {
            menu.addItem(NSMenuItem(title: hint, action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        for (title, sel) in [("Edit Layouts…", #selector(edit)), ("Reload Layouts", #selector(reload))] {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: ""); mi.target = self; menu.addItem(mi)
        }
        menu.addItem(NSMenuItem(title: "Quit BentoScreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc func pick(_ sender: NSMenuItem) { apply(layouts[sender.tag]) }
    @objc func edit() { NSWorkspace.shared.open(configURL) }
}

// Remix Icon "layout-masonry-fill" (Apache-2.0): four rounded tiles on a 24pt grid, drawn as a template image.
func menuIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let s: CGFloat = 18.0 / 24
        for (x, y, w, h) in [(3.0, 3.0, 10.0, 8.0), (15, 3, 6, 8), (11, 13, 10, 8), (3, 13, 6, 8)] {
            NSBezierPath(roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: h * s), xRadius: s, yRadius: s).fill()
        }
        return true
    }
    img.isTemplate = true  // follows light/dark menu bar
    return img
}

// MARK: self-check (`BentoScreen --check`)

func selfCheck() {
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)  // primary, no menu bar for easy maths
    let browser = axRect(Slot(apps: [], x: 0, y: 0, w: 0.5, h: 2.0 / 3), in: screen, primaryHeight: 900)
    precondition(browser == CGRect(x: 0, y: 0, width: 600, height: 600), "\(browser)")
    let chat = axRect(Slot(apps: [], x: 0, y: 2.0 / 3, w: 0.5, h: 1.0 / 3), in: screen, primaryHeight: 900)
    precondition(chat == CGRect(x: 0, y: 600, width: 600, height: 300), "\(chat)")
    // second display to the right, shorter, bottom-aligned with the primary
    let right = axRect(Slot(apps: [], x: 0.5, y: 0, w: 0.5, h: 1), in: CGRect(x: 1200, y: 0, width: 800, height: 600), primaryHeight: 900)
    precondition(right == CGRect(x: 1600, y: 300, width: 400, height: 600), "\(right)")
    precondition(parseHotkey("ctrl+opt+1")! == (UInt32(kVK_ANSI_1), UInt32(controlKey | optionKey)))
    precondition(parseHotkey("1") == nil && parseHotkey("ctrl+opt+f13") == nil)
    let vis = CGRect(x: 0, y: 25, width: 1200, height: 900), win = CGRect(x: 0, y: 25, width: 600, height: 900)
    precondition(snapRect(.left, step: 0, vis: vis, win: win) == CGRect(x: 0, y: 25, width: 600, height: 900))
    precondition(snapRect(.right, step: 1, vis: vis, win: win) == CGRect(x: 400, y: 25, width: 800, height: 900))
    precondition(snapRect(.up, step: 1, vis: vis, win: win) == CGRect(x: 0, y: 25, width: 600, height: 600))
    precondition(snapRect(.down, step: 2, vis: vis, win: win) == CGRect(x: 0, y: 625, width: 600, height: 300))
    precondition(snapRect(.down, step: 3, vis: vis, win: win) == snapRect(.down, step: 0, vis: vis, win: win))
    precondition(snapRect(.bottomRight, step: 0, vis: vis, win: win) == CGRect(x: 600, y: 475, width: 600, height: 450))
    precondition(snapRect(.topLeft, step: 2, vis: vis, win: win) == CGRect(x: 0, y: 25, width: 400, height: 300))
    precondition(snapRect(.center, step: 0, vis: vis, win: CGRect(x: 0, y: 0, width: 400, height: 2000))
                 == CGRect(x: 400, y: 25, width: 400, height: 900))
    // left half of a 1200 screen → left half of a 1600 screen sitting to its right
    precondition(moveRect(win, from: vis, to: CGRect(x: 1200, y: 0, width: 1600, height: 1000))
                 == CGRect(x: 1200, y: 0, width: 800, height: 1000))
    precondition(parseHotkey("ctrl+opt+cmd+left") != nil)
    print("ok")
}

if CommandLine.arguments.contains("--check") { selfCheck(); exit(0) }
let delegate = App()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
