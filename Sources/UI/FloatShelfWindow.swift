import Foundation
import AppKit

@MainActor
public final class FloatShelfWindowController: NSWindowController {
    public static let shared = FloatShelfWindowController()

    private let shelfView = FloatShelfView()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 300, width: 420, height: 380),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Floating Shelf"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 380, height: 320)

        super.init(window: window)
        window.contentView = shelfView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func addFiles(_ urls: [URL]) {
        shelfView.addFiles(urls)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

public final class FloatShelfView: NSVisualEffectView {
    private var files: [URL] = []

    private let headerLabel = NSTextField(labelWithString: "Floating Shelf")
    private let statusLabel = NSTextField(labelWithString: "0 items staged")
    private let emptyPlaceholder = NSStackView()

    private let scrollView = NSScrollView()
    private let itemsStack = NSStackView()

    private let cropWebPButton = NSButton()
    private let pdfButton = NSButton()
    private let resizeButton = NSButton()
    private let clearButton = NSButton()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor

        registerForDraggedTypes([.fileURL])

        // 1. Header
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .systemFont(ofSize: 13, weight: .heavy)
        headerLabel.textColor = .white
        addSubview(headerLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = NSColor(white: 0.75, alpha: 0.9)
        addSubview(statusLabel)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.title = "Clear All"
        clearButton.bezelStyle = .recessed
        clearButton.font = .systemFont(ofSize: 11, weight: .semibold)
        clearButton.target = self
        clearButton.action = #selector(clearShelf)
        addSubview(clearButton)

        // 2. Empty State View
        emptyPlaceholder.orientation = .vertical
        emptyPlaceholder.alignment = .centerX
        emptyPlaceholder.spacing = 8
        emptyPlaceholder.translatesAutoresizingMaskIntoConstraints = false

        let emptyIcon = NSImageView()
        emptyIcon.image = NSImage(systemSymbolName: "square.dashed", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 32, weight: .light))
        emptyIcon.contentTintColor = NSColor(white: 0.6, alpha: 0.7)

        let emptyText = NSTextField(labelWithString: "Drop files here to stage across desktops\nor drag files & tap ⌃ Control")
        emptyText.font = .systemFont(ofSize: 11.5, weight: .medium)
        emptyText.alignment = .center
        emptyText.textColor = NSColor(white: 0.65, alpha: 0.8)

        emptyPlaceholder.addArrangedSubview(emptyIcon)
        emptyPlaceholder.addArrangedSubview(emptyText)
        addSubview(emptyPlaceholder)

        // 3. Staged Items Scroll List
        itemsStack.orientation = .vertical
        itemsStack.spacing = 6
        itemsStack.translatesAutoresizingMaskIntoConstraints = false
        itemsStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = itemsStack
        addSubview(scrollView)

        // 4. Action Dock
        let actionDock = NSStackView()
        actionDock.orientation = .horizontal
        actionDock.distribution = .fillEqually
        actionDock.spacing = 8
        actionDock.translatesAutoresizingMaskIntoConstraints = false

        configureActionBtn(cropWebPButton, title: "Crop & WebP", symbol: "crop", action: #selector(cropWebPFromShelf))
        configureActionBtn(pdfButton, title: "To PDF", symbol: "doc.badge.plus", action: #selector(createPDFFromShelf))
        configureActionBtn(resizeButton, title: "Resize & Edit", symbol: "slider.horizontal.3", action: #selector(resizeFromShelf))

        actionDock.addArrangedSubview(cropWebPButton)
        actionDock.addArrangedSubview(pdfButton)
        actionDock.addArrangedSubview(resizeButton)
        addSubview(actionDock)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),

            statusLabel.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: headerLabel.trailingAnchor, constant: 8),

            clearButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            emptyPlaceholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyPlaceholder.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            emptyPlaceholder.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            emptyPlaceholder.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scrollView.bottomAnchor.constraint(equalTo: actionDock.topAnchor, constant: -12),

            itemsStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -8),

            actionDock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            actionDock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            actionDock.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            actionDock.heightAnchor.constraint(equalToConstant: 32)
        ])

        updateUI()
    }

    private func configureActionBtn(_ btn: NSButton, title: String, symbol: String, action: Selector) {
        btn.title = title
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 11, weight: .bold)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        btn.imagePosition = .imageLeading
        btn.target = self
        btn.action = action
    }

    public func addFiles(_ newFiles: [URL]) {
        for url in newFiles where !files.contains(url) {
            files.append(url)
        }
        rebuildItemsList()
        updateUI()
    }

    private func rebuildItemsList() {
        for sub in itemsStack.arrangedSubviews {
            itemsStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        for (idx, file) in files.enumerated() {
            let row = makeFileChip(file: file, index: idx)
            itemsStack.addArrangedSubview(row)
        }
    }

    private func makeFileChip(file: URL, index: Int) -> NSView {
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.75).cgColor
        chip.layer?.cornerRadius = 8
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        let iconView = NSImageView()
        iconView.image = NSWorkspace.shared.icon(forFile: file.path)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: file.lastPathComponent)
        nameLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        let sizeLabel = NSTextField(labelWithString: sizeStr)
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        sizeLabel.textColor = NSColor(white: 0.75, alpha: 0.9)
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false

        let removeBtn = NSButton()
        removeBtn.bezelStyle = .recessed
        removeBtn.isBordered = false
        removeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove file")
        removeBtn.contentTintColor = NSColor(white: 0.65, alpha: 0.8)
        removeBtn.tag = index
        removeBtn.target = self
        removeBtn.action = #selector(removeFileItem(_:))
        removeBtn.translatesAutoresizingMaskIntoConstraints = false

        chip.addSubview(iconView)
        chip.addSubview(nameLabel)
        chip.addSubview(sizeLabel)
        chip.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            chip.heightAnchor.constraint(equalToConstant: 34),

            iconView.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: sizeLabel.leadingAnchor, constant: -8),

            sizeLabel.trailingAnchor.constraint(equalTo: removeBtn.leadingAnchor, constant: -6),
            sizeLabel.centerYAnchor.constraint(equalTo: chip.centerYAnchor),

            removeBtn.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -6),
            removeBtn.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            removeBtn.widthAnchor.constraint(equalToConstant: 18),
            removeBtn.heightAnchor.constraint(equalToConstant: 18)
        ])

        return chip
    }

    @objc private func removeFileItem(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < files.count else { return }
        files.remove(at: idx)
        rebuildItemsList()
        updateUI()
    }

    private func updateUI() {
        let count = files.count
        statusLabel.stringValue = "\(count) item\(count == 1 ? "" : "s") staged"
        clearButton.isHidden = (count == 0)
        emptyPlaceholder.isHidden = (count > 0)
        scrollView.isHidden = (count == 0)

        let hasImagesOrPDF = files.contains { url in
            let ext = url.pathExtension.lowercased()
            return ConversionMatrix.imageFormats.contains(ext) || ext == "pdf"
        }
        cropWebPButton.isEnabled = hasImagesOrPDF
        pdfButton.isEnabled = hasImagesOrPDF
        pdfButton.title = count > 1 ? "Combine PDF" : "To PDF"
        resizeButton.isEnabled = hasImagesOrPDF
    }

    @objc private func clearShelf() {
        files.removeAll()
        rebuildItemsList()
        updateUI()
    }

    @objc private func cropWebPFromShelf() {
        guard !files.isEmpty else { return }
        ResizeEditorWindowController.shared.present(for: files, defaultWebP: true)
    }

    @objc private func createPDFFromShelf() {
        guard !files.isEmpty else { return }
        let currentFiles = files
        Task {
            let dir = currentFiles[0].deletingLastPathComponent()
            let firstBase = currentFiles[0].deletingPathExtension().lastPathComponent
            let baseName = currentFiles.count > 1 ? "\(firstBase) Combined" : firstBase
            let outURL = FileConverterService.shared.uniqueOutputURL(directory: dir, baseName: baseName, ext: "pdf")

            do {
                let finalURL = try FileConverterService.shared.createPDFFromImages(sources: currentFiles, destination: outURL)
                await MainActor.run {
                    NotificationService.shared.notify(
                        title: currentFiles.count > 1 ? "Created PDF from \(currentFiles.count) Images" : "Converted to PDF",
                        message: finalURL.lastPathComponent,
                        success: true
                    )
                    NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                }
            } catch {
                await MainActor.run {
                    NotificationService.shared.notify(
                        title: "PDF Creation Failed",
                        message: error.localizedDescription,
                        success: false
                    )
                }
            }
        }
    }

    @objc private func resizeFromShelf() {
        guard !files.isEmpty else { return }
        ResizeEditorWindowController.shared.present(for: files, defaultWebP: false)
    }

    // Drag and Drop destination handling
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = NSColor.systemOrange.cgColor
        layer?.borderWidth = 2.0
        return .copy
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        layer?.borderWidth = 1.0
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        layer?.borderWidth = 1.0
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        addFiles(items)
        return true
    }
}
