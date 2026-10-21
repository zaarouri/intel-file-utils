import Foundation
import AppKit

public final class FileActionsService: @unchecked Sendable {
    public static let shared = FileActionsService()

    private init() {}

    @MainActor
    public func performAction(_ actionId: String, on urls: [URL]) {
        guard !urls.isEmpty else { return }

        switch actionId {
        case "airDrop":
            if let sharingService = NSSharingService(named: .sendViaAirDrop) {
                sharingService.perform(withItems: urls)
            }

        case "copy":
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls as [NSURL])
            showNotification(title: "Copied to Clipboard", message: "\(urls.count) item(s) ready to paste.")

        case "copyPath":
            let pb = NSPasteboard.general
            pb.clearContents()
            let paths = urls.map { $0.path }.joined(separator: "\n")
            pb.setString(paths, forType: .string)
            showNotification(title: "Path Copied", message: urls.count == 1 ? urls[0].path : "\(urls.count) paths copied.")

        case "openTerminal":
            let targetDir = urls[0].hasDirectoryPath ? urls[0] : urls[0].deletingLastPathComponent()
            NSWorkspace.shared.open(targetDir)
            let config = NSWorkspace.OpenConfiguration()
            if let termURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                NSWorkspace.shared.open([targetDir], withApplicationAt: termURL, configuration: config, completionHandler: nil)
            }

        case "move":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            panel.message = "Choose destination folder"
            if panel.runModal() == .OK, let dest = panel.url {
                for u in urls {
                    let destFile = dest.appendingPathComponent(u.lastPathComponent)
                    try? FileManager.default.moveItem(at: u, to: destFile)
                }
                showNotification(title: "Moved", message: "Moved \(urls.count) item(s) to \(dest.lastPathComponent).")
            }

        case "float":
            NotificationCenter.default.post(name: .tangerineShowFloatShelf, object: urls)

        default:
            break
        }
    }

    private func showNotification(title: String, message: String) {
        let notif = NSUserNotification()
        notif.title = title
        notif.informativeText = message
        NSUserNotificationCenter.default.deliver(notif)
    }
}

extension Notification.Name {
    public static let tangerineShowFloatShelf = Notification.Name("tangerineShowFloatShelf")
}
