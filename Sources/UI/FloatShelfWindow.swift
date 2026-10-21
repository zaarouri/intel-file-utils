import Foundation
import AppKit

@MainActor
public final class FloatShelfWindowController: NSWindowController {
    public static let shared = FloatShelfWindowController()

    private let shelfView = FloatShelfView()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 300, width: 380, height: 360),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "floating-utils-intel-mac Shelf"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

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
    }
}

public final class FloatShelfView: NSView {
    private var files: [URL] = []
    private let titleLabel = NSTextField(labelWithString: "Drop files here or hold Shift/⌘/⌃ while dragging")
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
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.cornerRadius = 12

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        addSubview(titleLabel)

        configureButton(cropWebPButton, title: "Freeform Crop & WebP...", action: #selector(cropWebPFromShelf))
        configureButton(pdfButton, title: "Convert to PDF", action: #selector(createPDFFromShelf))
        configureButton(resizeButton, title: "Resize & Edit...", action: #selector(resizeFromShelf))

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.title = "Clear Shelf"
        clearButton.bezelStyle = .recessed
        clearButton.target = self
        clearButton.action = #selector(clearShelf)
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            cropWebPButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            cropWebPButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            cropWebPButton.widthAnchor.constraint(equalToConstant: 220),

            pdfButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            pdfButton.topAnchor.constraint(equalTo: cropWebPButton.bottomAnchor, constant: 8),
            pdfButton.widthAnchor.constraint(equalToConstant: 220),

            resizeButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            resizeButton.topAnchor.constraint(equalTo: pdfButton.bottomAnchor, constant: 8),
            resizeButton.widthAnchor.constraint(equalToConstant: 220),

            clearButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            clearButton.topAnchor.constraint(equalTo: resizeButton.bottomAnchor, constant: 14)
        ])
    }

    private func configureButton(_ btn: NSButton, title: String, action: Selector) {
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.title = title
        btn.bezelStyle = .rounded
        btn.target = self
        btn.action = action
        btn.isHidden = true
        addSubview(btn)
    }

    public func addFiles(_ newFiles: [URL]) {
        files.append(contentsOf: newFiles)
        updateUI()
    }

    private func updateUI() {
        if files.isEmpty {
            titleLabel.stringValue = "Drop files here or hold Shift/⌘/⌃ while dragging"
            cropWebPButton.isHidden = true
            pdfButton.isHidden = true
            resizeButton.isHidden = true
            clearButton.isHidden = true
        } else {
            let hasImagesOrPDF = files.contains { url in
                let ext = url.pathExtension.lowercased()
                return ConversionMatrix.imageFormats.contains(ext) || ext == "pdf"
            }
            titleLabel.stringValue = "\(files.count) item(s) on shelf.\nChoose a quick tool or drag anywhere."
            cropWebPButton.isHidden = !hasImagesOrPDF
            pdfButton.title = files.count > 1 ? "Combine into PDF" : "Convert to PDF"
            pdfButton.isHidden = !hasImagesOrPDF
            resizeButton.isHidden = !hasImagesOrPDF
            clearButton.isHidden = false
        }
    }

    @objc private func clearShelf() {
        files.removeAll()
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
                    self.notify(title: "Created PDF", message: finalURL.lastPathComponent, success: true)
                    NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                }
            } catch {
                await MainActor.run {
                    self.notify(title: "PDF Creation Failed", message: error.localizedDescription, success: false)
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
        return .copy
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        addFiles(items)
        return true
    }

    private func notify(title: String, message: String, success: Bool) {
        let notif = NSUserNotification()
        notif.title = title
        notif.informativeText = message
        NSUserNotificationCenter.default.deliver(notif)
        if success {
            NSSound(named: "Glass")?.play()
        } else {
            NSSound(named: "Basso")?.play()
        }
    }
}
