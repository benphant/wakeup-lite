import AppKit
import Combine

@MainActor final class LiteStatusItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: 24)
    private let model: LiteModel
    private let open: () -> Void
    private var subscription: AnyCancellable?
    init(model: LiteModel, open: @escaping () -> Void) {
        self.model = model; self.open = open; super.init()
        item.button?.target = self; item.button?.action = #selector(click)
        item.button?.sendAction(on: [.leftMouseUp,.rightMouseUp])
        subscription = model.$awake.sink { [weak self] awake in self?.update(awake) }
    }
    func remove() { NSStatusBar.system.removeStatusItem(item) }
    private func update(_ awake: Bool) {
        let image = NSImage(systemSymbolName: awake ? "power.circle.fill" : "power.circle", accessibilityDescription: awake ? "防休眠已开启" : "防休眠已关闭")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.contentTintColor = nil
        item.button?.toolTip = awake ? "醒着Lite · 已开启\n左键结束，右键菜单" : "醒着Lite · 已关闭\n左键开启，右键菜单"
        item.button?.setAccessibilityLabel(awake ? "醒着Lite已开启" : "醒着Lite已关闭")
    }

    @objc private func click() {
        guard let event=NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            let menu=NSMenu()
            add(model.awake ? "结束本次" : "开始醒着", #selector(toggle), to:menu)
            add("打开醒着Lite", #selector(show), to:menu)
            menu.addItem(.separator())
            add("退出醒着Lite", #selector(quit), to:menu)
            if let button=item.button { item.menu=menu; button.performClick(nil); item.menu=nil }
        } else { model.toggle() }
    }
    private func add(_ name:String,_ action:Selector,to menu:NSMenu) { let item=NSMenuItem(title:name,action:action,keyEquivalent:"");item.target=self;menu.addItem(item) }
    @objc private func toggle() { model.toggle() }
    @objc private func show() { open() }
    @objc private func quit() { NSApp.terminate(nil) }
}
