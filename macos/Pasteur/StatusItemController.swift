import AppKit

final class StatusItemController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private weak var target: AnyObject?
    private let visualizeAction: Selector

    var button: NSStatusBarButton? {
        statusItem.button
    }

    init(target: AnyObject, visualizeAction: Selector, preferencesAction: Selector, quitAction: Selector) {
        self.target = target
        self.visualizeAction = visualizeAction
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = ""

        menu = NSMenu()
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: preferencesAction,
            keyEquivalent: ","
        )
        preferencesItem.target = target
        menu.addItem(preferencesItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit",
            action: quitAction,
            keyEquivalent: "q"
        )
        quitItem.target = target
        menu.addItem(quitItem)

        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        applyStatusIcon()
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        _ = target?.perform(visualizeAction)
    }

    private func applyStatusIcon() {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "pasteur_icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            statusItem.button?.title = "Pasteur"
            return
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image
        statusItem.button?.imageScaling = .scaleProportionallyDown
    }
}
