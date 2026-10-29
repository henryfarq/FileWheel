import AppKit
import FileWheelCore

/// Watches the mouse, shows the wheel on ⌘-drag, and acts when you let go.
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSSharingServiceDelegate {
    private var airDrop: NSSharingService?
    private var airDropOrigin = CGRect.zero
    private var wheel: WheelPanel?          // the wheel you are dragging over right now
    private var busy: [WheelPanel] = []     // dropped-on wheels, now just a progress bubble while their file converts
    private var monitors: [Any] = []
    private var armed = false
    private var dragStart = CGPoint.zero
    private var active: DesktopFile?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()
        Log.write("launched")
        // A drag that holds still gives no mouse events, so also look for ⌘ being pressed a few times a second.
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateWheel()
            }
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            let flags = e.modifierFlags, type = e.type, loc = NSEvent.mouseLocation
            Task { @MainActor in self?.handle(type: type, command: flags.contains(.command), at: loc) }
        }) { monitors.append(m) }
    }

    private var dragBaseline = 0

    private func handle(type: NSEvent.EventType, command: Bool, at mouse: CGPoint) {
        switch type {
        case .leftMouseDown:
            active = nil
            armed = true                       // "armed" = the mouse button is down; ⌘ is checked as you go
            dragStart = mouse
            dragBaseline = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            updateWheel()
        case .leftMouseUp:
            armed = false
            // If the wheel caught the drop it already acted; otherwise the drag ended off the wheel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.active != nil, !self.armed else { return }
                self.wheel?.hide(); self.wheel = nil; self.active = nil
            }
        default: break
        }
    }

    /// The wheel follows ⌘: shown while it is held during a drag, tucked away when it is released.
    private func updateWheel() {
        guard armed else { return }
        if NSEvent.modifierFlags.contains(.command) {
            tryShowWheel()
            if active != nil { wheel?.hover(at: NSEvent.mouseLocation) }
        } else if active != nil {
            active = nil
            wheel?.hide()
            wheel = nil
        }
    }

    /// Shows the wheel once a file is being dragged AND ⌘ is held, whichever happened first.
    private func tryShowWheel() {
        let mouse = NSEvent.mouseLocation
        guard active == nil, armed, NSEvent.modifierFlags.contains(.command),
              NSPasteboard(name: .drag).changeCount != dragBaseline,       // a real drag has started
              hypot(mouse.x - dragStart.x, mouse.y - dragStart.y) > 8,
              let c = draggedFile(), let format = FileFormat.detect(url: c.url),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(dragStart) }) ?? NSScreen.main
        else { return }
        active = c
        // A fresh wheel every time, so earlier ones can keep showing their conversion's progress.
        let w = WheelPanel()
        w.onDrop = { [weak self, weak w] p in
            guard let self, let w else { return }
            self.dropped(on: w, at: p)
        }
        wheel = w
        w.show(fileName: c.url.lastPathComponent, targets: ConversionRules.targets(for: format),
               beside: c.frame, on: screen)
    }

    /// The file being dragged right now: macOS keeps it on the "drag" clipboard while you drag.
    private func draggedFile() -> DesktopFile? {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let url = urls.first(where: { FileFormat.detect(url: $0) != nil }) else { return nil }
        // The icon was picked up where the mouse went down, so put the wheel beside that spot.
        let frame = CGRect(x: dragStart.x - 40, y: dragStart.y - 45, width: 80, height: 90)
        Log.write("dragging \(url.lastPathComponent)")
        return DesktopFile(url: url, frame: frame)
    }

    private func dropped(on w: WheelPanel, at point: CGPoint) {
        guard w === wheel, let file = active else { return }
        active = nil
        wheel = nil                 // the next ⌘-drag gets its own wheel
        w.releaseMouse()
        finish(file, on: w, hit: w.hit(at: point))
    }

    private func finish(_ file: DesktopFile, on w: WheelPanel, hit: WheelHit) {
        switch hit {
        case .slice(let i):
            let target = w.model.targets[i]
            busy.append(w)
            w.model.status = .working(nil)
            Task {
                let start = Date()
                var result: WheelModel.Status = .done
                do {
                    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                    let outs = try await Converter.convert(file.url, to: target, into: desktop) { p in
                        Task { @MainActor in
                            if case .working = w.model.status { w.model.status = .working(p) }
                        }
                    }
                    Log.write("saved \(outs.map(\.lastPathComponent).joined(separator: ", "))")
                } catch {
                    result = .failed(ConversionError.shortReason(error))
                    Log.write("failed \(file.url.lastPathComponent) → \(target.label): \(error.localizedDescription)")
                    NSSound.beep()
                }
                // Even a 1 ms conversion shows the loading circle briefly, so the result doesn't just flash.
                let shown = Date().timeIntervalSince(start)
                if shown < 0.6 { try? await Task.sleep(nanoseconds: UInt64((0.6 - shown) * 1e9)) }
                w.model.status = result
                let linger = result == .done ? 0.9 : 2.2
                w.hide(after: linger)
                DispatchQueue.main.asyncAfter(deadline: .now() + linger + 0.5) { [weak self] in
                    self?.busy.removeAll { $0 === w }
                }
            }
        case .center:
            // Hand the file to AirDrop. The AirDrop window is macOS's own, so tell it to start from the
            // wheel's centre button instead of sliding down from the top of the screen.
            let c = w.centerOnScreen, r = WheelGeometry.centerRadius
            airDropOrigin = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            airDrop = NSSharingService(named: .sendViaAirDrop)
            airDrop?.delegate = self
            airDrop?.perform(withItems: [file.url])
            w.hide()
        case .none:
            w.hide()
        }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        MainActor.assumeIsolated { airDropOrigin }
    }

    // MARK: menu bar + permission

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "FileWheel")
        let menu = NSMenu()
        menu.addItem(withTitle: "Hold ⌘ and drag a Desktop file", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FileWheel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

}

/// Notes for troubleshooting. Off unless FileWheel is started with FILEWHEEL_DEBUG=1, so file names aren't recorded.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["FILEWHEEL_DEBUG"] == "1"
    static func write(_ m: String) {
        guard enabled else { return }
        let line = "\(Date()) \(m)\n"
        let url = URL(fileURLWithPath: "/tmp/filewheel.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}

struct DesktopFile { let url: URL; let frame: CGRect }
