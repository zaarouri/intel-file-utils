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
            name: .intelFileUtilsShowFloatShelf,
            object: nil
        )

        // Check accessibility permissions
        checkAccessibilityPermissions()
    }

    private func checkAccessibilityPermissions() {
        let isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            let hasPromptedKey = "hasPromptedAccessibilityOnboarding"
            if !UserDefaults.standard.bool(forKey: hasPromptedKey) {
                UserDefaults.standard.set(true, forKey: hasPromptedKey)

                let alert = NSAlert()
                alert.messageText = "Welcome to Intel File Utils"
                alert.informativeText = "Intel File Utils allows you to convert, crop, and manipulate files with zero clicks simply by dragging in Finder and holding Shift, ⌘, or ⌃.\n\nTo detect these drag gestures globally, macOS requires Accessibility permission."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")

                if let icon = NSApp.applicationIconImage {
                    alert.icon = icon
                }

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
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
