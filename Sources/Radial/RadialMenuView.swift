import Foundation
import AppKit

public final class RadialMenuView: NSView {
    public var mode: RadialMode = .conversions {
        didSet { needsDisplay = true }
    }
    public var items: [String] = [] {
        didSet { needsDisplay = true }
    }
    public var selectedIndex: Int? = nil {
        didSet {
            if oldValue != selectedIndex {
                needsDisplay = true
            }
        }
    }

    public var centerTitle: String = "CONVERT"
    public var centerSubtitle: String = ""

    public var onCommitSelection: ((String, RadialMode, [URL]) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    public override var isFlipped: Bool { false }

    public func updateSelection(at localPoint: CGPoint) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let index = RadialGeometry.hitTest(point: localPoint, center: center, count: items.count)

        if index != selectedIndex {
            selectedIndex = index
            if let idx = index {
                let item = items[idx]
                switch mode {
                case .conversions:
                    centerTitle = "TO " + item.uppercased()
                    centerSubtitle = "Convert Format"
                case .tools:
                    if let def = ToolDefinition.all[item] {
                        centerTitle = def.title
                        centerSubtitle = def.name
                    } else {
                        centerTitle = item.uppercased()
                        centerSubtitle = "File Tool"
                    }
                case .actions:
                    if let def = ActionDefinition.all[item] {
                        centerTitle = def.title
                        centerSubtitle = def.name
                    } else {
                        centerTitle = item.uppercased()
                        centerSubtitle = "File Action"
                    }
                }
                NSSound(named: "Tink")?.play()
            } else {
                centerTitle = mode.rawValue.uppercased()
                let files = RadialWindowController.shared.activeFiles
                centerSubtitle = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
            }
        }
    }

    // MARK: - Drag Destination Support
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateSelection(at: sender.draggingLocation)
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateSelection(at: sender.draggingLocation)
        return .copy
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) {
        selectedIndex = nil
        centerTitle = mode.rawValue.uppercased()
        let files = RadialWindowController.shared.activeFiles
        centerSubtitle = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return false
        }
        if let idx = selectedIndex, idx < items.count {
            let item = items[idx]
            let m = self.mode
            onCommitSelection?(item, m, urls)
            return true
        }
        return false
    }

    // MARK: - Mouse Click Handling
    public override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        updateSelection(at: localPoint)
        if let idx = selectedIndex, idx < items.count {
            let item = items[idx]
            let m = self.mode
            let files = RadialWindowController.shared.activeFiles
            onCommitSelection?(item, m, files)
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let count = items.count

        // 1. Draw Glassmorphism Outer Ring Backdrop
        ctx.saveGState()
        let ringPath = CGMutablePath()
        ringPath.addArc(center: center, radius: RadialGeometry.innerRadius - 4, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ringPath.addArc(center: center, radius: RadialGeometry.outerRadius + 8, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        
        ctx.addPath(ringPath)
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. Draw Center Disc
        ctx.saveGState()
        let centerRect = CGRect(
            x: center.x - RadialGeometry.innerRadius + 4,
            y: center.y - RadialGeometry.innerRadius + 4,
            width: (RadialGeometry.innerRadius - 4) * 2,
            height: (RadialGeometry.innerRadius - 4) * 2
        )
        let centerPath = CGPath(ellipseIn: centerRect, transform: nil)
        
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor(white: 0, alpha: 0.25).cgColor)
        ctx.addPath(centerPath)
        ctx.setFillColor(NSColor(white: 0.18, alpha: 0.88).cgColor)
        ctx.fillPath()

        ctx.addPath(centerPath)
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.2).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.restoreGState()

        // 3. Draw Petals
        for i in 0..<count {
            let isSelected = (selectedIndex == i)
            let petalPath = RadialGeometry.petalPath(index: i, count: count, center: center)

            ctx.saveGState()
            ctx.addPath(petalPath)

            if isSelected {
                ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 12, color: NSColor.systemOrange.withAlphaComponent(0.6).cgColor)
                ctx.setFillColor(NSColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 0.95).cgColor)
                ctx.fillPath()

                ctx.addPath(petalPath)
                ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.9).cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokePath()
            } else {
                ctx.setFillColor(NSColor(white: 0.96, alpha: 0.85).cgColor)
                ctx.fillPath()

                ctx.addPath(petalPath)
                ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.4).cgColor)
                ctx.setLineWidth(1.0)
                ctx.strokePath()
            }
            ctx.restoreGState()

            // 4. Draw Petal Content
            let item = items[i]
            let iconPos = RadialGeometry.iconCenter(for: i, count: count, center: center)
            drawPetalContent(item: item, index: i, at: iconPos, isSelected: isSelected)
        }

        // 5. Draw Center Information
        drawCenterText(center: center)
    }

    private func drawPetalContent(item: String, index: Int, at pos: CGPoint, isSelected: Bool) {
        let title: String
        var symbolName: String? = nil

        switch mode {
        case .conversions:
            title = item.uppercased()
        case .tools:
            if let def = ToolDefinition.all[item] {
                title = def.title
                symbolName = def.symbol
            } else {
                title = item.uppercased()
            }
        case .actions:
            if let def = ActionDefinition.all[item] {
                title = def.title
                symbolName = def.symbol
            } else {
                title = item.uppercased()
            }
        }

        let textColor = isSelected ? NSColor.white : NSColor(white: 0.15, alpha: 0.95)

        if let symbol = symbolName, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let symImg = img.withSymbolConfiguration(config) ?? img
            let imgSize = CGSize(width: 18, height: 18)
            let imgRect = CGRect(x: pos.x - imgSize.width / 2, y: pos.y - 2, width: imgSize.width, height: imgSize.height)
            
            symImg.lockFocus()
            textColor.set()
            let r = NSRect(origin: .zero, size: symImg.size)
            r.fill(using: .sourceAtop)
            symImg.unlockFocus()
            
            symImg.draw(in: imgRect)

            let font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let str = NSAttributedString(string: title, attributes: attrs)
            let strSize = str.size()
            let strRect = CGRect(x: pos.x - strSize.width / 2, y: pos.y - 13, width: strSize.width, height: strSize.height)
            str.draw(in: strRect)
        } else {
            let font = NSFont.systemFont(ofSize: 12.0, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let str = NSAttributedString(string: title, attributes: attrs)
            let strSize = str.size()
            let strRect = CGRect(x: pos.x - strSize.width / 2, y: pos.y - strSize.height / 2, width: strSize.width, height: strSize.height)
            str.draw(in: strRect)
        }
    }

    private func drawCenterText(center: CGPoint) {
        let titleFont = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        let subFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)

        let titleStr = NSAttributedString(string: centerTitle, attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.white
        ])
        let subStr = NSAttributedString(string: centerSubtitle, attributes: [
            .font: subFont,
            .foregroundColor: NSColor(white: 0.8, alpha: 0.9)
        ])

        let titleSize = titleStr.size()
        let subSize = subStr.size()
        let totalH = titleSize.height + (centerSubtitle.isEmpty ? 0 : subSize.height + 2)

        let titleY = center.y - (totalH / 2) + (centerSubtitle.isEmpty ? 0 : subSize.height + 2)
        let titleRect = CGRect(x: center.x - titleSize.width / 2, y: titleY, width: titleSize.width, height: titleSize.height)
        titleStr.draw(in: titleRect)

        if !centerSubtitle.isEmpty {
            let subY = titleY - subSize.height - 2
            let subRect = CGRect(x: center.x - subSize.width / 2, y: subY, width: subSize.width, height: subSize.height)
            subStr.draw(in: subRect)
        }
    }
}
