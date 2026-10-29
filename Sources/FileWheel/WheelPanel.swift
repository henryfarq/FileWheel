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
        (accepts?(screenPoint(sender)) ?? false) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let p = screenPoint(sender)
        guard accepts?(p) ?? false else { return false }
        onDrop?(p)
        return true
    }
}

@MainActor
final class WheelPanel {
    let model = WheelModel()
    private let panel: NSPanel
    private let dropView: WheelDropView
    var onDrop: ((CGPoint) -> Void)? { didSet { dropView.onDrop = onDrop } }
    private(set) var token = 0      // goes up each time the wheel opens, so old work can tell it's stale
    private(set) var centerOnScreen = CGPoint.zero

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
        token += 1
        model.fileName = fileName
        model.targets = targets
        model.hover = .none
        model.status = .idle
        centerOnScreen = WheelGeometry.center(besideFile: file, screen: screen.visibleFrame)
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: centerOnScreen.x - size.width / 2, y: centerOnScreen.y - size.height / 2))
        panel.ignoresMouseEvents = false      // so the wheel, not the app below, receives the drop
        panel.orderFrontRegardless()
        // Start folded (no animation), then sweep open clockwise on the next beat.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { model.sweep = false; model.visible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self.model.sweep = true }
    }

    /// Mouse position (screen coordinates, y up) turned into a position on the wheel.
    func hit(at mouse: CGPoint) -> WheelHit {
        WheelGeometry.hit(CGPoint(x: mouse.x - centerOnScreen.x, y: centerOnScreen.y - mouse.y),
                          sliceCount: model.targets.count)
    }

    func hover(at mouse: CGPoint) {
        let h = hit(at: mouse)
        guard h != model.hover else { return }
        model.hover = h
        if h != .none { SoundFX.shared.tick(center: h == .center) }   // a click each time you change slice
    }

    /// After a drop, let clicks go through to whatever is underneath, even while a conversion finishes.
    func releaseMouse() { panel.ignoresMouseEvents = true }

    func hide(after delay: TimeInterval = 0) {
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
