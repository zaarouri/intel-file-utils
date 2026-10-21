import Foundation
import AppKit

@MainActor
public final class RadialWindowController: NSWindowController {
    public static let shared = RadialWindowController()

    private let radialView = RadialMenuView()
    private var currentCenter: CGPoint = .zero
    public private(set) var isVisible: Bool = false
    public var activeFiles: [URL] = []
    public var currentMode: RadialMode = .conversions

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: RadialGeometry.totalSize, height: RadialGeometry.totalSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true

        super.init(window: panel)
        panel.contentView = radialView

        radialView.onCommitSelection = { [weak self] item, mode, urls in
            self?.hide()
            DragMonitorService.shared.executeSelection(item: item, mode: mode, files: urls)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(at screenPoint: CGPoint, mode: RadialMode, files: [URL]) {
        guard !files.isEmpty else { return }
        self.activeFiles = files
        self.currentMode = mode
        self.currentCenter = screenPoint

        let count = files.count
        let ext = files[0].pathExtension.lowercased()

        let items: [String]
        switch mode {
        case .conversions:
            items = ConversionMatrix.conversions(for: ext)
        case .tools:
            items = ConversionMatrix.tools(for: ext, fileCount: count)
        case .actions:
            items = ConversionMatrix.allActions
        }

        guard !items.isEmpty else {
            hide()
            return
        }

        radialView.mode = mode
        radialView.items = items
        radialView.selectedIndex = nil
        radialView.centerTitle = mode.rawValue.uppercased()
        radialView.centerSubtitle = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"

        let size = RadialGeometry.totalSize
        let origin = CGPoint(x: screenPoint.x - (size / 2), y: screenPoint.y - (size / 2))
        window?.setFrame(NSRect(origin: origin, size: CGSize(width: size, height: size)), display: true)
        window?.orderFrontRegardless()
        isVisible = true
    }

    public func updateCursor(at screenPoint: CGPoint) {
        guard isVisible, let window = window else { return }
        let windowFrame = window.frame
        let localPoint = CGPoint(
            x: screenPoint.x - windowFrame.origin.x,
            y: screenPoint.y - windowFrame.origin.y
        )
        radialView.updateSelection(at: localPoint)
    }

    public func commitSelection() -> (item: String, mode: RadialMode)? {
        guard isVisible, let idx = radialView.selectedIndex, idx < radialView.items.count else {
            hide()
            return nil
        }
        let selectedItem = radialView.items[idx]
        let mode = currentMode
        hide()
        return (selectedItem, mode)
    }

    public func hide() {
        window?.orderOut(nil)
        isVisible = false
        radialView.selectedIndex = nil
        activeFiles = []
    }
}
