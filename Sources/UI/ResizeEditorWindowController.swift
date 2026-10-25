import Foundation
import AppKit
import CoreGraphics
import CoreImage
import PDFKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Drag Mode for Crop Canvas
private enum CropDragMode {
    case none
    case create
    case move
    case cornerTL
    case cornerTR
    case cornerBL
    case cornerBR
    case edgeTop
    case edgeBottom
    case edgeLeft
    case edgeRight
}

// MARK: - Interactive Crop & Preview Canvas View
@MainActor
public final class InteractiveCropView: NSView {
    public var image: NSImage? {
        didSet {
            cropNormalizedRect = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    public var originalWidth: CGFloat = 1
    public var originalHeight: CGFloat = 1

    // Normalized crop box: x, y (from top-left 0..1), width (0..1), height (0..1)
    public var cropNormalizedRect: CGRect? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            onCropChanged?(cropNormalizedRect)
        }
    }

    public var lockedAspectRatio: CGFloat? = nil // nil = freeform
    public var onCropChanged: ((CGRect?) -> Void)?

    private var dragMode: CropDragMode = .none
    private var dragStartLoc: CGPoint = .zero
    private var initialCropNorm: CGRect? = nil

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool { false }

    public func imageDrawingRect() -> CGRect {
        guard let img = image, img.size.width > 0, img.size.height > 0 else { return .zero }
        let b = bounds.insetBy(dx: 16, dy: 16)
        guard b.width > 0 && b.height > 0 else { return .zero }

        let scale = min(b.width / img.size.width, b.height / img.size.height)
        let dw = img.size.width * scale
        let dh = img.size.height * scale
        let ox = b.minX + (b.width - dw) / 2
        let oy = b.minY + (b.height - dh) / 2
        return CGRect(x: ox, y: oy, width: dw, height: dh)
    }

    public func cropRectInView() -> CGRect? {
        guard let norm = cropNormalizedRect else { return nil }
        let imgRect = imageDrawingRect()
        guard imgRect.width > 0 && imgRect.height > 0 else { return nil }

        let cx = imgRect.minX + norm.origin.x * imgRect.width
        let cy = imgRect.maxY - (norm.origin.y + norm.size.height) * imgRect.height
        let cw = norm.size.width * imgRect.width
        let ch = norm.size.height * imgRect.height
        return CGRect(x: cx, y: cy, width: cw, height: ch)
    }

    // MARK: - Mouse Event Handling
    private func hitTestCrop(loc: CGPoint) -> CropDragMode {
        guard let box = cropRectInView() else { return .create }
        let tol: CGFloat = 14.0

        let tl = CGPoint(x: box.minX, y: box.maxY)
        let tr = CGPoint(x: box.maxX, y: box.maxY)
        let bl = CGPoint(x: box.minX, y: box.minY)
        let br = CGPoint(x: box.maxX, y: box.minY)

        if hypot(loc.x - tl.x, loc.y - tl.y) <= tol { return .cornerTL }
        if hypot(loc.x - tr.x, loc.y - tr.y) <= tol { return .cornerTR }
        if hypot(loc.x - bl.x, loc.y - bl.y) <= tol { return .cornerBL }
        if hypot(loc.x - br.x, loc.y - br.y) <= tol { return .cornerBR }

        if abs(loc.y - box.maxY) <= tol && loc.x >= box.minX && loc.x <= box.maxX { return .edgeTop }
        if abs(loc.y - box.minY) <= tol && loc.x >= box.minX && loc.x <= box.maxX { return .edgeBottom }
        if abs(loc.x - box.minX) <= tol && loc.y >= box.minY && loc.y <= box.maxY { return .edgeLeft }
        if abs(loc.x - box.maxX) <= tol && loc.y >= box.minY && loc.y <= box.maxY { return .edgeRight }

        if box.contains(loc) { return .move }
        return .create
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        guard let box = cropRectInView() else {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }

        let tol: CGFloat = 12.0
        let tlRect = CGRect(x: box.minX - tol, y: box.maxY - tol, width: tol * 2, height: tol * 2)
        let trRect = CGRect(x: box.maxX - tol, y: box.maxY - tol, width: tol * 2, height: tol * 2)
        let blRect = CGRect(x: box.minX - tol, y: box.minY - tol, width: tol * 2, height: tol * 2)
        let brRect = CGRect(x: box.maxX - tol, y: box.minY - tol, width: tol * 2, height: tol * 2)

        let topRect = CGRect(x: box.minX, y: box.maxY - tol, width: box.width, height: tol * 2)
        let botRect = CGRect(x: box.minX, y: box.minY - tol, width: box.width, height: tol * 2)
        let leftRect = CGRect(x: box.minX - tol, y: box.minY, width: tol * 2, height: box.height)
        let rightRect = CGRect(x: box.maxX - tol, y: box.minY, width: tol * 2, height: box.height)

        addCursorRect(tlRect, cursor: .crosshair)
        addCursorRect(trRect, cursor: .crosshair)
        addCursorRect(blRect, cursor: .crosshair)
        addCursorRect(brRect, cursor: .crosshair)

        addCursorRect(topRect, cursor: .resizeUpDown)
        addCursorRect(botRect, cursor: .resizeUpDown)
        addCursorRect(leftRect, cursor: .resizeLeftRight)
        addCursorRect(rightRect, cursor: .resizeLeftRight)

        addCursorRect(box, cursor: .openHand)
        addCursorRect(bounds, cursor: .crosshair)
    }

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let imgRect = imageDrawingRect()
        guard imgRect.contains(loc) else {
            dragMode = .none
            return
        }

        dragStartLoc = loc
        initialCropNorm = cropNormalizedRect
        dragMode = hitTestCrop(loc: loc)

        if dragMode == .create {
            cropNormalizedRect = nil
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard dragMode != .none else { return }
        let current = convert(event.locationInWindow, from: nil)
        let imgRect = imageDrawingRect()
        guard imgRect.width > 0 && imgRect.height > 0 else { return }

        let isShiftHeld = event.modifierFlags.contains(.shift)
        let activeAspect = lockedAspectRatio ?? (isShiftHeld ? 1.0 : nil)

        switch dragMode {
        case .create:
            let clampedX = min(max(current.x, imgRect.minX), imgRect.maxX)
            let clampedY = min(max(current.y, imgRect.minY), imgRect.maxY)

            let rx = min(dragStartLoc.x, clampedX)
            let ry = min(dragStartLoc.y, clampedY)
            var rw = abs(clampedX - dragStartLoc.x)
            var rh = abs(clampedY - dragStartLoc.y)

            if let aspect = activeAspect, aspect > 0 && rh > 0 {
                rw = rh * aspect
                if rx + rw > imgRect.maxX {
                    rw = imgRect.maxX - rx
                    rh = rw / aspect
                }
            }

            guard rw > 6 && rh > 6 else { return }

            let normX = (rx - imgRect.minX) / imgRect.width
            let normY = (imgRect.maxY - (ry + rh)) / imgRect.height
            let normW = rw / imgRect.width
            let normH = rh / imgRect.height
            cropNormalizedRect = CGRect(x: max(0, normX), y: max(0, normY), width: min(1 - normX, normW), height: min(1 - normY, normH))

        case .move:
            guard let initNorm = initialCropNorm else { return }
            let dx = (current.x - dragStartLoc.x) / imgRect.width
            let dy = -(current.y - dragStartLoc.y) / imgRect.height

            var newX = initNorm.origin.x + dx
            var newY = initNorm.origin.y + dy

            newX = max(0, min(1 - initNorm.size.width, newX))
            newY = max(0, min(1 - initNorm.size.height, newY))

            cropNormalizedRect = CGRect(x: newX, y: newY, width: initNorm.size.width, height: initNorm.size.height)

        case .cornerTL, .cornerTR, .cornerBL, .cornerBR, .edgeTop, .edgeBottom, .edgeLeft, .edgeRight:
            guard let initNorm = initialCropNorm else { return }
            let clampedX = min(max(current.x, imgRect.minX), imgRect.maxX)
            let clampedY = min(max(current.y, imgRect.minY), imgRect.maxY)

            let currNormX = (clampedX - imgRect.minX) / imgRect.width
            let currNormY = (imgRect.maxY - clampedY) / imgRect.height

            var nx = initNorm.origin.x
            var ny = initNorm.origin.y
            var nw = initNorm.size.width
            var nh = initNorm.size.height

            switch dragMode {
            case .cornerTL:
                let rEdge = initNorm.maxX
                let bEdge = initNorm.maxY
                nx = min(currNormX, rEdge - 0.02)
                ny = min(currNormY, bEdge - 0.02)
                nw = rEdge - nx
                nh = bEdge - ny
            case .cornerTR:
                let lEdge = initNorm.minX
                let bEdge = initNorm.maxY
                ny = min(currNormY, bEdge - 0.02)
                nw = max(0.02, currNormX - lEdge)
                nh = bEdge - ny
            case .cornerBL:
                let rEdge = initNorm.maxX
                let tEdge = initNorm.minY
                nx = min(currNormX, rEdge - 0.02)
                nw = rEdge - nx
                nh = max(0.02, currNormY - tEdge)
            case .cornerBR:
                let lEdge = initNorm.minX
                let tEdge = initNorm.minY
                nw = max(0.02, currNormX - lEdge)
                nh = max(0.02, currNormY - tEdge)
            case .edgeTop:
                let bEdge = initNorm.maxY
                ny = min(currNormY, bEdge - 0.02)
                nh = bEdge - ny
            case .edgeBottom:
                let tEdge = initNorm.minY
                nh = max(0.02, currNormY - tEdge)
            case .edgeLeft:
                let rEdge = initNorm.maxX
                nx = min(currNormX, rEdge - 0.02)
                nw = rEdge - nx
            case .edgeRight:
                let lEdge = initNorm.minX
                nw = max(0.02, currNormX - lEdge)
            default: break
            }

            if let aspect = activeAspect, aspect > 0 && nh > 0 {
                let naturalRatio = (originalWidth / originalHeight)
                let normAspect = aspect / naturalRatio
                nw = nh * normAspect
            }

            cropNormalizedRect = CGRect(x: max(0, nx), y: max(0, ny), width: min(1 - nx, nw), height: min(1 - ny, nh))

        default: break
        }
    }

    public override func mouseUp(with event: NSEvent) {
        dragMode = .none
        initialCropNorm = nil
    }

    // MARK: - Drawing & Graphics
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let imgRect = imageDrawingRect()
        guard imgRect.width > 0, let img = image else { return }

        // 1. Draw Source Image with Subtle Drop Shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor(white: 0, alpha: 0.35).cgColor)
        img.draw(in: imgRect)
        ctx.restoreGState()

        // 2. Crop Overlay
        if let norm = cropNormalizedRect, let cropBox = cropRectInView() {
            // Dark outer mask with smooth vignette
            ctx.saveGState()
            let maskPath = CGMutablePath()
            maskPath.addRect(bounds)
            maskPath.addRect(cropBox)
            ctx.addPath(maskPath)
            ctx.setFillColor(NSColor(white: 0, alpha: 0.65).cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            // Crisp White Crop Border
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2.0)
            ctx.stroke(cropBox)

            // Rule-of-thirds Grid
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.32).cgColor)
            ctx.setLineWidth(1.0)
            let cx = cropBox.minX
            let cy = cropBox.minY
            let cw = cropBox.width
            let ch = cropBox.height
            ctx.strokeLineSegments(between: [
                CGPoint(x: cx + cw / 3, y: cy), CGPoint(x: cx + cw / 3, y: cy + ch),
                CGPoint(x: cx + 2 * cw / 3, y: cy), CGPoint(x: cx + 2 * cw / 3, y: cy + ch),
                CGPoint(x: cx, y: cy + ch / 3), CGPoint(x: cx + cw, y: cy + ch / 3),
                CGPoint(x: cx, y: cy + 2 * ch / 3), CGPoint(x: cx + cw, y: cy + 2 * ch / 3)
            ])

            // Corner Handles (12x12 rounded white gloss pills)
            let handleSize: CGFloat = 12.0
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor(white: 0, alpha: 0.4).cgColor)
            let corners = [
                CGRect(x: cx - 2, y: cy - 2, width: handleSize, height: handleSize),
                CGRect(x: cx + cw - handleSize + 2, y: cy - 2, width: handleSize, height: handleSize),
                CGRect(x: cx - 2, y: cy + ch - handleSize + 2, width: handleSize, height: handleSize),
                CGRect(x: cx + cw - handleSize + 2, y: cy + ch - handleSize + 2, width: handleSize, height: handleSize)
            ]
            for c in corners {
                let path = CGPath(roundedRect: c, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
            }

            // Edge Handle bars (18x6 pills)
            let edgeBarW: CGFloat = 18.0
            let edgeBarH: CGFloat = 6.0
            let edgeBars = [
                CGRect(x: cx + cw / 2 - edgeBarW / 2, y: cy - 3, width: edgeBarW, height: edgeBarH),
                CGRect(x: cx + cw / 2 - edgeBarW / 2, y: cy + ch - 3, width: edgeBarW, height: edgeBarH),
                CGRect(x: cx - 3, y: cy + ch / 2 - edgeBarW / 2, width: edgeBarH, height: edgeBarW),
                CGRect(x: cx + cw - 3, y: cy + ch / 2 - edgeBarW / 2, width: edgeBarH, height: edgeBarW)
            ]
            for b in edgeBars {
                let path = CGPath(roundedRect: b, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
            }
            ctx.restoreGState()

            // Dynamic Crop Badge with Aspect Ratio Readout
            let pxW = Int(round(norm.size.width * originalWidth))
            let pxH = Int(round(norm.size.height * originalHeight))
            let gcdVal = gcd(pxW, pxH)
            let rW = pxW / max(1, gcdVal)
            let rH = pxH / max(1, gcdVal)
            let ratioStr = (rW <= 32 && rH <= 32) ? " • \(rW):\(rH)" : ""
            let badgeText = "Crop: \(pxW) × \(pxH) px\(ratioStr)"
            drawBadge(text: badgeText, at: CGPoint(x: cropBox.midX, y: max(24, cropBox.minY - 18)))
        } else {
            // Helpful Guide Badge
            drawBadge(text: "Drag freely anywhere on image to crop (Hold ⇧ for 1:1 square)", at: CGPoint(x: bounds.midX, y: 26))
        }
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 {
            let t = y
            y = x % y
            x = t
        }
        return x
    }

    private func drawBadge(text: String, at point: CGPoint) {
        let font = NSFont.systemFont(ofSize: 11.0, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pillRect = CGRect(x: point.x - size.width / 2 - 12, y: point.y - size.height / 2 - 5, width: size.width + 24, height: size.height + 10)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
        ctx.addPath(pillPath)
        ctx.setFillColor(NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 0.94).cgColor)
        ctx.fillPath()
        ctx.addPath(pillPath)
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.28).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()
        ctx.restoreGState()

        str.draw(at: CGPoint(x: pillRect.minX + 12, y: pillRect.minY + 5))
    }
}

// MARK: - Main Resize, Freeform Crop & Edit Window Controller
@MainActor
public final class ResizeEditorWindowController: NSWindowController, NSTextFieldDelegate {
    public static let shared = ResizeEditorWindowController()

    // Active files & state
    private var targetFiles: [URL] = []
    private var originalWidth: CGFloat = 1
    private var originalHeight: CGFloat = 1
    private var isPDF: Bool = false
    private var pdfDocument: PDFDocument?
    private var rotationDegrees: Int = 0
    private var flipH: Bool = false

    // UI Elements
    private let cropCanvasView = InteractiveCropView()
    private let fileInfoBadge = NSTextField(labelWithString: "Loading...")
    private let targetInfoLabel = NSTextField(labelWithString: "Target: —")

    private let cropAspectPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cropStatusLabel = NSTextField(labelWithString: "Crop: Full Image (Freeform)")

    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let lockAspectButton = NSButton()
    private var isAspectLocked: Bool = true

    private let presetPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    public let formatPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualitySlider = NSSlider(value: 85.0, minValue: 30.0, maxValue: 100.0, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: "WebP Quality: 85% (High)")

    private let brightnessSlider = NSSlider(value: 0.0, minValue: -0.5, maxValue: 0.5, target: nil, action: nil)
    private let contrastSlider = NSSlider(value: 1.0, minValue: 0.5, maxValue: 1.5, target: nil, action: nil)
    private let saturationSlider = NSSlider(value: 1.0, minValue: 0.0, maxValue: 2.0, target: nil, action: nil)

    private let applyBtn = NSButton()

    private var isUpdatingFields = false

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 940, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Freeform Crop, Resize & Convert to WebP"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 860, height: 580)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present(for files: [URL], defaultWebP: Bool = true) {
        guard let first = files.first else { return }
        self.targetFiles = files
        loadFile(first, selectWebP: defaultWebP)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func loadFile(_ url: URL, selectWebP: Bool) {
        let ext = url.pathExtension.lowercased()
        isPDF = (ext == "pdf")
        rotationDegrees = 0
        flipH = false
        brightnessSlider.doubleValue = 0.0
        contrastSlider.doubleValue = 1.0
        saturationSlider.doubleValue = 1.0

        if isPDF {
            pdfDocument = PDFDocument(url: url)
            if let page = pdfDocument?.page(at: 0) {
                let box = page.bounds(for: .mediaBox)
                originalWidth = box.width
                originalHeight = box.height
                let pageImg = page.thumbnail(of: NSSize(width: 1200, height: 1200), for: .mediaBox)
                cropCanvasView.image = pageImg
            }
        } else {
            pdfDocument = nil
            if let img = NSImage(contentsOf: url) {
                if let rep = img.representations.first {
                    originalWidth = CGFloat(rep.pixelsWide > 0 ? rep.pixelsWide : Int(img.size.width))
                    originalHeight = CGFloat(rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(img.size.height))
                } else {
                    originalWidth = img.size.width
                    originalHeight = img.size.height
                }
                cropCanvasView.image = img
            }
        }

        cropCanvasView.originalWidth = originalWidth
        cropCanvasView.originalHeight = originalHeight
        cropCanvasView.cropNormalizedRect = nil
        cropCanvasView.lockedAspectRatio = nil
        cropAspectPopUp.selectItem(at: 0)

        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        let multiNote = targetFiles.count > 1 ? " +\(targetFiles.count - 1) other files" : ""
        fileInfoBadge.stringValue = "\(url.lastPathComponent)\(multiNote) • \(Int(originalWidth)) × \(Int(originalHeight)) px (\(sizeStr))"

        isUpdatingFields = true
        widthField.stringValue = "\(Int(originalWidth))"
        heightField.stringValue = "\(Int(originalHeight))"
        isUpdatingFields = false

        if selectWebP || ext != "pdf" {
            formatPopUp.selectItem(at: 0) // Default WebP (.webp)
        } else {
            formatPopUp.selectItem(at: 3) // PDF
        }

        updateFormatSelectionUI()
        updateTargetInfo()
    }

    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }
        contentView.wantsLayer = true

        let rootSplit = NSSplitView()
        rootSplit.isVertical = true
        rootSplit.dividerStyle = .thin
        rootSplit.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootSplit)

        NSLayoutConstraint.activate([
            rootSplit.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootSplit.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootSplit.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootSplit.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 1. Left View: Studio Canvas Area
        let leftContainer = NSView()
        leftContainer.wantsLayer = true
        leftContainer.layer?.backgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0).cgColor

        fileInfoBadge.translatesAutoresizingMaskIntoConstraints = false
        fileInfoBadge.font = .systemFont(ofSize: 12, weight: .bold)
        fileInfoBadge.textColor = .white
        leftContainer.addSubview(fileInfoBadge)

        cropCanvasView.translatesAutoresizingMaskIntoConstraints = false
        cropCanvasView.onCropChanged = { [weak self] normRect in
            self?.handleCropUpdated(normRect)
        }
        leftContainer.addSubview(cropCanvasView)

        // Canvas Tool Bar (Glass Pills)
        let toolBar = NSStackView()
        toolBar.orientation = .horizontal
        toolBar.spacing = 8
        toolBar.translatesAutoresizingMaskIntoConstraints = false

        let rotateLeftBtn = makePillButton(title: "↺ Rotate 90°", action: #selector(rotateLeft))
        let rotateRightBtn = makePillButton(title: "↻ Rotate 90°", action: #selector(rotateRight))
        let flipBtn = makePillButton(title: "⇄ Flip H", action: #selector(flipHorizontal))
        let resetCropBtn = makePillButton(title: "⛶ Reset Crop", action: #selector(resetCrop))

        toolBar.addArrangedSubview(rotateLeftBtn)
        toolBar.addArrangedSubview(rotateRightBtn)
        toolBar.addArrangedSubview(flipBtn)
        toolBar.addArrangedSubview(resetCropBtn)
        leftContainer.addSubview(toolBar)

        NSLayoutConstraint.activate([
            fileInfoBadge.topAnchor.constraint(equalTo: leftContainer.topAnchor, constant: 16),
            fileInfoBadge.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor, constant: 18),
            fileInfoBadge.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor, constant: -18),

            cropCanvasView.topAnchor.constraint(equalTo: fileInfoBadge.bottomAnchor, constant: 12),
            cropCanvasView.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor, constant: 18),
            cropCanvasView.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor, constant: -18),
            cropCanvasView.bottomAnchor.constraint(equalTo: toolBar.topAnchor, constant: -14),

            toolBar.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor, constant: 18),
            toolBar.bottomAnchor.constraint(equalTo: leftContainer.bottomAnchor, constant: -16),
            toolBar.heightAnchor.constraint(equalToConstant: 28)
        ])

        // 2. Right View: Controls Panel (Translucent Sidebar)
        let rightVisual = NSVisualEffectView()
        rightVisual.material = .sidebar
        rightVisual.blendingMode = .behindWindow
        rightVisual.state = .active
        rightVisual.wantsLayer = true

        let rightContainer = NSView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        rightVisual.addSubview(rightContainer)

        NSLayoutConstraint.activate([
            rightContainer.leadingAnchor.constraint(equalTo: rightVisual.leadingAnchor),
            rightContainer.trailingAnchor.constraint(equalTo: rightVisual.trailingAnchor),
            rightContainer.topAnchor.constraint(equalTo: rightVisual.topAnchor),
            rightContainer.bottomAnchor.constraint(equalTo: rightVisual.bottomAnchor)
        ])

        // Card 1: FREEFORM CROP
        let cropTitle = makeSectionHeader("FREEFORM CROP")
        rightContainer.addSubview(cropTitle)

        cropAspectPopUp.translatesAutoresizingMaskIntoConstraints = false
        cropAspectPopUp.addItems(withTitles: [
            "Freeform Crop (Drag Freely on Canvas)",
            "1:1 Square (Avatar / Post)",
            "16:9 Widescreen (YouTube / Banner)",
            "4:3 Standard Photo",
            "9:16 Vertical Reel / Story",
            "3:2 Classic 35mm Photo"
        ])
        cropAspectPopUp.target = self
        cropAspectPopUp.action = #selector(aspectPresetSelected)
        rightContainer.addSubview(cropAspectPopUp)

        cropStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        cropStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        cropStatusLabel.textColor = .secondaryLabelColor
        rightContainer.addSubview(cropStatusLabel)

        // Card 2: TARGET DIMENSIONS
        let dimTitle = makeSectionHeader("TARGET DIMENSIONS & SCALING")
        rightContainer.addSubview(dimTitle)

        let wLabel = NSTextField(labelWithString: "Width:")
        wLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        wLabel.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(wLabel)

        widthField.translatesAutoresizingMaskIntoConstraints = false
        widthField.delegate = self
        widthField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        rightContainer.addSubview(widthField)

        let hLabel = NSTextField(labelWithString: "Height:")
        hLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        hLabel.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(hLabel)

        heightField.translatesAutoresizingMaskIntoConstraints = false
        heightField.delegate = self
        heightField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        rightContainer.addSubview(heightField)

        lockAspectButton.translatesAutoresizingMaskIntoConstraints = false
        lockAspectButton.bezelStyle = .texturedRounded
        lockAspectButton.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Lock Aspect Ratio")
        lockAspectButton.target = self
        lockAspectButton.action = #selector(toggleAspectLock)
        rightContainer.addSubview(lockAspectButton)

        // Scale Presets Stack
        let scaleStack = NSStackView()
        scaleStack.orientation = .horizontal
        scaleStack.distribution = .fillEqually
        scaleStack.spacing = 6
        scaleStack.translatesAutoresizingMaskIntoConstraints = false

        for pct in [25, 50, 75, 100, 200] {
            let btn = NSButton(title: "\(pct)%", target: self, action: #selector(scalePresetClicked(_:)))
            btn.tag = pct
            btn.bezelStyle = .rounded
            scaleStack.addArrangedSubview(btn)
        }
        rightContainer.addSubview(scaleStack)

        // Standard Resolutions Dropdown
        presetPopUp.translatesAutoresizingMaskIntoConstraints = false
        presetPopUp.addItems(withTitles: [
            "Select resolution preset...",
            "1080p Full HD (1920 × 1080)",
            "720p HD (1280 × 720)",
            "Square Avatar (1080 × 1080)",
            "Social Landscape (1200 × 630)",
            "A4 Document (595 × 842 pt)",
            "US Letter (612 × 792 pt)"
        ])
        presetPopUp.target = self
        presetPopUp.action = #selector(resolutionPresetSelected)
        rightContainer.addSubview(presetPopUp)

        // Card 3: OUTPUT FORMAT & QUALITY
        let formatTitle = makeSectionHeader("OUTPUT FORMAT & COMPRESSION")
        rightContainer.addSubview(formatTitle)

        formatPopUp.translatesAutoresizingMaskIntoConstraints = false
        formatPopUp.addItems(withTitles: [
            "WebP (.webp) — Optimized & Modern",
            "PNG (.png) — Lossless",
            "JPEG (.jpg) — Standard Photo",
            "PDF (.pdf) — Vector Document",
            "Keep Original Format"
        ])
        formatPopUp.target = self
        formatPopUp.action = #selector(formatSelected)
        rightContainer.addSubview(formatPopUp)

        qualityLabel.translatesAutoresizingMaskIntoConstraints = false
        qualityLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        qualityLabel.textColor = .secondaryLabelColor
        rightContainer.addSubview(qualityLabel)

        qualitySlider.translatesAutoresizingMaskIntoConstraints = false
        qualitySlider.target = self
        qualitySlider.action = #selector(qualitySliderChanged)
        rightContainer.addSubview(qualitySlider)

        // Card 4: ADJUSTMENTS
        let adjTitle = makeSectionHeader("IMAGE ADJUSTMENTS")
        rightContainer.addSubview(adjTitle)

        let brightLabel = NSTextField(labelWithString: "Brightness:")
        brightLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        brightLabel.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(brightLabel)

        brightnessSlider.translatesAutoresizingMaskIntoConstraints = false
        brightnessSlider.target = self
        brightnessSlider.action = #selector(sliderChanged)
        rightContainer.addSubview(brightnessSlider)

        let contrastLabel = NSTextField(labelWithString: "Contrast:")
        contrastLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        contrastLabel.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(contrastLabel)

        contrastSlider.translatesAutoresizingMaskIntoConstraints = false
        contrastSlider.target = self
        contrastSlider.action = #selector(sliderChanged)
        rightContainer.addSubview(contrastSlider)

        targetInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        targetInfoLabel.font = .systemFont(ofSize: 11.5, weight: .bold)
        targetInfoLabel.textColor = .labelColor
        rightContainer.addSubview(targetInfoLabel)

        // Action Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(cancelBtn)

        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"
        applyBtn.target = self
        applyBtn.action = #selector(applyAction)
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(applyBtn)

        NSLayoutConstraint.activate([
            cropTitle.topAnchor.constraint(equalTo: rightContainer.topAnchor, constant: 18),
            cropTitle.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),

            cropAspectPopUp.topAnchor.constraint(equalTo: cropTitle.bottomAnchor, constant: 6),
            cropAspectPopUp.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            cropAspectPopUp.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            cropStatusLabel.topAnchor.constraint(equalTo: cropAspectPopUp.bottomAnchor, constant: 4),
            cropStatusLabel.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            cropStatusLabel.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            dimTitle.topAnchor.constraint(equalTo: cropStatusLabel.bottomAnchor, constant: 14),
            dimTitle.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),

            wLabel.topAnchor.constraint(equalTo: dimTitle.bottomAnchor, constant: 6),
            wLabel.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            wLabel.widthAnchor.constraint(equalToConstant: 45),

            widthField.centerYAnchor.constraint(equalTo: wLabel.centerYAnchor),
            widthField.leadingAnchor.constraint(equalTo: wLabel.trailingAnchor, constant: 4),
            widthField.widthAnchor.constraint(equalToConstant: 72),

            hLabel.centerYAnchor.constraint(equalTo: wLabel.centerYAnchor),
            hLabel.leadingAnchor.constraint(equalTo: widthField.trailingAnchor, constant: 10),
            hLabel.widthAnchor.constraint(equalToConstant: 48),

            heightField.centerYAnchor.constraint(equalTo: wLabel.centerYAnchor),
            heightField.leadingAnchor.constraint(equalTo: hLabel.trailingAnchor, constant: 4),
            heightField.widthAnchor.constraint(equalToConstant: 72),

            lockAspectButton.centerYAnchor.constraint(equalTo: wLabel.centerYAnchor),
            lockAspectButton.leadingAnchor.constraint(equalTo: heightField.trailingAnchor, constant: 6),
            lockAspectButton.widthAnchor.constraint(equalToConstant: 28),
            lockAspectButton.heightAnchor.constraint(equalToConstant: 24),

            scaleStack.topAnchor.constraint(equalTo: widthField.bottomAnchor, constant: 8),
            scaleStack.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            scaleStack.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            presetPopUp.topAnchor.constraint(equalTo: scaleStack.bottomAnchor, constant: 8),
            presetPopUp.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            presetPopUp.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            formatTitle.topAnchor.constraint(equalTo: presetPopUp.bottomAnchor, constant: 14),
            formatTitle.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),

            formatPopUp.topAnchor.constraint(equalTo: formatTitle.bottomAnchor, constant: 6),
            formatPopUp.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            formatPopUp.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            qualityLabel.topAnchor.constraint(equalTo: formatPopUp.bottomAnchor, constant: 6),
            qualityLabel.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),

            qualitySlider.centerYAnchor.constraint(equalTo: qualityLabel.centerYAnchor),
            qualitySlider.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 145),
            qualitySlider.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            adjTitle.topAnchor.constraint(equalTo: qualityLabel.bottomAnchor, constant: 14),
            adjTitle.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),

            brightLabel.topAnchor.constraint(equalTo: adjTitle.bottomAnchor, constant: 6),
            brightLabel.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            brightLabel.widthAnchor.constraint(equalToConstant: 72),

            brightnessSlider.centerYAnchor.constraint(equalTo: brightLabel.centerYAnchor),
            brightnessSlider.leadingAnchor.constraint(equalTo: brightLabel.trailingAnchor, constant: 4),
            brightnessSlider.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            contrastLabel.topAnchor.constraint(equalTo: brightLabel.bottomAnchor, constant: 6),
            contrastLabel.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            contrastLabel.widthAnchor.constraint(equalToConstant: 72),

            contrastSlider.centerYAnchor.constraint(equalTo: contrastLabel.centerYAnchor),
            contrastSlider.leadingAnchor.constraint(equalTo: contrastLabel.trailingAnchor, constant: 4),
            contrastSlider.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),

            targetInfoLabel.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            targetInfoLabel.bottomAnchor.constraint(equalTo: cancelBtn.topAnchor, constant: -14),

            cancelBtn.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            cancelBtn.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor, constant: -16),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80),

            applyBtn.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),
            applyBtn.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor, constant: -16),
            applyBtn.leadingAnchor.constraint(equalTo: cancelBtn.trailingAnchor, constant: 12)
        ])

        rootSplit.addArrangedSubview(leftContainer)
        rootSplit.addArrangedSubview(rightVisual)
        rootSplit.setPosition(580, ofDividerAt: 0)
    }

    private func makeSectionHeader(_ text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = .systemFont(ofSize: 10, weight: .heavy)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }

    private func makePillButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .recessed
        btn.font = .systemFont(ofSize: 11, weight: .semibold)
        return btn
    }

    @objc private func toggleAspectLock() {
        isAspectLocked.toggle()
        lockAspectButton.image = NSImage(
            systemSymbolName: isAspectLocked ? "lock.fill" : "lock.open.fill",
            accessibilityDescription: "Aspect Ratio Lock"
        )
    }

    // MARK: - Crop Actions & Updates
    private func handleCropUpdated(_ normRect: CGRect?) {
        guard let norm = normRect else {
            cropStatusLabel.stringValue = "Crop: Full Image (Freeform)"
            isUpdatingFields = true
            widthField.stringValue = "\(Int(originalWidth))"
            heightField.stringValue = "\(Int(originalHeight))"
            isUpdatingFields = false
            updateTargetInfo()
            return
        }

        let cropW = Int(round(norm.width * originalWidth))
        let cropH = Int(round(norm.height * originalHeight))
        cropStatusLabel.stringValue = "Crop Box: \(cropW) × \(cropH) px (Drag handles to adjust)"

        isUpdatingFields = true
        widthField.stringValue = "\(cropW)"
        heightField.stringValue = "\(cropH)"
        isUpdatingFields = false

        updateTargetInfo()
    }

    @objc private func aspectPresetSelected() {
        switch cropAspectPopUp.indexOfSelectedItem {
        case 1: cropCanvasView.lockedAspectRatio = 1.0       // 1:1
        case 2: cropCanvasView.lockedAspectRatio = 16.0 / 9.0 // 16:9
        case 3: cropCanvasView.lockedAspectRatio = 4.0 / 3.0  // 4:3
        case 4: cropCanvasView.lockedAspectRatio = 9.0 / 16.0 // 9:16
        case 5: cropCanvasView.lockedAspectRatio = 3.0 / 2.0  // 3:2
        default: cropCanvasView.lockedAspectRatio = nil       // Freeform
        }
    }

    @objc private func resetCrop() {
        cropCanvasView.cropNormalizedRect = nil
        cropAspectPopUp.selectItem(at: 0)
        cropCanvasView.lockedAspectRatio = nil
    }

    // MARK: - Format & Quality Updates
    @objc private func formatSelected() {
        updateFormatSelectionUI()
        updateTargetInfo()
    }

    @objc private func qualitySliderChanged() {
        let q = Int(qualitySlider.doubleValue)
        let labelDesc = q >= 85 ? "High Quality" : (q >= 60 ? "Balanced" : "Maximum Compression")
        qualityLabel.stringValue = "WebP Quality: \(q)% (\(labelDesc))"
    }

    private func updateFormatSelectionUI() {
        let idx = formatPopUp.indexOfSelectedItem
        let isWebP = (idx == 0)
        let isJPG = (idx == 2)
        qualityLabel.isHidden = !(isWebP || isJPG)
        qualitySlider.isHidden = !(isWebP || isJPG)

        let fmtName: String
        switch idx {
        case 0: fmtName = "WebP"
        case 1: fmtName = "PNG"
        case 2: fmtName = "JPEG"
        case 3: fmtName = "PDF"
        default: fmtName = "Image"
        }
        applyBtn.title = "Apply Crop & Save as \(fmtName)"
    }

    // MARK: - Delegate & Updates
    public func controlTextDidChange(_ obj: Notification) {
        guard !isUpdatingFields else { return }
        guard let field = obj.object as? NSTextField else { return }

        isUpdatingFields = true
        let lock = isAspectLocked

        let activeW = cropCanvasView.cropNormalizedRect.map { $0.width * originalWidth } ?? originalWidth
        let activeH = cropCanvasView.cropNormalizedRect.map { $0.height * originalHeight } ?? originalHeight

        if field == widthField {
            if let wVal = Double(widthField.stringValue), wVal > 0 {
                if lock && activeW > 0 {
                    let ratio = activeH / activeW
                    heightField.stringValue = "\(Int(round(wVal * ratio)))"
                }
            }
        } else if field == heightField {
            if let hVal = Double(heightField.stringValue), hVal > 0 {
                if lock && activeH > 0 {
                    let ratio = activeW / activeH
                    widthField.stringValue = "\(Int(round(hVal * ratio)))"
                }
            }
        }
        isUpdatingFields = false
        updateTargetInfo()
    }

    @objc private func scalePresetClicked(_ sender: NSButton) {
        let pct = Double(sender.tag) / 100.0
        let baseW = cropCanvasView.cropNormalizedRect.map { $0.width * originalWidth } ?? originalWidth
        let baseH = cropCanvasView.cropNormalizedRect.map { $0.height * originalHeight } ?? originalHeight

        let newW = max(1, Int(round(baseW * pct)))
        let newH = max(1, Int(round(baseH * pct)))

        isUpdatingFields = true
        widthField.stringValue = "\(newW)"
        heightField.stringValue = "\(newH)"
        isUpdatingFields = false

        updateTargetInfo()
    }

    @objc private func resolutionPresetSelected() {
        let idx = presetPopUp.indexOfSelectedItem
        var targetW: Int?
        var targetH: Int?

        switch idx {
        case 1: targetW = 1920; targetH = 1080
        case 2: targetW = 1280; targetH = 720
        case 3: targetW = 1080; targetH = 1080
        case 4: targetW = 1200; targetH = 630
        case 5: targetW = 595; targetH = 842
        case 6: targetW = 612; targetH = 792
        default: break
        }

        if let tw = targetW, let th = targetH {
            isUpdatingFields = true
            widthField.stringValue = "\(tw)"
            heightField.stringValue = "\(th)"
            isUpdatingFields = false
            updateTargetInfo()
        }
    }

    @objc private func sliderChanged() {
        // Real-time adjustments reflected on export
    }

    @objc private func rotateLeft() {
        rotationDegrees = (rotationDegrees + 270) % 360
    }

    @objc private func rotateRight() {
        rotationDegrees = (rotationDegrees + 90) % 360
    }

    @objc private func flipHorizontal() {
        flipH.toggle()
    }

    private func updateTargetInfo() {
        let w = Int(widthField.stringValue) ?? Int(originalWidth)
        let h = Int(heightField.stringValue) ?? Int(originalHeight)
        let baseW = cropCanvasView.cropNormalizedRect.map { $0.width * originalWidth } ?? originalWidth
        let scalePct = Int(round((Double(w) / Double(baseW)) * 100.0))
        targetInfoLabel.stringValue = "Target Output: \(w) × \(h) px (\(scalePct)% scale)"
    }

    @objc private func cancelAction() {
        window?.orderOut(nil)
    }

    @objc private func applyAction() {
        let targetW = Int(widthField.stringValue) ?? Int(originalWidth)
        let targetH = Int(heightField.stringValue) ?? Int(originalHeight)
        let selectedFormatIdx = formatPopUp.indexOfSelectedItem

        var targetExt: String = "webp"
        switch selectedFormatIdx {
        case 0: targetExt = "webp"
        case 1: targetExt = "png"
        case 2: targetExt = "jpg"
        case 3: targetExt = "pdf"
        default: targetExt = targetFiles.first?.pathExtension.lowercased() ?? "webp"
        }

        let rot = rotationDegrees
        let doFlip = flipH
        let bright = brightnessSlider.doubleValue
        let contrast = contrastSlider.doubleValue
        let sat = saturationSlider.doubleValue
        let cropNorm = cropCanvasView.cropNormalizedRect
        let quality = Int(qualitySlider.doubleValue)
        let files = targetFiles

        window?.orderOut(nil)

        Task {
            for file in files {
                do {
                    let outURL = try await self.processFile(
                        file: file,
                        cropNorm: cropNorm,
                        targetW: targetW,
                        targetH: targetH,
                        targetExt: targetExt,
                        quality: quality,
                        rotation: rot,
                        flipH: doFlip,
                        brightness: bright,
                        contrast: contrast,
                        saturation: sat
                    )
                    await MainActor.run {
                        NotificationService.shared.notify(
                            title: "Saved as \(targetExt.uppercased())",
                            message: outURL.lastPathComponent,
                            success: true
                        )
                        NSWorkspace.shared.activateFileViewerSelecting([outURL])
                    }
                } catch {
                    await MainActor.run {
                        NotificationService.shared.notify(
                            title: "Process Failed",
                            message: error.localizedDescription,
                            success: false
                        )
                    }
                }
            }
        }
    }

    private func processFile(
        file: URL,
        cropNorm: CGRect?,
        targetW: Int,
        targetH: Int,
        targetExt: String,
        quality: Int,
        rotation: Int,
        flipH: Bool,
        brightness: Double,
        contrast: Double,
        saturation: Double
    ) async throws -> URL {
        let ext = file.pathExtension.lowercased()
        let outExt = targetExt.lowercased()

        if ext == "pdf" && outExt == "pdf" {
            // PDF Page Scaling
            guard let doc = PDFDocument(url: file) else {
                throw ConversionError.conversionFailed("Could not open PDF")
            }
            let outURL = FileConverterService.shared.uniqueOutputURL(
                directory: file.deletingLastPathComponent(),
                baseName: "\(file.deletingPathExtension().lastPathComponent) Resized",
                ext: "pdf"
            )

            guard let consumer = CGDataConsumer(url: outURL as CFURL),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil) else {
                throw ConversionError.conversionFailed("Failed to create PDF context")
            }

            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i), let pageRef = page.pageRef else { continue }
                let origBox = page.bounds(for: .mediaBox)
                var newBox = CGRect(x: 0, y: 0, width: CGFloat(targetW), height: CGFloat(targetH))

                pdfContext.beginPage(mediaBox: &newBox)
                pdfContext.saveGState()

                let scaleX = CGFloat(targetW) / origBox.width
                let scaleY = CGFloat(targetH) / origBox.height
                pdfContext.scaleBy(x: scaleX, y: scaleY)

                if rotation != 0 {
                    pdfContext.translateBy(x: origBox.width / 2, y: origBox.height / 2)
                    pdfContext.rotate(by: CGFloat(rotation) * .pi / 180.0)
                    pdfContext.translateBy(x: -origBox.width / 2, y: -origBox.height / 2)
                }

                pdfContext.drawPDFPage(pageRef)
                pdfContext.restoreGState()
                pdfContext.endPage()
            }
            pdfContext.closePDF()
            return outURL
        }

        // Image Processing
        guard let imageSource = CGImageSourceCreateWithURL(file as CFURL, nil),
              var baseCG = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.conversionFailed("Could not read image file")
        }

        // 1. Apply Freeform Crop if specified
        if let norm = cropNorm {
            let pxX = round(norm.origin.x * CGFloat(baseCG.width))
            let pxY = round(norm.origin.y * CGFloat(baseCG.height))
            let pxW = round(norm.size.width * CGFloat(baseCG.width))
            let pxH = round(norm.size.height * CGFloat(baseCG.height))
            let cropRect = CGRect(x: pxX, y: pxY, width: pxW, height: pxH)
            if let cropped = baseCG.cropping(to: cropRect) {
                baseCG = cropped
            }
        }

        // 2. Render target dimensions, rotation & adjustments
        let isPerp = (rotation == 90 || rotation == 270)
        let finalW = isPerp ? targetH : targetW
        let finalH = isPerp ? targetW : targetH

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: finalW,
            height: finalH,
            bitsPerComponent: 8,
            bytesPerRow: finalW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ConversionError.conversionFailed("Could not allocate image context")
        }

        ctx.interpolationQuality = .high
        ctx.saveGState()

        ctx.translateBy(x: CGFloat(finalW) / 2, y: CGFloat(finalH) / 2)
        ctx.rotate(by: CGFloat(rotation) * .pi / 180.0)
        if flipH {
            ctx.scaleBy(x: -1, y: 1)
        }

        let drawRect = CGRect(x: -CGFloat(targetW) / 2, y: -CGFloat(targetH) / 2, width: CGFloat(targetW), height: CGFloat(targetH))

        var processedCG = baseCG
        if brightness != 0.0 || contrast != 1.0 || saturation != 1.0 {
            let ci = CIImage(cgImage: baseCG)
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(ci, forKey: kCIInputImageKey)
            filter?.setValue(brightness, forKey: kCIInputBrightnessKey)
            filter?.setValue(contrast, forKey: kCIInputContrastKey)
            filter?.setValue(saturation, forKey: kCIInputSaturationKey)
            if let outCI = filter?.outputImage {
                let ciCtx = CIContext()
                if let cg = ciCtx.createCGImage(outCI, from: outCI.extent) {
                    processedCG = cg
                }
            }
        }

        ctx.draw(processedCG, in: drawRect)
        ctx.restoreGState()

        guard let finalCG = ctx.makeImage() else {
            throw ConversionError.conversionFailed("Failed to render output image")
        }

        let baseName = "\(file.deletingPathExtension().lastPathComponent) \(cropNorm != nil ? "Cropped" : "Resized")"
        let outURL = FileConverterService.shared.uniqueOutputURL(
            directory: file.deletingLastPathComponent(),
            baseName: baseName,
            ext: outExt
        )

        if outExt == "pdf" {
            return try FileConverterService.shared.createPDFFromImages(sources: [file], destination: outURL)
        }

        return try FileConverterService.shared.saveCGImage(finalCG, to: outURL, quality: quality)
    }
}
