import Cocoa
import Foundation

NSLog("[VibeMic] Starting...")
let app = NSApplication.shared
NSLog("[VibeMic] NSApplication created")
let delegate = AppDelegate()
app.delegate = delegate
NSLog("[VibeMic] Running event loop")
app.run()
