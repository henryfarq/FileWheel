import XCTest
import AppKit
@testable import FileWheelCore

final class RulesTests: XCTestCase {
    func testNoFormatConvertsToItself() {
        for f in FileFormat.all where f != .txt {
            XCTAssertFalse(ConversionRules.canConvert(f, to: f), f.label)
        }
    }
    func testPDFOffersTextButImagesDont() {
        XCTAssertTrue(ConversionRules.canConvert(.pdf, to: .txt))
        XCTAssertFalse(ConversionRules.canConvert(.png, to: .txt))
    }
    func testFamiliesDontMix() {
        XCTAssertFalse(ConversionRules.canConvert(.png, to: .mp4))
        XCTAssertFalse(ConversionRules.canConvert(.wav, to: .png))
        XCTAssertFalse(ConversionRules.canConvert(.mp4, to: .wav))
        XCTAssertTrue(ConversionRules.canConvert(.mp4, to: .m4a))
    }
    func testDetect() {
        XCTAssertEqual(FileFormat.detect(url: URL(fileURLWithPath: "/a/b.JPEG")), .jpeg)
        XCTAssertEqual(FileFormat.detect(url: URL(fileURLWithPath: "/a/b.aif")), .aiff)
        XCTAssertNil(FileFormat.detect(url: URL(fileURLWithPath: "/a/b.docx")))
    }
}

final class GeometryTests: XCTestCase {
    func testSlicesGoClockwiseFromTwelve() {
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: 1, y: -100), sliceCount: 4), .slice(0))
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: 100, y: 1), sliceCount: 4), .slice(1))
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: -1, y: 100), sliceCount: 4), .slice(2))
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: -100, y: -1), sliceCount: 4), .slice(3))
    }
    func testCenterAndOutside() {
        XCTAssertEqual(WheelGeometry.hit(.zero, sliceCount: 4), .center)
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: 400, y: 0), sliceCount: 4), .none)
    }
    func testPlacementFlipsLeftNearRightEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let nearLeft = WheelGeometry.center(besideFile: CGRect(x: 100, y: 400, width: 80, height: 90), screen: screen)
        XCTAssertGreaterThan(nearLeft.x, 180)
        let nearRight = WheelGeometry.center(besideFile: CGRect(x: 1350, y: 400, width: 80, height: 90), screen: screen)
        XCTAssertLessThan(nearRight.x, 1350)
    }
}

final class ConverterTests: XCTestCase {
    func testUniqueURLAddsNumber() {
        let folder = URL(fileURLWithPath: "/tmp")
        let taken: Set<String> = ["/tmp/a.jpg", "/tmp/a 2.jpg"]
        let url = Converter.uniqueURL(base: "a", ext: "jpg", in: folder) { taken.contains($0.path) }
        XCTAssertEqual(url.lastPathComponent, "a 3.jpg")
    }

    func testPNGToJPGToPDFAndBack() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = dir.appendingPathComponent("pic.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: png)

        let jpg = try await Converter.convertOne(png, to: .jpeg, into: dir)
        XCTAssertEqual(jpg.lastPathComponent, "pic.jpg")
        XCTAssertNotNil(NSImage(contentsOf: jpg))
        let pdf = try await Converter.convertOne(jpg, to: .pdf, into: dir)
        XCTAssertEqual(pdf.pathExtension, "pdf")
        let back = try await Converter.convertOne(pdf, to: .png, into: dir)
        XCTAssertEqual(back.lastPathComponent, "pic 2.png")   // pic.png already exists, original untouched
        XCTAssertNotNil(NSImage(contentsOf: back))
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path))
        // Every made file carries the hidden tag; the original does not.
        func tagged(_ u: URL) -> Bool { getxattr(u.path, Converter.convertedTag, nil, 0, 0, 0) >= 0 }
        XCTAssertTrue(tagged(jpg) && tagged(pdf) && tagged(back))
        XCTAssertFalse(tagged(png))
    }

    func testWAVToAIFF() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wav = dir.appendingPathComponent("tone.wav")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        do {
        let file = try AVAudioFile(forWriting: wav, settings: fmt.settings)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4410)!
        buf.frameLength = 4410
        for i in 0..<4410 { buf.floatChannelData![0][i] = sin(Float(i) * 0.1) * 0.5 }
        try file.write(from: buf)
        }
        let aiff = try await Converter.convertOne(wav, to: .aiff, into: dir)
        XCTAssertEqual(try AVAudioFile(forReading: aiff).length, 4410)
    }
}
import AVFoundation

extension Converter {
    /// Most conversions make exactly one file; tests use this to get it.
    static func convertOne(_ s: URL, to t: FileFormat, into f: URL) async throws -> URL {
        try await convert(s, to: t, into: f).first!
    }
}

final class MultiPageTests: XCTestCase {
    func testEachPDFPageBecomesItsOwnImage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdf = dir.appendingPathComponent("doc.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ctx = CGContext(pdf as CFURL, mediaBox: &box, nil)!
        for _ in 0..<3 { ctx.beginPDFPage(nil); ctx.endPDFPage() }
        ctx.closePDF()

        let seen = Counter()
        let outs = try await Converter.convert(pdf, to: .png, into: dir) { p in seen.add(p) }
        XCTAssertEqual(outs.map(\.lastPathComponent), ["doc page 1.png", "doc page 2.png", "doc page 3.png"])
        XCTAssertTrue(outs.allSatisfy { NSImage(contentsOf: $0) != nil })
        XCTAssertEqual(seen.values.last, 1.0)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
}
