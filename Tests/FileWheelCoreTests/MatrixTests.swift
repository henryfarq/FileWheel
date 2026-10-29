import XCTest
import AppKit
import AVFoundation
import PDFKit
import ImageIO
@testable import FileWheelCore

/// Makes a sample of every supported file type, runs every conversion the wheel offers,
/// and checks each result really opens as the new type.
final class MatrixTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fw-matrix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func testEveryImageAndPDFConversion() async throws {
        let png = try makePNG()
        var sources: [URL] = [png]
        for f in [FileFormat.jpeg, .heic, .tiff, .gif, .bmp] {
            sources.append(try await Converter.convertOne(png, to: f, into: dir))
        }
        sources.append(try makeTextPDF())
        try await runAll(sources)
    }

    func testEveryAudioConversion() async throws {
        let wav = try makeWAV()
        var sources = [wav]
        for f in [FileFormat.m4a, .aiff, .caf] {
            sources.append(try await Converter.convertOne(wav, to: f, into: dir))
        }
        try await runAll(sources)
    }

    func testEveryVideoConversion() async throws {
        let mov = try await makeMovie()
        try await runAll([mov])
        // Optionally also try a real video: FILEWHEEL_SAMPLE_VIDEO=/path/to/clip.mp4 swift test
        if let path = ProcessInfo.processInfo.environment["FILEWHEEL_SAMPLE_VIDEO"],
           FileManager.default.fileExists(atPath: path) {
            let real = URL(fileURLWithPath: path)
            let copy = dir.appendingPathComponent("recording.mp4")
            try FileManager.default.copyItem(at: real, to: copy)   // never touch the original
            try await runAll([copy])
        }
    }

    // MARK: running and checking

    private func runAll(_ sources: [URL]) async throws {
        for src in sources {
            let from = try XCTUnwrap(FileFormat.detect(url: src), src.lastPathComponent)
            for target in ConversionRules.targets(for: from) {
                let start = Date()
                do {
                    let out = try await Converter.convertOne(src, to: target, into: dir)
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    XCTAssertTrue(try valid(out, as: target), "\(from.label) → \(target.label) made a broken file")
                    print("OK  \(from.label) → \(target.label)  \(ms) ms")
                } catch {
                    XCTFail("\(from.label) → \(target.label) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func valid(_ url: URL, as f: FileFormat) throws -> Bool {
        switch f.family {
        case .text:
            return (try String(contentsOf: url, encoding: .utf8)).contains("Hello FileWheel")
        case .image:
            guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let t = CGImageSourceGetType(s) else { return false }
            return UTType(t as String)?.conforms(to: f.type) == true && CGImageSourceCreateImageAtIndex(s, 0, nil) != nil
        case .pdf:
            return (PDFDocument(url: url)?.pageCount ?? 0) > 0
        case .audio:
            return try AVAudioFile(forReading: url).length > 0
        case .video:
            let asset = AVURLAsset(url: url)
            let tracks = try awaitSync { try await asset.loadTracks(withMediaType: .video) }
            return !tracks.isEmpty
        }
    }

    private func awaitSync<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>!
        Task { do { result = .success(try await op()) } catch { result = .failure(error) }; sem.signal() }
        sem.wait()
        return try result.get()
    }

    // MARK: sample files

    private func makePNG() throws -> URL {
        let url = dir.appendingPathComponent("sample.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.orange.setFill(); NSRect(x: 8, y: 8, width: 40, height: 30).fill()
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func makeTextPDF() throws -> URL {
        let url = dir.appendingPathComponent("doc.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("Hello FileWheel" as NSString).draw(at: CGPoint(x: 20, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage(); ctx.closePDF()
        return url
    }

    private func makeWAV() throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 22050)!
        buf.frameLength = 22050
        for c in 0..<2 { for i in 0..<22050 { buf.floatChannelData![c][i] = sin(Float(i) * 0.06) * 0.4 } }
        do { try AVAudioFile(forWriting: url, settings: fmt.settings).write(from: buf) }
        return url
    }

    /// A one-second movie with picture and sound, written frame by frame.
    private func makeMovie() async throws -> URL {
        let url = dir.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: v, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
        writer.add(v); writer.add(a)
        writer.startWriting(); writer.startSession(atSourceTime: .zero)

        for i in 0..<30 {
            while !v.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            CVPixelBufferLockBaseAddress(pb!, [])
            memset(CVPixelBufferGetBaseAddress(pb!), Int32(i * 8), CVPixelBufferGetDataSize(pb!))
            CVPixelBufferUnlockBaseAddress(pb!, [])
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        v.markAsFinished()

        // One second of tone as 16-bit PCM sample buffers.
        var asbd = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var fmtDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmtDesc)
        for chunk in 0..<10 {
            while !a.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            let n = 4410
            var samples = (0..<n).map { Int16(sin(Double(chunk * n + $0) * 0.05) * 8000) }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n * 2, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: n * 2, flags: 0, blockBufferOut: &block)
            CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: block!, offsetIntoDestination: 0, dataLength: n * 2)
            var sb: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: fmtDesc!,
                sampleCount: n, presentationTimeStamp: CMTime(value: CMTimeValue(chunk * n), timescale: 44100),
                packetDescriptions: nil, sampleBufferOut: &sb)
            a.append(sb!)
        }
        a.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }
}
