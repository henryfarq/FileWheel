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
    // Developer helper: `FILEWHEEL_DEBUG=1 FileWheel --demo-open` opens wheels by itself (a cold one, then
    // warmed ones) and logs how quickly each starts its sweep, then quits.
    if args.contains("--demo-open") {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let screen = NSScreen.main!
        let spot = CGRect(x: screen.frame.midX - 300, y: screen.frame.midY - 45, width: 80, height: 90)
        let cold = WheelPanel()
        let warm = WheelPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { warm.warmUp() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Log.write("cold (no warm-up):")
            cold.show(fileName: "demo.png", targets: ConversionRules.targets(for: .png), beside: spot, on: screen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { cold.hide() }
        }
        var later: [WheelPanel] = []
        for (n, delay) in [2.0, 3.5].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let w = WheelPanel(); later.append(w)
                Log.write("new wheel #\(n + 1) after warm-up:")
                w.show(fileName: "demo.png", targets: ConversionRules.targets(for: .pdf), beside: spot, on: screen)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { w.hide() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
        app.run()
    }
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
    app.run()
}
