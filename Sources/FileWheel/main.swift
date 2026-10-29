import AppKit
import SwiftUI
import FileWheelCore

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    // Developer helper: `FileWheel --preview out.png` draws the wheel to a picture and quits.
    if let i = args.firstIndex(of: "--preview"), args.count > i + 1 {
        let model = WheelModel()
        model.targets = ConversionRules.targets(for: .pdf)
        model.hover = .slice(1)
        model.sweep = true; model.visible = true
        // Optional third argument picks a state to draw: spin, progress, done or failed.
        switch args.count > i + 2 ? args[i + 2] : "" {
        case "spin": model.status = .working(nil)
        case "progress": model.status = .working(0.62)
        case "done": model.status = .done
        case "failed": model.status = .failed("Can't open file")
        default: break
        }
        let view = ZStack {
            LinearGradient(colors: [.orange, .pink, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            WheelView(model: model)
        }.frame(width: 360, height: 360)
        let r = ImageRenderer(content: view); r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        exit(0)
    }
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
    app.run()
}
