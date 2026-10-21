import Foundation

public enum FileCategory: String, Sendable {
    case image = "Image"
    case audio = "Audio"
    case video = "Video"
    case document = "Document"
    case spreadsheet = "Spreadsheet"
    case archive = "Archive"
    case subtitle = "Subtitle"
    case other = "Other"
}

public struct ConversionMatrix {
    public static let imageFormats = ["jpg", "jpeg", "png", "webp", "heic", "tiff", "svg", "avif", "bmp"]
    // Put PDF and PNG at the front so PDF is immediately visible and prominent
    public static let imageExportFormats = ["pdf", "png", "jpg", "webp", "heic", "tiff", "bmp"]
    
    public static let audioFormats = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    public static let videoFormats = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
    public static let documentFormats = ["docx", "pages", "md", "rtf", "rtfd", "txt", "textclipping"]
    public static let documentExportFormats = ["pdf", "docx", "txt", "md", "html", "epub", "png", "jpg"]
    public static let spreadsheetFormats = ["xlsx", "xls", "ods", "csv", "tsv"]
    public static let subtitleFormats = ["srt", "vtt"]
    public static let archiveFormats = ["zip", "tar", "gz", "rar", "tgz"]

    public static func category(for ext: String) -> FileCategory {
        let e = ext.lowercased()
        if imageFormats.contains(e) { return .image }
        if audioFormats.contains(e) { return .audio }
        if videoFormats.contains(e) || e == "gif" { return .video }
        if e == "pdf" || documentFormats.contains(e) || e == "epub" || e == "ppt" || e == "pptx" { return .document }
        if spreadsheetFormats.contains(e) { return .spreadsheet }
        if archiveFormats.contains(e) { return .archive }
        if subtitleFormats.contains(e) { return .subtitle }
        return .other
    }

    public static func conversions(for ext: String) -> [String] {
        let e = ext.lowercased()
        var targets: [String] = []

        if imageFormats.contains(e) {
            targets = imageExportFormats
        } else if audioFormats.contains(e) {
            targets = ["mp3", "m4a", "wav", "flac", "aiff"]
        } else if videoFormats.contains(e) {
            targets = ["mp4", "mov", "webm", "gif", "mp3"]
        } else if e == "gif" {
            targets = ["mp4", "mov", "png", "webp", "pdf"]
        } else if e == "pdf" {
            targets = ["docx", "jpg", "png", "txt", "md"]
        } else if ["ppt", "pptx"].contains(e) {
            targets = ["pdf", "jpg", "png"]
        } else if spreadsheetFormats.contains(e) {
            targets = ["pdf", "xlsx", "csv"]
        } else if documentFormats.contains(e) {
            targets = ["pdf", "docx", "txt", "md", "html"]
        } else if e == "epub" {
            targets = ["pdf", "txt", "md"]
        } else if subtitleFormats.contains(e) {
            targets = ["srt", "vtt", "txt"]
        } else if archiveFormats.contains(e) {
            targets = ["zip", "tar", "gz"]
        }

        // Return distinct targets excluding current extension
        return targets.filter { $0 != e }
    }

    public static func tools(for ext: String, fileCount: Int = 1) -> [String] {
        let e = ext.lowercased()
        if imageFormats.contains(e) && e != "svg" {
            if fileCount > 1 {
                return ["createPDF", "resizeImage", "compress", "removeMetadata"]
            }
            return ["cropImage", "resizeImage", "createPDF", "compress", "removeMetadata"]
        } else if audioFormats.contains(e) {
            return ["compress", "removeMetadata", "normalizeAudio", "trimAudio"]
        } else if videoFormats.contains(e) {
            if fileCount > 1 {
                return ["joinVideos", "compress", "muteVideo"]
            }
            return ["muteVideo", "videoSnapshots", "trimVideo", "changeVideoSpeed", "compress", "removeMetadata"]
        } else if e == "pdf" {
            if fileCount > 1 {
                return ["mergePDF", "resizeImage", "compress", "removeMetadata", "splitPDF"]
            }
            return ["splitPDF", "resizeImage", "organizePDF", "compress", "removeMetadata"]
        } else if archiveFormats.contains(e) {
            return ["extractArchive"]
        }
        return ["compress", "removeMetadata"]
    }

    public static let allActions: [String] = [
        "airDrop", "float", "copy", "move", "copyPath", "openTerminal"
    ]
}
