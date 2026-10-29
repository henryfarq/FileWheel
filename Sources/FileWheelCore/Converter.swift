import Foundation
import ImageIO
import PDFKit
import AVFoundation
import AppKit

public enum ConversionError: LocalizedError {
    case unsupported, unreadable, writeFailed(String)
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "That conversion isn't supported."
        case .unreadable: return "Couldn't open the file."
        case .writeFailed(let m): return "Couldn't save the new file. \(m)"
        }
    }

    /// A few words that fit inside the wheel's centre circle.
    public static func shortReason(_ error: Error) -> String {
        switch error as? ConversionError {
        case .unsupported: return "Not supported"
        case .unreadable: return "Can't open file"
        case .writeFailed: return "Couldn't save"
        case nil: return "Couldn't convert"
        }
    }
}

public enum Converter {
    /// Picks a name that doesn't clash: "photo.jpg", then "photo 2.jpg", "photo 3.jpg"...
    public static func uniqueURL(base: String, ext: String, in folder: URL,
                                 exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        var url = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    /// Names picked by conversions that haven't saved their file yet. Two conversions running at once
    /// (say the same video, twice) would otherwise both pick "clip.mp4", and the second would fail to save.
    private static let claimLock = NSLock()
    nonisolated(unsafe) private static var claimed: Set<String> = []

    private static func claimURL(base: String, ext: String, in folder: URL) -> URL {
        claimLock.lock(); defer { claimLock.unlock() }
        let url = uniqueURL(base: base, ext: ext, in: folder) {
            claimed.contains($0.path) || FileManager.default.fileExists(atPath: $0.path)
        }
        claimed.insert(url.path)
        return url
    }

    private static func release(_ url: URL) {
        claimLock.lock(); defer { claimLock.unlock() }
        claimed.remove(url.path)
    }

    /// Runs one save into a freshly claimed name. If it fails, any half-written file is cleared away
    /// so a broken copy is never left on the Desktop.
    private static func saving(_ out: URL, _ work: () async throws -> Void) async throws {
        defer { release(out) }
        do { try await work() }
        catch { try? FileManager.default.removeItem(at: out); throw error }
    }

    /// How far a conversion has got, from 0 to 1. Only slow kinds (video, audio, multi-page PDF) report it.
    public typealias Progress = @Sendable (Double) -> Void

    /// Converts `source` into `target` and saves the copy (or copies) in `folder`. The original is never touched.
    /// Usually one file comes back; a PDF with several pages gives one image per page.
    public static func convert(_ source: URL, to target: FileFormat, into folder: URL,
                               progress: Progress? = nil) async throws -> [URL] {
        let outs = try await run(source, to: target, into: folder, progress: progress)
        outs.forEach(tagAsConverted)
        return outs
    }

    /// Hidden label on every file FileWheel makes, so other apps (like Screen Line) can tell
    /// a converted copy apart from a brand-new screenshot or screen recording.
    public static let convertedTag = "com.henry.filewheel.converted"

    public static func tagAsConverted(_ url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path in
            setxattr(path, convertedTag, "1", 1, 0, 0)
        }
    }

    private static func run(_ source: URL, to target: FileFormat, into folder: URL,
                            progress: Progress?) async throws -> [URL] {
        guard let from = FileFormat.detect(url: source), ConversionRules.canConvert(from, to: target) else {
            throw ConversionError.unsupported
        }
        let base = source.deletingPathExtension().lastPathComponent
        if from.family == .pdf, target.family == .image {
            return try await pdfToImages(source, base: base, folder: folder, target, progress)
        }
        let out = claimURL(base: base, ext: target.ext, in: folder)
        try await saving(out) {
            switch (from.family, target.family) {
            case (.image, .image): try imageToImage(source, out, target)
            case (.image, .pdf): try imageToPDF(source, out)
            case (.pdf, .text): try pdfToText(source, out)
            case (.video, .video):
                try await export(source, out, preset: AVAssetExportPresetHighestQuality, type: avType(target), progress)
            case (.video, .audio), (.audio, .audio) where target == .m4a:
                try await export(source, out, preset: AVAssetExportPresetAppleM4A, type: .m4a, progress)
            case (.audio, .audio): try audioToPCM(source, out, target, progress)
            default: throw ConversionError.unsupported
            }
        }
        return [out]
    }

    // MARK: images

    private static func loadImage(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ConversionError.unreadable }
        return img
    }

    private static func flattenedOnWhite(_ img: CGImage) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return img }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage() ?? img
    }

    private static func write(_ img: CGImage, to out: URL, as target: FileFormat) throws {
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, target.type.identifier as CFString, 1, nil)
        else { throw ConversionError.writeFailed("This Mac can't write \(target.label) files.") }
        let image = (target == .jpeg || target == .bmp) ? flattenedOnWhite(img) : img
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(dest, image, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConversionError.writeFailed("") }
    }

    private static func imageToImage(_ s: URL, _ o: URL, _ t: FileFormat) throws { try write(loadImage(s), to: o, as: t) }

    private static func imageToPDF(_ s: URL, _ o: URL) throws {
        guard let img = NSImage(contentsOf: s), let page = PDFPage(image: img) else { throw ConversionError.unreadable }
        let doc = PDFDocument(); doc.insert(page, at: 0)
        guard doc.write(to: o) else { throw ConversionError.writeFailed("") }
    }

    // MARK: PDF

    /// One image per page: "doc.png" for a single page, "doc page 1.png", "doc page 2.png"... for more.
    private static func pdfToImages(_ s: URL, base: String, folder: URL, _ t: FileFormat,
                                    _ progress: Progress?) async throws -> [URL] {
        guard let doc = PDFDocument(url: s), doc.pageCount > 0 else { throw ConversionError.unreadable }
        var outs: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let name = doc.pageCount == 1 ? base : "\(base) page \(i + 1)"
            let out = claimURL(base: name, ext: t.ext, in: folder)
            try await saving(out) {
                let box = page.bounds(for: .mediaBox), scale: CGFloat = 2
                let thumb = page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
                guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ConversionError.unreadable }
                try write(cg, to: out, as: t)
            }
            outs.append(out)
            progress?(Double(i + 1) / Double(doc.pageCount))
        }
        return outs
    }

    private static func pdfToText(_ s: URL, _ o: URL) throws {
        guard let text = PDFDocument(url: s)?.string else { throw ConversionError.unreadable }
        do { try text.write(to: o, atomically: true, encoding: .utf8) }
        catch { throw ConversionError.writeFailed(error.localizedDescription) }
    }

    // MARK: audio / video

    private static func avType(_ f: FileFormat) -> AVFileType {
        switch f {
        case .mp4: return .mp4
        case .m4v: return .m4v
        case .m4a: return .m4a
        case .wav: return .wav
        case .aiff: return .aiff
        case .caf: return .caf
        default: return .mov
        }
    }

    private static func export(_ s: URL, _ o: URL, preset: String, type: AVFileType, _ progress: Progress?) async throws {
        let asset = AVURLAsset(url: s)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ConversionError.unsupported }
        // Watch the export alongside it so the wheel can fill its progress ring.
        let watcher = Task {
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let p) = state { progress?(p.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do { try await session.export(to: o, as: type) }
        catch { throw ConversionError.writeFailed(error.localizedDescription) }
    }

    private static func audioToPCM(_ s: URL, _ o: URL, _ t: FileFormat, _ progress: Progress?) throws {
        let input = try AVAudioFile(forReading: s)
        let format = input.processingFormat
        var settings = format.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = (t == .aiff)
        let output = try AVAudioFile(forWriting: o, settings: settings, commonFormat: format.commonFormat,
                                     interleaved: format.isInterleaved)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else { throw ConversionError.unreadable }
        while input.framePosition < input.length {
            try input.read(into: buf)
            if buf.frameLength == 0 { break }
            try output.write(from: buf)
            progress?(Double(input.framePosition) / Double(max(input.length, 1)))
        }
    }
}
