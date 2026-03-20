import Cocoa
import Foundation

enum TextPaster {
    /// Check if we have accessibility permission
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func paste(_ text: String) {
        // Always copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Log.d("TextPaster: copied to clipboard, length=\(text.count)")

        if hasAccessibilityPermission {
            // Auto-paste via osascript
            usleep(300_000)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"System Events\" to keystroke \"v\" using command down"]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    Log.d("TextPaster: auto-pasted OK")
                } else {
                    Log.d("TextPaster: osascript failed")
                }
            } catch {
                Log.d("TextPaster: error: \(error)")
            }
        } else {
            Log.d("TextPaster: no accessibility permission, clipboard only")
        }
    }
}
