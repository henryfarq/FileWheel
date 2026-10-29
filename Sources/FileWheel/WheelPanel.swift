import AppKit
import SwiftUI
import FileWheelCore

/// Catches the file when you let go of it over the wheel, so apps underneath (like Screen Line) never get it.
final class WheelDropView: NSView {
    var accepts: ((CGPoint) -> Bool)?      // is this screen point on the wheel?
    var onDrop: ((CGPoint) -> Void)?

    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }

    private func screenPoint(_ sender: NSDraggingInfo) -> CGPoint {
        window?.convertPoint(toScreen: sender.draggingLocation) ?? .zero
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts?(screenPoint(sender)) ?? false else { return [] }
        // Holding ⌘ tells Finder "move", and it then refuses a drop that answers "copy": the file just snaps back.
        // So answer with something Finder allows. FileWheel only ever reads the file, whatever the answer.
        let allowed = sender.draggingSourceOperationMask
        return [.copy, .generic, .link, .move].first { allowed.contains($0) } ?? .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let p = screenPoint(sender)
        guard accepts?(p) ?? false else { return false }
        onDrop?(p)
        return true
    }
}

/// Runs `action` once the screen has actually drawn `frames` more frames, so an animation
/// starts when the window is really visible instead of while it is still being set up.
final class AfterFrames: NSObject {
    private var link: CADisplayLink?
    private var left: Int
    private let action: () -> Void

    init(_ view: NSView, frames: Int = 2, _ action: @escaping () -> Void) {
        left = frames
        self.action = action
        super.init()
        link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ l: CADisplayLink) {
        left -= 1
        guard left <= 0 else { return }
        l.invalidate(); link = nil
        action()
    }

    func cancel() { link?.invalidate(); link = nil }
}

@MainActor
final class WheelPanel {
    let model = WheelModel()
    private let panel: NSPanel
    private let dropView: WheelDropView
    var onDrop: ((CGPoint) -> Void)? { didSet { dropView.onDrop = onDrop } }
    private(set) var token = 0      // goes up each time the wheel opens, so old work can tell it's stale
    private(set) var centerOnScreen = CGPoint.zero
    private var opening: AfterFrames?

    init() {
        let size = WheelGeometry.diameter + 40
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        dropView = WheelDropView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        let host = NSHostingView(rootView: WheelView(model: model).frame(width: size, height: size))
        host.frame = dropView.bounds
        dropView.addSubview(host)
        panel.contentView = dropView
        dropView.accepts = { [weak self] p in self.map { $0.hit(at: p) != .none } ?? false }
    }

    func show(fileName: String, targets: [FileFormat], beside file: CGRect, on screen: NSScreen) {
        let began = Date()
        token += 1
        model.fileName = fileName
        model.targets = targets
        model.hover = .none
        model.status = .idle
        centerOnScreen = WheelGeometry.center(besideFile: file, screen: screen.visibleFrame)
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: centerOnScreen.x - size.width / 2, y: centerOnScreen.y - size.height / 2))
        panel.ignoresMouseEvents = false      // so the wheel, not the app below, receives the drop
        panel.alphaValue = 1
        // Start folded (no animation) and get that drawn before the window appears...
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { model.sweep = false; model.visible = true }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        Log.write("wheel ready to appear in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
        // ...then sweep open only once the screen has really shown it, so no part of the sweep is skipped.
        opening?.cancel()
        let asked = Date()
        opening = AfterFrames(panel.contentView!) { [weak self] in
            self?.model.sweep = true
            Log.write("wheel on screen, sweep started \(Int(Date().timeIntervalSince(asked) * 1000)) ms after opening")
        }
    }

    /// Mouse position (screen coordinates, y up) turned into a position on the wheel.
    /// A little past the glass edge still counts, so a drop right on the rim isn't lost to the Desktop.
    func hit(at mouse: CGPoint) -> WheelHit {
        WheelGeometry.hit(CGPoint(x: mouse.x - centerOnScreen.x, y: centerOnScreen.y - mouse.y),
                          sliceCount: model.targets.count, outerRadius: WheelGeometry.diameter / 2 + 16)
    }

    func hover(at mouse: CGPoint) {
        let h = hit(at: mouse)
        guard h != model.hover else { return }
        model.hover = h
        if h != .none { SoundFX.shared.tick(center: h == .center) }   // a click each time you change slice
    }

    /// After a drop, let clicks go through to whatever is underneath, even while a conversion finishes.
    func releaseMouse() { panel.ignoresMouseEvents = true }

    /// Draws the wheel once, invisibly, so macOS has the glass effect ready before it's needed for real.
    /// Without this the very first wheel stutters and appears part-way through its sweep.
    func warmUp() {
        guard let screen = NSScreen.main else { return }
        model.targets = [.png, .jpeg, .heic, .pdf]
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { model.sweep = true; model.visible = true }
        panel.alphaValue = 0.01
        panel.setFrameOrigin(screen.frame.origin)
        panel.orderFrontRegardless()
        panel.display()
        // The display link holds on to this until it fires, so it needn't be stored.
        _ = AfterFrames(panel.contentView!, frames: 6) { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            withTransaction(t) { self.model.sweep = false; self.model.visible = false }
        }
    }

    func hide(after delay: TimeInterval = 0) {
        opening?.cancel()
        panel.ignoresMouseEvents = true
        let mine = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard mine == self.token else { return }
            self.model.visible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if mine == self.token { self.panel.orderOut(nil) }
            }
        }
    }
}
