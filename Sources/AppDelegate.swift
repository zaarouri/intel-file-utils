import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory agent (no dock icon clutter, stays responsive)
        NSApp.setActivationPolicy(.accessory)

        // Setup Menu Bar Status Item
        StatusItemController.shared.setup()

        // Start global drag gesture monitor
        DragMonitorService.shared.startMonitoring()

        // Listen for Float shelf notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowFloatShelf(_:)),
            name: .tangerineShowFloatShelf,
            object: nil
        )

        // Prompt accessibility if not yet granted
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("Note: floating-utils-intel-mac requires Accessibility permission in System Settings -> Privacy & Security -> Accessibility to observe global drag events.")
        }
    }

    @objc private func handleShowFloatShelf(_ notification: Notification) {
        if let urls = notification.object as? [URL] {
            FloatShelfWindowController.shared.addFiles(urls)
        } else {
            FloatShelfWindowController.shared.showWindow(nil)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        DragMonitorService.shared.stopMonitoring()
    }
}
