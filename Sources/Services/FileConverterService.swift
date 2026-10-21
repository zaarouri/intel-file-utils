import Foundation
import AppKit
import ImageIO
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers
import PDFKit
import AVFoundation

public enum ConversionError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotFound(URL)
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fmt):
            return "Format '\(fmt)' is not supported."
        case .fileNotFound(let url):
            return "File not found at \(url.path)."
        case .conversionFailed(let reason):
            return "Conversion failed: \(reason)"
        }
    }
}

public final class FileConverterService: @unchecked Sendable {
    public static let shared = FileConverterService()

    private init() {}

    public func convert(file url: URL, to targetExt: String) async throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConversionError.fileNotFound(url)
        }

        let ext = targetExt.lowercased()
        let srcExt = url.pathExtension.lowercased()
        
        let outputDir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let outputURL = uniqueOutputURL(directory: outputDir, baseName: baseName, ext: ext)

        // 1. Image conversions
        if ConversionMatrix.imageFormats.contains(srcExt) {
            if ext == "pdf" {
                return try convertImageToPDF(source: url, destination: outputURL)
            } else if ext == "webp" || ext == "avif" {
                return try convertWithPythonPillow(source: url, destination: outputURL)
            } else {
                do {
                    return try convertImageNative(source: url, to: ext, destination: outputURL)
                } catch {
                    // Fallback to Python Pillow
                    return try convertWithPythonPillow(source: url, destination: outputURL)
                }
            }
        }

        // 2. PDF conversions
        if srcExt == "pdf" {
            if ["jpg", "jpeg", "png", "tiff"].contains(ext) {
                return try convertPDFToImages(source: url, format: ext)
            } else if ["txt", "md"].contains(ext) {
                return try convertPDFToText(source: url, destination: outputURL, markdown: ext == "md")
            } else if ext == "docx" {
                return try convertPDFToDocx(source: url, destination: outputURL)
            }
        }

        // 3. Audio & Video conversions
        if ConversionMatrix.videoFormats.contains(srcExt) || ConversionMatrix.audioFormats.contains(srcExt) {
            if ext == "mp3" || ext == "m4a" || ext == "wav" {
                return try await extractAudio(from: url, to: ext, destination: outputURL)
            } else if ConversionMatrix.videoFormats.contains(ext) {
                return try await convertVideo(source: url, to: ext, destination: outputURL)
            }
        }

        // 4. Document conversions via textutil
        if ConversionMatrix.documentFormats.contains(srcExt) {
            return try convertDocumentWithTextutil(source: url, destination: outputURL, targetExt: ext)
        }

        // 5. Fallback via python or sips
        do {
            return try convertWithPythonPillow(source: url, destination: outputURL)
        } catch {
            return try convertWithSips(source: url, destination: outputURL, targetFormat: ext)
        }
    }

    // MARK: - Native Image Conversion (ImageIO)
    private func convertImageNative(source: URL, to targetExt: String, destination: URL) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.conversionFailed("Could not load image data with ImageIO")
        }

        return try saveCGImage(cgImage, to: destination)
    }

    // MARK: - Python Pillow Conversion (WebP, AVIF, and advanced formats)
    public func convertWithPythonPillow(source: URL, destination: URL) throws -> URL {
        let script = """
        from PIL import Image
        import sys
        try:
            img = Image.open(sys.argv[1])
            target_ext = sys.argv[2].lower()
            if target_ext in ['jpg', 'jpeg'] and img.mode in ('RGBA', 'LA', 'P'):
                img = img.convert('RGB')
            img.save(sys.argv[3], quality=85)
            sys.exit(0)
        except Exception as e:
            print(e, file=sys.stderr)
            sys.exit(1)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script, source.path, destination.pathExtension, destination.path]
        var env = ProcessInfo.processInfo.environment
        let curPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/anaconda3/bin:/usr/local/bin:/usr/bin:/bin:\(curPath)"
        process.environment = env

        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination.path) {
            return destination
        } else {
            let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown Python error"
            throw ConversionError.conversionFailed("Pillow conversion failed: \(errMsg)")
        }
    }

    // MARK: - Image to PDF (High Performance & Clean CoreGraphics Rendering)
    public func createPDFFromImages(sources: [URL], destination: URL) throws -> URL {
        guard !sources.isEmpty else {
            throw ConversionError.conversionFailed("No image files provided for PDF creation")
        }

        guard let consumer = CGDataConsumer(url: destination as CFURL) else {
            throw ConversionError.conversionFailed("Unable to create PDF consumer at \(destination.path)")
        }

        guard let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ConversionError.conversionFailed("Unable to initialize PDF context")
        }

        var pageCount = 0
        for src in sources {
            guard let imageSource = CGImageSourceCreateWithURL(src as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                if let nsImage = NSImage(contentsOf: src),
                   let tiffData = nsImage.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiffData),
                   let cgImg = rep.cgImage {
                    var box = CGRect(x: 0, y: 0, width: CGFloat(cgImg.width), height: CGFloat(cgImg.height))
                    pdfContext.beginPage(mediaBox: &box)
                    pdfContext.draw(cgImg, in: box)
                    pdfContext.endPage()
                    pageCount += 1
                }
                continue
            }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            guard width > 0 && height > 0 else { continue }

            var box = CGRect(x: 0, y: 0, width: width, height: height)
            pdfContext.beginPage(mediaBox: &box)
            pdfContext.draw(cgImage, in: box)
            pdfContext.endPage()
            pageCount += 1
        }

        pdfContext.closePDF()

        guard pageCount > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw ConversionError.conversionFailed("Could not render any pages from the selected image(s).")
        }

        return destination
    }

    public func convertImageToPDF(source: URL, destination: URL) throws -> URL {
        return try createPDFFromImages(sources: [source], destination: destination)
    }

    // MARK: - Advanced Image Tools (Resize, Crop, Frame, Edit, Collage)

    public func resizeImage(source: URL, scale: Double = 0.5, maxDimension: Int? = 1920) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.conversionFailed("Could not read image for resizing")
        }

        let w = cgImage.width
        let h = cgImage.height
        var targetW = max(1, Int(Double(w) * scale))
        var targetH = max(1, Int(Double(h) * scale))

        if let maxDim = maxDimension, (targetW > maxDim || targetH > maxDim) {
            let ratio = min(Double(maxDim) / Double(w), Double(maxDim) / Double(h))
            targetW = max(1, Int(Double(w) * ratio))
            targetH = max(1, Int(Double(h) * ratio))
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: targetW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ConversionError.conversionFailed("Could not create drawing context for resize")
        }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        guard let resizedCG = ctx.makeImage() else {
            throw ConversionError.conversionFailed("Failed to render resized image")
        }

        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(
            directory: source.deletingLastPathComponent(),
            baseName: "\(source.deletingPathExtension().lastPathComponent) Resized",
            ext: ext
        )

        return try saveCGImage(resizedCG, to: outURL)
    }

    public func cropImage(source: URL) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.conversionFailed("Could not read image for crop")
        }

        let w = cgImage.width
        let h = cgImage.height
        let side = min(w, h)
        let cropRect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)

        guard let croppedCG = cgImage.cropping(to: cropRect) else {
            throw ConversionError.conversionFailed("Failed to crop image")
        }

        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(
            directory: source.deletingLastPathComponent(),
            baseName: "\(source.deletingPathExtension().lastPathComponent) Cropped",
            ext: ext
        )

        return try saveCGImage(croppedCG, to: outURL)
    }

    public func editImage(source: URL) throws -> URL {
        guard let ciImg = CIImage(contentsOf: source) else {
            throw ConversionError.conversionFailed("Could not read image for editing")
        }

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImg, forKey: kCIInputImageKey)
        filter?.setValue(1.10, forKey: kCIInputContrastKey)
        filter?.setValue(1.15, forKey: kCIInputSaturationKey)

        guard let outputCI = filter?.outputImage else {
            throw ConversionError.conversionFailed("Failed to apply color adjustments")
        }

        let ciContext = CIContext()
        guard let outputCG = ciContext.createCGImage(outputCI, from: outputCI.extent) else {
            throw ConversionError.conversionFailed("Failed to render edited image")
        }

        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(
            directory: source.deletingLastPathComponent(),
            baseName: "\(source.deletingPathExtension().lastPathComponent) Enhanced",
            ext: ext
        )

        return try saveCGImage(outputCG, to: outURL)
    }

    public func saveCGImage(_ cgImage: CGImage, to destination: URL, quality: Int = 85) throws -> URL {
        let ext = destination.pathExtension.lowercased()
        if ext == "webp" {
            return try saveCGImageAsWebP(cgImage, to: destination, quality: quality)
        }

        let uti: CFString
        switch ext {
        case "jpg", "jpeg":
            uti = UTType.jpeg.identifier as CFString
        case "heic":
            uti = UTType.heic.identifier as CFString
        case "tiff":
            uti = UTType.tiff.identifier as CFString
        case "bmp":
            uti = UTType.bmp.identifier as CFString
        default:
            uti = UTType.png.identifier as CFString
        }

        guard let destRef = CGImageDestinationCreateWithURL(destination as CFURL, uti, 1, nil) else {
            throw ConversionError.conversionFailed("Could not create image destination for \(destination.path)")
        }

        CGImageDestinationAddImage(destRef, cgImage, nil)
        guard CGImageDestinationFinalize(destRef) else {
            throw ConversionError.conversionFailed("Failed to write image data to \(destination.path)")
        }
        return destination
    }

    public func saveCGImageAsWebP(_ cgImage: CGImage, to destination: URL, quality: Int = 85) throws -> URL {
        let tempPNG = destination.deletingPathExtension().appendingPathExtension("temp_\(UUID().uuidString.prefix(6)).png")
        let uti = UTType.png.identifier as CFString
        guard let destRef = CGImageDestinationCreateWithURL(tempPNG as CFURL, uti, 1, nil) else {
            throw ConversionError.conversionFailed("Could not create temp PNG for WebP export")
        }
        CGImageDestinationAddImage(destRef, cgImage, nil)
        guard CGImageDestinationFinalize(destRef) else {
            throw ConversionError.conversionFailed("Failed to finalize temp PNG for WebP")
        }
        defer { try? FileManager.default.removeItem(at: tempPNG) }

        let script = """
        from PIL import Image
        import sys
        try:
            im = Image.open(sys.argv[1])
            im.save(sys.argv[2], 'WEBP', quality=\(quality))
        except Exception as e:
            sys.exit(1)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script, tempPNG.path, destination.path]
        var env = ProcessInfo.processInfo.environment
        let curPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/anaconda3/bin:/usr/local/bin:/usr/bin:/bin:\(curPath)"
        process.environment = env
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination.path) else {
            throw ConversionError.conversionFailed("WebP conversion failed via Pillow")
        }
        return destination
    }

    // MARK: - Advanced Audio & Video Tools

    public func normalizeAudio(source: URL) throws -> URL {
        let ext = source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(directory: source.deletingLastPathComponent(), baseName: "\(source.deletingPathExtension().lastPathComponent) Normalized", ext: ext)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-d", "aac", source.path, outURL.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outURL.path) {
            return outURL
        }
        try FileManager.default.copyItem(at: source, to: outURL)
        return outURL
    }

    public func trimAudio(source: URL) async throws -> URL {
        let ext = source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(directory: source.deletingLastPathComponent(), baseName: "\(source.deletingPathExtension().lastPathComponent) Trimmed", ext: ext)

        let asset = AVURLAsset(url: source)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ConversionError.conversionFailed("Cannot create trim session")
        }

        let duration = try await asset.load(.duration)
        let trimSeconds = min(30.0, CMTimeGetSeconds(duration) * 0.8)
        exportSession.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: trimSeconds, preferredTimescale: 600))
        exportSession.outputURL = outURL
        exportSession.outputFileType = .m4a
        await exportSession.export()

        if exportSession.status == .completed {
            return outURL
        } else {
            throw ConversionError.conversionFailed(exportSession.error?.localizedDescription ?? "Trim failed")
        }
    }

    public func trimVideo(source: URL) async throws -> URL {
        let ext = source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(directory: source.deletingLastPathComponent(), baseName: "\(source.deletingPathExtension().lastPathComponent) Trimmed", ext: ext)

        let asset = AVURLAsset(url: source)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConversionError.conversionFailed("Cannot create video export session")
        }

        let duration = try await asset.load(.duration)
        let trimSeconds = min(30.0, CMTimeGetSeconds(duration) * 0.8)
        exportSession.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: trimSeconds, preferredTimescale: 600))
        exportSession.outputURL = outURL
        exportSession.outputFileType = ext == "mov" ? .mov : .mp4
        await exportSession.export()

        if exportSession.status == .completed {
            return outURL
        } else {
            throw ConversionError.conversionFailed(exportSession.error?.localizedDescription ?? "Video trim failed")
        }
    }

    public func changeVideoSpeed(source: URL, rate: Float = 2.0) async throws -> URL {
        let ext = source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(directory: source.deletingLastPathComponent(), baseName: "\(source.deletingPathExtension().lastPathComponent) 2x Speed", ext: ext)

        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.conversionFailed("No video track found")
        }
        let duration = try await asset.load(.duration)
        let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compVideoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)

        let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / Double(rate))
        compVideoTrack?.scaleTimeRange(CMTimeRange(start: .zero, duration: duration), toDuration: scaledDuration)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConversionError.conversionFailed("Export session failed")
        }
        exportSession.outputURL = outURL
        exportSession.outputFileType = ext == "mov" ? .mov : .mp4
        await exportSession.export()

        if exportSession.status == .completed {
            return outURL
        } else {
            throw ConversionError.conversionFailed(exportSession.error?.localizedDescription ?? "Speed change failed")
        }
    }

    public func joinVideos(sources: [URL]) async throws -> URL {
        guard sources.count >= 2 else {
            throw ConversionError.conversionFailed("At least 2 videos are required to join")
        }

        let composition = AVMutableComposition()
        let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var currentTime = CMTime.zero

        for src in sources {
            let asset = AVURLAsset(url: src)
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
               let dur = try? await asset.load(.duration) {
                try? compTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: videoTrack, at: currentTime)
                currentTime = CMTimeAdd(currentTime, dur)
            }
        }

        let dir = sources[0].deletingLastPathComponent()
        let firstBase = sources[0].deletingPathExtension().lastPathComponent
        let outURL = uniqueOutputURL(directory: dir, baseName: "\(firstBase) Joined", ext: "mp4")

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConversionError.conversionFailed("Cannot create join export session")
        }
        exportSession.outputURL = outURL
        exportSession.outputFileType = .mp4
        await exportSession.export()

        if exportSession.status == .completed {
            return outURL
        } else {
            throw ConversionError.conversionFailed(exportSession.error?.localizedDescription ?? "Join videos failed")
        }
    }

    public func organizePDF(source: URL) throws -> URL {
        guard let pdfDoc = PDFDocument(url: source) else {
            throw ConversionError.conversionFailed("Could not open PDF")
        }

        for i in 0..<pdfDoc.pageCount {
            if let page = pdfDoc.page(at: i) {
                page.rotation = (page.rotation + 90) % 360
            }
        }

        let outURL = uniqueOutputURL(
            directory: source.deletingLastPathComponent(),
            baseName: "\(source.deletingPathExtension().lastPathComponent) Rotated",
            ext: "pdf"
        )
        guard pdfDoc.write(to: outURL) else {
            throw ConversionError.conversionFailed("Failed to save rotated PDF")
        }
        return outURL
    }

    // MARK: - PDF Operations
    public func mergePDFs(sources: [URL], destination: URL) throws -> URL {
        guard !sources.isEmpty else {
            throw ConversionError.conversionFailed("No PDF files provided to merge")
        }
        let mergedDoc = PDFDocument()
        var totalPages = 0
        for src in sources {
            guard let doc = PDFDocument(url: src) else { continue }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) {
                    mergedDoc.insert(page, at: totalPages)
                    totalPages += 1
                }
            }
        }
        guard totalPages > 0 else {
            throw ConversionError.conversionFailed("No readable pages in selected PDFs")
        }
        guard mergedDoc.write(to: destination) else {
            throw ConversionError.conversionFailed("Failed to save merged PDF")
        }
        return destination
    }

    public func splitPDF(source: URL) throws -> URL {
        guard let pdfDoc = PDFDocument(url: source) else {
            throw ConversionError.conversionFailed("Could not open PDF at \(source.path)")
        }
        let folderName = "\(source.deletingPathExtension().lastPathComponent) Pages"
        let outputFolder = uniqueOutputFolder(directory: source.deletingLastPathComponent(), name: folderName)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let pageCount = pdfDoc.pageCount
        for i in 0..<pageCount {
            if let page = pdfDoc.page(at: i) {
                let singleDoc = PDFDocument()
                singleDoc.insert(page, at: 0)
                let pageNum = String(format: "%02d", i + 1)
                let pageURL = outputFolder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) Page \(pageNum).pdf")
                singleDoc.write(to: pageURL)
            }
        }
        return outputFolder
    }

    private func convertPDFToImages(source: URL, format: String) throws -> URL {
        guard let pdfDoc = PDFDocument(url: source) else {
            throw ConversionError.conversionFailed("Could not read PDF")
        }

        let folderName = "\(source.deletingPathExtension().lastPathComponent) Images"
        let outputFolder = uniqueOutputFolder(directory: source.deletingLastPathComponent(), name: folderName)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let uti: CFString = format == "png" ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString
        let ext = format == "png" ? "png" : "jpg"

        for i in 0..<pdfDoc.pageCount {
            guard let page = pdfDoc.page(at: i) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            let image = NSImage(size: pageRect.size)
            image.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(pageRect)
                page.draw(with: .mediaBox, to: ctx)
            }
            image.unlockFocus()

            if let tiffData = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiffData),
               let cgImage = rep.cgImage {
                let pageNum = String(format: "%02d", i + 1)
                let fileURL = outputFolder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) \(pageNum).\(ext)")
                if let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, uti, 1, nil) {
                    CGImageDestinationAddImage(dest, cgImage, nil)
                    CGImageDestinationFinalize(dest)
                }
            }
        }

        return outputFolder
    }

    private func convertPDFToText(source: URL, destination: URL, markdown: Bool) throws -> URL {
        guard let pdfDoc = PDFDocument(url: source) else {
            throw ConversionError.conversionFailed("Cannot open PDF")
        }

        var fullText = ""
        for i in 0..<pdfDoc.pageCount {
            if let page = pdfDoc.page(at: i), let pageStr = page.string {
                if markdown {
                    fullText += "\n\n## Page \(i + 1)\n\n" + pageStr
                } else {
                    fullText += "\n--- Page \(i + 1) ---\n" + pageStr
                }
            }
        }

        try fullText.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    private func convertPDFToDocx(source: URL, destination: URL) throws -> URL {
        let txtURL = destination.deletingPathExtension().appendingPathExtension("txt")
        _ = try convertPDFToText(source: source, destination: txtURL, markdown: false)
        return try convertDocumentWithTextutil(source: txtURL, destination: destination, targetExt: "docx")
    }

    // MARK: - Audio & Video Conversions
    private func extractAudio(from source: URL, to format: String, destination: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ConversionError.conversionFailed("Cannot create audio export session")
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = format == "m4a" ? .m4a : .mp4
        await exportSession.export()

        if exportSession.status == .completed {
            return destination
        } else {
            return try await convertAudioWithFfmpegOrSoff(source: source, destination: destination)
        }
    }

    private func convertAudioWithFfmpegOrSoff(source: URL, destination: URL) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "m4af", "-d", "aac", source.path, destination.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return destination
        }
        throw ConversionError.conversionFailed("Audio export failed")
    }

    private func convertVideo(source: URL, to format: String, destination: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConversionError.conversionFailed("Video export session could not be created")
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = format == "mov" ? .mov : .mp4
        await exportSession.export()

        if exportSession.status == .completed {
            return destination
        } else {
            throw ConversionError.conversionFailed(exportSession.error?.localizedDescription ?? "Video conversion failed")
        }
    }

    public func muteVideo(source: URL) async throws -> URL {
        let ext = source.pathExtension
        let outputURL = uniqueOutputURL(directory: source.deletingLastPathComponent(), baseName: "\(source.deletingPathExtension().lastPathComponent) Muted", ext: ext)

        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.conversionFailed("No video track found")
        }
        let duration = try await asset.load(.duration)
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compositionVideoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConversionError.conversionFailed("Export session failed")
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = ext.lowercased() == "mov" ? .mov : .mp4
        await exportSession.export()

        if exportSession.status == .completed {
            return outputURL
        } else {
            throw ConversionError.conversionFailed(exportSession.error?.localizedDescription ?? "Muting failed")
        }
    }

    public func extractVideoSnapshots(source: URL, count: Int = 5) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        
        let folder = uniqueOutputFolder(directory: source.deletingLastPathComponent(), name: "\(source.deletingPathExtension().lastPathComponent) Snapshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let step = seconds / Double(count + 1)
        for i in 1...count {
            let time = CMTime(seconds: step * Double(i), preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: time) {
                let outURL = folder.appendingPathComponent(String(format: "Snapshot %02d.png", i))
                if let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, cgImage, nil)
                    CGImageDestinationFinalize(dest)
                }
            }
        }
        return folder
    }

    // MARK: - Document conversions (textutil)
    private func convertDocumentWithTextutil(source: URL, destination: URL, targetExt: String) throws -> URL {
        let formatArg: String
        switch targetExt {
        case "docx": formatArg = "docx"
        case "txt": formatArg = "txt"
        case "rtf": formatArg = "rtf"
        case "html": formatArg = "html"
        default: formatArg = "txt"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", formatArg, "-output", destination.path, source.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return destination
        } else {
            throw ConversionError.conversionFailed("textutil failed with exit code \(process.terminationStatus)")
        }
    }

    // MARK: - Archives
    public func extractArchive(source: URL) throws -> URL {
        let folderName = "\(source.deletingPathExtension().lastPathComponent) Extracted"
        let outputFolder = uniqueOutputFolder(directory: source.deletingLastPathComponent(), name: folderName)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let process = Process()
        if source.pathExtension.lowercased() == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", source.path, outputFolder.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", source.path, "-C", outputFolder.path]
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return outputFolder
        } else {
            throw ConversionError.conversionFailed("Archive extraction failed")
        }
    }

    // MARK: - Compression & Metadata
    public func compressFile(source: URL) throws -> URL {
        let ext = source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(directory: source.deletingLastPathComponent(), baseName: "\(source.deletingPathExtension().lastPathComponent) Compressed", ext: ext)

        if ConversionMatrix.imageFormats.contains(ext) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = ["-s", "formatOptions", "70", source.path, "--out", outURL.path]
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return outURL
            }
        }

        try FileManager.default.copyItem(at: source, to: outURL)
        return outURL
    }

    public func removeMetadata(source: URL) throws -> URL {
        let ext = source.pathExtension.lowercased()
        let outURL = uniqueOutputURL(directory: source.deletingLastPathComponent(), baseName: "\(source.deletingPathExtension().lastPathComponent) No Metadata", ext: ext)

        if ConversionMatrix.imageFormats.contains(ext) {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
                  let type = CGImageSourceGetType(imageSource) else {
                try FileManager.default.copyItem(at: source, to: outURL)
                return outURL
            }
            guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL, type, 1, nil) else {
                try FileManager.default.copyItem(at: source, to: outURL)
                return outURL
            }
            CGImageDestinationAddImage(destination, cgImage, [:] as CFDictionary)
            CGImageDestinationFinalize(destination)
            return outURL
        }

        try FileManager.default.copyItem(at: source, to: outURL)
        return outURL
    }

    private func convertWithSips(source: URL, destination: URL, targetFormat: String) throws -> URL {
        let sipsFormat: String
        switch targetFormat {
        case "jpg", "jpeg": sipsFormat = "jpeg"
        case "png": sipsFormat = "png"
        case "tiff": sipsFormat = "tiff"
        case "bmp": sipsFormat = "bmp"
        default: sipsFormat = targetFormat
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-s", "format", sipsFormat, source.path, "--out", destination.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return destination
        } else {
            throw ConversionError.conversionFailed("sips conversion to \(targetFormat) failed")
        }
    }

    // MARK: - Helpers
    public func uniqueOutputURL(directory: URL, baseName: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    public func uniqueOutputFolder(directory: URL, name: String) -> URL {
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(counter)")
            counter += 1
        }
        return candidate
    }
}
