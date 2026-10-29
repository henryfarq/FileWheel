import Foundation
import UniformTypeIdentifiers

/// One file type that can show up as a slice on the wheel.
public struct FileFormat: Hashable, Sendable {
    public let label: String
    public let ext: String
    public let type: UTType

    public static let png = FileFormat(label: "PNG", ext: "png", type: .png)
    public static let jpeg = FileFormat(label: "JPG", ext: "jpg", type: .jpeg)
    public static let heic = FileFormat(label: "HEIC", ext: "heic", type: .heic)
    public static let tiff = FileFormat(label: "TIFF", ext: "tiff", type: .tiff)
    public static let gif = FileFormat(label: "GIF", ext: "gif", type: .gif)
    public static let bmp = FileFormat(label: "BMP", ext: "bmp", type: .bmp)
    public static let pdf = FileFormat(label: "PDF", ext: "pdf", type: .pdf)
    public static let txt = FileFormat(label: "TXT", ext: "txt", type: .plainText)
    public static let mov = FileFormat(label: "MOV", ext: "mov", type: .quickTimeMovie)
    public static let mp4 = FileFormat(label: "MP4", ext: "mp4", type: .mpeg4Movie)
    public static let m4v = FileFormat(label: "M4V", ext: "m4v", type: UTType("com.apple.m4v-video") ?? .movie)
    public static let m4a = FileFormat(label: "M4A", ext: "m4a", type: .mpeg4Audio)
    public static let wav = FileFormat(label: "WAV", ext: "wav", type: .wav)
    public static let aiff = FileFormat(label: "AIFF", ext: "aiff", type: .aiff)
    public static let caf = FileFormat(label: "CAF", ext: "caf", type: UTType("com.apple.coreaudio-format") ?? .audio)

    public enum Family: Sendable { case image, pdf, video, audio, text }

    public var family: Family {
        if self == .pdf { return .pdf }
        if self == .txt { return .text }
        if [.mov, .mp4, .m4v].contains(self) { return .video }
        if [.m4a, .wav, .aiff, .caf].contains(self) { return .audio }
        return .image
    }

    static let all: [FileFormat] = [.png, .jpeg, .heic, .tiff, .gif, .bmp, .pdf, .txt,
                                    .mov, .mp4, .m4v, .m4a, .wav, .aiff, .caf]

    /// Works out what a file on disk is, from its extension.
    public static func detect(url: URL) -> FileFormat? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpeg": return .jpeg
        case "tif": return .tiff
        case "aif": return .aiff
        default: return all.first { $0.ext == ext && $0 != .txt }
        }
    }
}

/// The single rulebook: which file types may be turned into which.
public enum ConversionRules {
    private static let rasterImages: [FileFormat] = [.png, .jpeg, .heic, .tiff, .gif, .bmp]

    /// Slices to show on the wheel, in clockwise order from 12 o'clock.
    public static func targets(for source: FileFormat) -> [FileFormat] {
        switch source.family {
        case .image:
            return (rasterImages.filter { $0 != source }) + [.pdf]
        case .pdf:
            return [.png, .jpeg, .tiff, .txt]
        case .video:
            return ([.mov, .mp4, .m4v].filter { $0 != source }) + [.m4a]
        case .audio:
            return [.m4a, .wav, .aiff, .caf].filter { $0 != source }
        case .text:
            return []   // text is only ever an output (from PDF), never a source
        }
    }

    public static func canConvert(_ source: FileFormat, to target: FileFormat) -> Bool {
        targets(for: source).contains(target)
    }

    /// Something worth telling the user before converting, if any.
    public static func warning(from source: FileFormat, to target: FileFormat) -> String? {
        if target == .jpeg && [.png, .gif, .heic, .tiff].contains(source) {
            return "Transparent areas become white in a JPG."
        }
        if target == .gif && source != .gif { return "GIF only keeps 256 colours." }
        return nil
    }
}
