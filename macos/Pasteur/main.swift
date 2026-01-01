import AppKit

print("[Pasteur] Starting app...")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
