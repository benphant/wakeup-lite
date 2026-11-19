import SwiftUI
import AppKit

private let liteWindowSide: CGFloat = 260

private final class LiteGlassWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class LiteDelegate: NSObject, NSApplicationDelegate {
    private let model = LiteModel()
    private var statusItem: LiteStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentSize = NSSize(width: liteWindowSide, height: liteWindowSide)
        let window = LiteGlassWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "醒着 Lite"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = false

        let bounds = NSRect(origin: .zero, size: contentSize)
        let cornerRadius: CGFloat = 23
        let bleed: CGFloat = 5
        // Keep the glass material while clipping its built-in rim outside the window.
        let surface = NSView(frame: bounds)
        surface.wantsLayer = true
        surface.layer?.cornerRadius = cornerRadius
        surface.layer?.masksToBounds = true

        let glass = NSGlassEffectView(frame: bounds.insetBy(dx: -bleed, dy: -bleed))
        glass.cornerRadius = cornerRadius + bleed
        let glassContent = NSView(frame: NSRect(origin: .zero, size: glass.frame.size))
        let hostingView = NSHostingView(rootView: LiteView(
            model: model, bottomInset: 10 + 10 / window.backingScaleFactor,
            close: { [weak window] in window?.close() }
        ))
        hostingView.frame = bounds.offsetBy(dx: bleed, dy: bleed)
        glassContent.addSubview(hostingView)
        glass.contentView = glassContent
        surface.addSubview(glass)
        window.contentView = surface
        window.center()
        self.window = window
        statusItem = LiteStatusItem(model: model) { [weak self] in self?.show() }
        show()
    }

    private func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.stop(); statusItem?.remove() }
}

@main struct AwakeLiteApp: App {
    @NSApplicationDelegateAdaptor(LiteDelegate.self) var delegate
    init() {
        if CommandLine.arguments.contains("--self-test") {
            _ = NSApplication.shared
            do { try LiteTests.run(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        Settings { EmptyView() }
    }
}
struct LiteView: View {
    @ObservedObject var model: LiteModel
    let bottomInset: CGFloat
    let close: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            Text("醒着 Lite")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                row("合盖后保持 Mac 清醒", value: Binding(
                    get: { model.awake || model.connecting },
                    set: { value in
                        if value != (model.awake || model.connecting) { model.toggle() }
                    }
                ))
                Divider()
                row("合盖后保持内建屏幕常亮", value: $model.displayOn)
                    .disabled(!model.awake)
                Divider()
                row("低电量时自动停止", value: $model.lowBattery)
            }

            Divider()

            Spacer(minLength: 0)

            VStack(spacing: 5) {
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if model.canPrepareService {
                    Button("设置合盖辅助服务") { model.prepareService() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular)
                } else if model.lowBattery {
                    Text("使用电池时低于 10% 停止")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 17)
        .padding(.top, 21)
        .padding(.bottom, bottomInset)
        .frame(width: liteWindowSide, height: liteWindowSide)
        .overlay(alignment: .topLeading) {
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: .command)
            .accessibilityLabel("关闭窗口")
            .padding(10)
        }
    }

    private func row(_ title: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch)
        }
        .frame(minHeight: 37)
    }
}
