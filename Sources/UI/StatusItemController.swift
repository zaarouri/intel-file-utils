import Foundation
import AppKit

@MainActor
public final class StatusItemController: NSObject {
    public static let shared = StatusItemController()

    private var statusItem: NSStatusItem?

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        if let image = loadMenuIcon() {
            button.image = image
        } else {
            button.title = "⚡️"
        }

        button.toolTip = "Intel File Utils — Drag file & tap Shift (Convert), ⌘ (Tools), or ⌃ (Actions)"
        buildMenu()
    }

    private func loadMenuIcon() -> NSImage? {
        if let iconURL = Bundle.main.url(forResource: "menu_icon", withExtension: "png") ??
                         Bundle.main.url(forResource: "menu_icon@2x", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        // Relative executable fallback (works in standalone CLI or debug builds)
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources") {
            let resFile = execDir.appendingPathComponent("menu_icon.png")
            if let image = NSImage(contentsOf: resFile) {
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }

        return nil
    }

    public func buildMenu() {
        let menu = NSMenu()

        // 1. App Title & Architecture
        let titleItem = NSMenuItem(title: "Intel File Utils (v1.0.0 • x86_64)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        // 2. Permission Status Indicator
        let isTrusted = AXIsProcessTrusted()
        let statusTitle = isTrusted ? "● Zero-Click Gestures: Active" : "▲ Accessibility Permission Needed"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: isTrusted ? nil : #selector(openAccessibilitySettings), keyEquivalent: "")
        statusMenuItem.target = self
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Core Quick Utilities
        let cropItem = NSMenuItem(title: "Freeform Crop & Resize...", action: #selector(cropImagesAction), keyEquivalent: "c")
        cropItem.target = self
        menu.addItem(cropItem)

        let webpItem = NSMenuItem(title: "Convert Image(s) to WebP...", action: #selector(convertToWebPAction), keyEquivalent: "w")
        webpItem.target = self
        menu.addItem(webpItem)

        let pdfItem = NSMenuItem(title: "Convert Image(s) to PDF...", action: #selector(convertImagesToPDF), keyEquivalent: "p")
        pdfItem.target = self
        menu.addItem(pdfItem)

        let resizeItem = NSMenuItem(title: "Resize & Scale (Image / PDF)...", action: #selector(resizeImagesAction), keyEquivalent: "r")
        resizeItem.target = self
        menu.addItem(resizeItem)

        let mergePDFItem = NSMenuItem(title: "Merge Multiple PDFs...", action: #selector(mergePDFsAction), keyEquivalent: "m")
        mergePDFItem.target = self
        menu.addItem(mergePDFItem)

        let convertItem = NSMenuItem(title: "Quick Convert Any File...", action: #selector(quickConvert), keyEquivalent: "o")
        convertItem.target = self
        menu.addItem(convertItem)

        let shelfItem = NSMenuItem(title: "Open Floating Shelf...", action: #selector(openShelf), keyEquivalent: "s")
        shelfItem.target = self
        menu.addItem(shelfItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Zero-Click Gesture Cheatsheet
        let cheatHeader = NSMenuItem(title: "Zero-Click Gestures (while dragging in Finder):", action: nil, keyEquivalent: "")
        cheatHeader.isEnabled = false
        menu.addItem(cheatHeader)

        let cheatShift = NSMenuItem(title: "  ⇧ Shift: Conversions (WebP, PDF, PNG, JPG, MP3, MP4)", action: nil, keyEquivalent: "")
        cheatShift.isEnabled = false
        menu.addItem(cheatShift)

        let cheatCmd = NSMenuItem(title: "  ⌘ Command: Tools (Freeform Crop, Resize, PDF, Compress)", action: nil, keyEquivalent: "")
        cheatCmd.isEnabled = false
        menu.addItem(cheatCmd)

        let cheatCtrl = NSMenuItem(title: "  ⌃ Control: Actions (Floating Shelf, AirDrop, Copy, Path)", action: nil, keyEquivalent: "")
        cheatCtrl.isEnabled = false
        menu.addItem(cheatCtrl)

        menu.addItem(NSMenuItem.separator())

        // 5. About & Settings
        let aboutItem = NSMenuItem(title: "About Intel File Utils...", action: #selector(showAboutDialog), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let permItem = NSMenuItem(title: "Check Accessibility Permissions...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Intel File Utils", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "Intel File Utils"
        alert.informativeText = """
        Version 1.0.0 (Intel x86_64)
        An open-source, zero-click file conversion & manipulation tool inspired by Tangerine, engineered 100% offline for Intel Macs.

        • GitHub: https://github.com/zaarouri/intel-file-utils
        • Open Source: MIT License
        • Author: @zaarouri
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Visit GitHub")
        alert.addButton(withTitle: "OK")

        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/zaarouri/intel-file-utils") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func cropImagesAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select image or PDF to crop freely"
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .bmp, .webP, .pdf]

        if panel.runModal() == .OK {
            let files = panel.urls
            guard !files.isEmpty else { return }
            ResizeEditorWindowController.shared.present(for: files, defaultWebP: true)
        }
    }

    @objc private func convertToWebPAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select image(s) to convert directly to WebP"
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .bmp]

        if panel.runModal() == .OK {
            let files = panel.urls
            guard !files.isEmpty else { return }

            Task {
                for file in files {
                    let outURL = FileConverterService.shared.uniqueOutputURL(
                        directory: file.deletingLastPathComponent(),
                        baseName: file.deletingPathExtension().lastPathComponent,
                        ext: "webp"
                    )
                    do {
                        let finalURL = try FileConverterService.shared.convertWithPythonPillow(source: file, destination: outURL)
                        await MainActor.run {
                            NotificationService.shared.notify(
                                title: "Converted to WebP",
                                message: finalURL.lastPathComponent,
                                success: true
                            )
                            NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                        }
                    } catch {
                        await MainActor.run {
                            NotificationService.shared.notify(
                                title: "WebP Conversion Failed",
                                message: error.localizedDescription,
                                success: false
                            )
                        }
                    }
                }
            }
        }
    }

    @objc private func resizeImagesAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select an image or PDF to resize and edit"
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .bmp, .webP, .pdf]

        if panel.runModal() == .OK {
            let files = panel.urls
            guard !files.isEmpty else { return }
            ResizeEditorWindowController.shared.present(for: files, defaultWebP: false)
        }
    }

    @objc private func convertImagesToPDF() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select one or more images to convert into a PDF"
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .bmp, .webP]

        if panel.runModal() == .OK {
            let files = panel.urls
            guard !files.isEmpty else { return }

            Task {
                let dir = files[0].deletingLastPathComponent()
                let firstBase = files[0].deletingPathExtension().lastPathComponent
                let baseName = files.count > 1 ? "\(firstBase) Combined" : firstBase
                let outURL = FileConverterService.shared.uniqueOutputURL(directory: dir, baseName: baseName, ext: "pdf")

                do {
                    let finalURL = try FileConverterService.shared.createPDFFromImages(sources: files, destination: outURL)
                    await MainActor.run {
                        let title = files.count > 1 ? "Created PDF from \(files.count) Images" : "Converted Image to PDF"
                        NotificationService.shared.notify(title: title, message: finalURL.lastPathComponent, success: true)
                        NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                    }
                } catch {
                    await MainActor.run {
                        NotificationService.shared.notify(title: "PDF Conversion Failed", message: error.localizedDescription, success: false)
                    }
                }
            }
        }
    }

    @objc private func mergePDFsAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select two or more PDFs to merge"
        panel.allowedContentTypes = [.pdf]

        if panel.runModal() == .OK {
            let files = panel.urls
            guard files.count >= 2 else { return }

            Task {
                let dir = files[0].deletingLastPathComponent()
                let firstBase = files[0].deletingPathExtension().lastPathComponent
                let outURL = FileConverterService.shared.uniqueOutputURL(directory: dir, baseName: "\(firstBase) Merged", ext: "pdf")

                do {
                    let finalURL = try FileConverterService.shared.mergePDFs(sources: files, destination: outURL)
                    await MainActor.run {
                        NotificationService.shared.notify(title: "Merged \(files.count) PDFs", message: finalURL.lastPathComponent, success: true)
                        NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                    }
                } catch {
                    await MainActor.run {
                        NotificationService.shared.notify(title: "Merge PDFs Failed", message: error.localizedDescription, success: false)
                    }
                }
            }
        }
    }

    @objc private func openShelf() {
        FloatShelfWindowController.shared.showWindow(nil)
        FloatShelfWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quickConvert() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a file to convert"
        if panel.runModal() == .OK, let fileURL = panel.url {
            let center = CGPoint(x: NSScreen.main?.frame.midX ?? 400, y: NSScreen.main?.frame.midY ?? 400)
            RadialWindowController.shared.show(at: center, mode: .conversions, files: [fileURL])
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
