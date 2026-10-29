import SwiftUI
import FileWheelCore

/// Everything the wheel needs to draw itself; the controller updates it while you drag.
@MainActor
final class WheelModel: ObservableObject {
    @Published var fileName = ""
    @Published var targets: [FileFormat] = []
    @Published var hover: WheelHit = .none
    @Published var sweep = false      // the clockwise reveal from 12 o'clock
    @Published var visible = false    // whole wheel shown; going false shrinks and fades it
    @Published var status: Status = .idle
    /// idle = choosing; working(progress) = converting (nil progress = just spin); done / failed = the result.
    enum Status: Equatable { case idle, working(Double?), done, failed(String) }
}

/// One petal of the ring with rounded corners. Angles run clockwise from 12 o'clock.
struct PetalShape: Shape {
    var index: Int, count: Int
    var inner: CGFloat, outer: CGFloat
    var corner: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let step = 2 * Double.pi / Double(count), gap = 0.03
        let a0 = Double(index) * step + gap - .pi / 2, a1 = Double(index + 1) * step - gap - .pi / 2
        // Draw a smaller petal, then fatten its outline by `corner` with round joins: that rounds every corner.
        let ri = inner + corner, ro = outer - corner
        let di = Double(corner / ri), dout = Double(corner / ro)
        func pt(_ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        var core = Path()
        core.addArc(center: c, radius: ro, startAngle: .radians(a0 + dout), endAngle: .radians(a1 - dout), clockwise: false)
        core.addLine(to: pt(ri, a1 - di))
        core.addArc(center: c, radius: ri, startAngle: .radians(a1 - di), endAngle: .radians(a0 + di), clockwise: true)
        core.closeSubpath()
        return core.union(core.strokedPath(StrokeStyle(lineWidth: corner * 2, lineJoin: .round)))
    }
}

struct WheelView: View {
    @ObservedObject var model: WheelModel
    private let d = WheelGeometry.diameter
    private var inner: CGFloat { WheelGeometry.centerRadius + 8 }
    private var outer: CGFloat { d / 2 - 4 }

    var body: some View {
        ZStack {
            // The ring sweeps open clockwise from 12 o'clock: a thick ring stroke grows from 0 to 1 and masks it.
            ZStack {
                ForEach(Array(model.targets.enumerated()), id: \.offset) { i, f in
                    let lit = model.hover == .slice(i)
                    let shape = PetalShape(index: i, count: model.targets.count, inner: inner, outer: outer)
                    glass(shape)
                        .overlay(shape.fill(lit ? Color.orange.opacity(0.85) : Color.clear))
                        .shadow(color: lit ? .orange.opacity(0.7) : .clear, radius: 12)
                    label(f.label, index: i, lit: lit)
                }
            }
            .frame(width: d, height: d)
            .mask(
                Circle().trim(from: 0, to: model.sweep ? 1 : 0.0001)
                    .stroke(lineWidth: d)
                    .rotationEffect(.degrees(-90))
                    .frame(width: d, height: d)
            )
            .opacity(model.sweep ? 1 : 0)      // a gentle fade-in alongside the sweep, so it isn't harsh
            .animation(.timingCurve(0.22, 0.0, 0.05, 1.0, duration: 0.4), value: model.sweep)   // quick, with a soft landing
            // Once a file is dropped the buttons drift away, leaving only the centre circle to show progress.
            .opacity(model.status == .idle ? 1 : 0)
            .scaleEffect(model.status == .idle ? 1 : 1.08)
            .animation(.easeOut(duration: 0.25), value: model.status == .idle)

            // The AirDrop button doesn't sweep; it just fades in as the sweep begins.
            centre
                .opacity(model.sweep ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: model.sweep)
        }
        .frame(width: d, height: d)
        // Closing is not a sweep: the whole wheel shrinks a little and fades.
        .scaleEffect(model.visible ? 1 : 0.8)
        .opacity(model.visible ? 1 : 0)
        .animation(.easeIn(duration: 0.2), value: model.visible)
        .animation(.easeOut(duration: 0.1), value: model.hover)
    }

    /// Glass petal; the gaps between petals are left empty so the desktop shows through.
    @ViewBuilder private func glass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26, *) {
            shape.fill(Color.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private func label(_ text: String, index: Int, lit: Bool) -> some View {
        let step = 2 * Double.pi / Double(model.targets.count)
        let angle = (Double(index) + 0.5) * step - .pi / 2
        let r = (inner + outer) / 2
        return Text(text).font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(lit ? .white : .primary)
            .position(x: d / 2 + cos(angle) * r, y: d / 2 + sin(angle) * r)
    }

    private var centre: some View {
        let over = model.hover == .center
        let size = WheelGeometry.centerRadius * 2 - 4
        let done = model.status == .done
        let failed: Bool = { if case .failed = model.status { return true }; return false }()
        return ZStack {
            glass(Circle())
                .overlay(Circle().fill(over && model.status == .idle ? Color.blue.opacity(0.85) : Color.clear))
                // The result colour grows out from the middle until it fills the whole circle.
                .overlay(Circle().fill(Color.green).scaleEffect(done ? 1 : 0.01).opacity(done ? 1 : 0))
                .overlay(Circle().fill(Color.red).scaleEffect(failed ? 1 : 0.01).opacity(failed ? 1 : 0))
                .frame(width: size, height: size)
            switch model.status {
            case .idle:
                VStack(spacing: 2) {
                    Image(systemName: "airplayaudio").font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                    Text("AirDrop").font(.system(size: 9, weight: .medium))
                }.foregroundStyle(over ? .white : .primary)
            case .working(let progress):
                LoadingRing(progress: progress).frame(width: size - 18, height: size - 18)
            case .done:
                Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            case .failed(let why):
                VStack(spacing: 3) {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .bold))
                    Text(why).font(.system(size: 9, weight: .semibold)).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .frame(width: size - 14)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.status)
        .position(x: d / 2, y: d / 2)
    }
}

/// The loading circle. With a known progress it fills up and shows a percentage; without one it spins.
struct LoadingRing: View {
    var progress: Double?
    private let line = StrokeStyle(lineWidth: 5, lineCap: .round)

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: 5)
            if let p = progress {
                Circle().trim(from: 0, to: max(0.02, min(p, 1)))
                    .stroke(Color.primary, style: line)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.15), value: p)
                Text("\(Int((min(p, 1) * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            } else {
                TimelineView(.animation) { ctx in
                    let turn = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
                    Circle().trim(from: 0, to: 0.28)
                        .stroke(Color.primary, style: line)
                        .rotationEffect(.degrees(turn * 360))
                }
            }
        }
    }
}
