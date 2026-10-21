import Foundation
import AppKit

@MainActor
public final class DragMonitorService {
    public static let shared = DragMonitorService()

    private var globalMouseMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localMouseMonitor: Any?
    private var localFlagsMonitor: Any?

    private var isDragging: Bool = false
    private var cachedDraggedFiles: [URL] = []
    private var lastFinderQueryTime: Date = .distantPast

    private init() {}

    public func startMonitoring() {
        stopMonitoring()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleFlagsEvent(event)
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .mouseMoved]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleFlagsEvent(event)
            return event
        }
    }

    public func stopMonitoring() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let f = globalFlagsMonitor { NSEvent.removeMonitor(f) }
        if let lm = localMouseMonitor { NSEvent.removeMonitor(lm) }
        if let lf = localFlagsMonitor { NSEvent.removeMonitor(lf) }
        globalMouseMonitor = nil
        globalFlagsMonitor = nil
        localMouseMonitor = nil
        localFlagsMonitor = nil
    }

    private func handleMouseEvent(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation

        if event.type == .leftMouseDragged {
            if !isDragging {
                isDragging = true
                detectDraggedFiles()
            }
            if RadialWindowController.shared.isVisible {
                RadialWindowController.shared.updateCursor(at: mouseLocation)
            }
        } else if event.type == .mouseMoved {
            if RadialWindowController.shared.isVisible {
                RadialWindowController.shared.updateCursor(at: mouseLocation)
            }
        } else if event.type == .leftMouseUp {
            if RadialWindowController.shared.isVisible {
                let files = RadialWindowController.shared.activeFiles
                if let (item, mode) = RadialWindowController.shared.commitSelection() {
                    executeSelection(item: item, mode: mode, files: files)
                } else {
                    RadialWindowController.shared.hide()
                }
            }
            isDragging = false
            cachedDraggedFiles = []
        }
    }

    private func handleFlagsEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 { // Escape
            RadialWindowController.shared.hide()
            return
        }

        guard isDragging || RadialWindowController.shared.isVisible else { return }

        let flags = event.modifierFlags
        let mouseLocation = NSEvent.mouseLocation

        if cachedDraggedFiles.isEmpty {
            detectDraggedFiles()
        }

        guard !cachedDraggedFiles.isEmpty else { return }

        if flags.contains(.shift) {
            RadialWindowController.shared.show(at: mouseLocation, mode: .conversions, files: cachedDraggedFiles)
        } else if flags.contains(.command) {
            RadialWindowController.shared.show(at: mouseLocation, mode: .tools, files: cachedDraggedFiles)
        } else if flags.contains(.control) {
            RadialWindowController.shared.show(at: mouseLocation, mode: .actions, files: cachedDraggedFiles)
        }
    }

    private func detectDraggedFiles() {
        // 1. Try drag pasteboard
        let dragPasteboard = NSPasteboard(name: .drag)
        if let urls = dragPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            cachedDraggedFiles = urls
            return
        }

        // 2. Query Finder selection via AppleScript
        if Date().timeIntervalSince(lastFinderQueryTime) > 0.3 {
            lastFinderQueryTime = Date()
            if let urls = getFinderSelection(), !urls.isEmpty {
                cachedDraggedFiles = urls
            }
        }
    }

    private func getFinderSelection() -> [URL]? {
        let scriptSource = """
        tell application "Finder"
            set selectedItems to selection as alias list
            set posixPaths to {}
            repeat with itemRef in selectedItems
                set end of posixPaths to POSIX path of itemRef
            end repeat
            return posixPaths
        end tell
        """
        guard let appleScript = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)
        guard errorDict == nil else { return nil }

        var urls: [URL] = []
        let count = result.numberOfItems
        if count > 0 {
            for i in 1...count {
                if let itemStr = result.atIndex(i)?.stringValue {
                    urls.append(URL(fileURLWithPath: itemStr))
                }
            }
        }
        return urls.isEmpty ? nil : urls
    }

    public func executeSelection(item: String, mode: RadialMode, files: [URL]) {
        guard !files.isEmpty else { return }

        Task {
            switch mode {
            case .conversions:
                if item == "pdf" && files.count > 1 {
                    let dir = files[0].deletingLastPathComponent()
                    let firstBase = files[0].deletingPathExtension().lastPathComponent
                    let outURL = FileConverterService.shared.uniqueOutputURL(directory: dir, baseName: "\(firstBase) Combined", ext: "pdf")
                    do {
                        let finalURL = try FileConverterService.shared.createPDFFromImages(sources: files, destination: outURL)
                        await MainActor.run {
                            self.showSuccessNotification(title: "Created Combined PDF", path: finalURL.path)
                            NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                        }
                    } catch {
                        await MainActor.run {
                            self.showErrorNotification(title: "PDF Creation Failed", error: error.localizedDescription)
                        }
                    }
                } else {
                    for file in files {
                        do {
                            let outURL = try await FileConverterService.shared.convert(file: file, to: item)
                            await MainActor.run {
                                self.showSuccessNotification(title: "Converted to \(item.uppercased())", path: outURL.path)
                                NSWorkspace.shared.activateFileViewerSelecting([outURL])
                            }
                        } catch {
                            await MainActor.run {
                                self.showErrorNotification(title: "Conversion Failed", error: error.localizedDescription)
                            }
                        }
                    }
                }

            case .tools:
                // Freeform Crop, Resize & Edit Interactive Popup
                if item == "cropImage" || item == "resizeImage" || item == "editImage" {
                    await MainActor.run {
                        ResizeEditorWindowController.shared.present(for: files)
                    }
                } else if item == "createPDF" {
                    let dir = files[0].deletingLastPathComponent()
                    let firstBase = files[0].deletingPathExtension().lastPathComponent
                    let baseName = files.count > 1 ? "\(firstBase) Combined" : firstBase
                    let outURL = FileConverterService.shared.uniqueOutputURL(directory: dir, baseName: baseName, ext: "pdf")
                    do {
                        let finalURL = try FileConverterService.shared.createPDFFromImages(sources: files, destination: outURL)
                        await MainActor.run {
                            let title = files.count > 1 ? "Created PDF from \(files.count) Images" : "Converted to PDF"
                            self.showSuccessNotification(title: title, path: finalURL.path)
                            NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                        }
                    } catch {
                        await MainActor.run {
                            self.showErrorNotification(title: "Create PDF Failed", error: error.localizedDescription)
                        }
                    }

                } else if item == "mergePDF" {
                    let dir = files[0].deletingLastPathComponent()
                    let firstBase = files[0].deletingPathExtension().lastPathComponent
                    let outURL = FileConverterService.shared.uniqueOutputURL(directory: dir, baseName: "\(firstBase) Merged", ext: "pdf")
                    do {
                        let finalURL = try FileConverterService.shared.mergePDFs(sources: files, destination: outURL)
                        await MainActor.run {
                            self.showSuccessNotification(title: "Merged \(files.count) PDFs", path: finalURL.path)
                            NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                        }
                    } catch {
                        await MainActor.run {
                            self.showErrorNotification(title: "Merge PDFs Failed", error: error.localizedDescription)
                        }
                    }
                } else if item == "joinVideos" {
                    do {
                        let finalURL = try await FileConverterService.shared.joinVideos(sources: files)
                        await MainActor.run {
                            self.showSuccessNotification(title: "Joined \(files.count) Videos", path: finalURL.path)
                            NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                        }
                    } catch {
                        await MainActor.run {
                            self.showErrorNotification(title: "Join Videos Failed", error: error.localizedDescription)
                        }
                    }
                } else {
                    // Other file tools
                    for file in files {
                        do {
                            let outURL: URL
                            switch item {
                            case "compress":
                                outURL = try FileConverterService.shared.compressFile(source: file)
                            case "removeMetadata":
                                outURL = try FileConverterService.shared.removeMetadata(source: file)
                            case "normalizeAudio":
                                outURL = try FileConverterService.shared.normalizeAudio(source: file)
                            case "trimAudio":
                                outURL = try await FileConverterService.shared.trimAudio(source: file)
                            case "muteVideo":
                                outURL = try await FileConverterService.shared.muteVideo(source: file)
                            case "trimVideo":
                                outURL = try await FileConverterService.shared.trimVideo(source: file)
                            case "changeVideoSpeed":
                                outURL = try await FileConverterService.shared.changeVideoSpeed(source: file)
                            case "videoSnapshots":
                                outURL = try await FileConverterService.shared.extractVideoSnapshots(source: file)
                            case "splitPDF":
                                outURL = try FileConverterService.shared.splitPDF(source: file)
                            case "organizePDF":
                                outURL = try FileConverterService.shared.organizePDF(source: file)
                            case "extractArchive":
                                outURL = try FileConverterService.shared.extractArchive(source: file)
                            default:
                                outURL = file
                            }
                            await MainActor.run {
                                let defName = ToolDefinition.all[item]?.name ?? item.capitalized
                                self.showSuccessNotification(title: "\(defName) Complete", path: outURL.path)
                                NSWorkspace.shared.activateFileViewerSelecting([outURL])
                            }
                        } catch {
                            await MainActor.run {
                                let defName = ToolDefinition.all[item]?.name ?? item.capitalized
                                self.showErrorNotification(title: "\(defName) Failed", error: error.localizedDescription)
                            }
                        }
                    }
                }

            case .actions:
                await MainActor.run {
                    FileActionsService.shared.performAction(item, on: files)
                }
            }
        }
    }

    private func showSuccessNotification(title: String, path: String) {
        let notif = NSUserNotification()
        notif.title = title
        notif.informativeText = URL(fileURLWithPath: path).lastPathComponent
        NSUserNotificationCenter.default.deliver(notif)
        NSSound(named: "Glass")?.play()
    }

    private func showErrorNotification(title: String, error: String) {
        let notif = NSUserNotification()
        notif.title = title
        notif.informativeText = error
        NSUserNotificationCenter.default.deliver(notif)
        NSSound(named: "Basso")?.play()
    }
}
