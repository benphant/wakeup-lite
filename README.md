# wakeup-lite · 醒着 Lite

[简体中文](#中文) · [MIT License](LICENSE)

**Keep your Mac awake with the lid closed when a task needs more time.** wakeup-lite is a small, offline macOS menu bar utility with three switches and a Liquid Glass window.

- **Stay awake with the lid closed.** Keep a download, render, or local job running when you step away.
- **Keep the built-in display on, where supported.** The app requests display wakefulness when the built-in panel is the only online display. Some Macs or macOS configurations turn off the panel when the lid closes.
- **Stop on low battery.** Automatically release wakefulness below 10% while running on battery.

Left-click the menu bar icon to toggle. Right-click for the menu. Closing the window keeps the current session running. Turning the main switch off or quitting releases the app's wakefulness request.

## Download

Get the DMG from [GitHub Releases](https://github.com/benphant/wakeup-lite/releases/latest). Requires macOS 26 or later. The disk image contains builds for Apple silicon and Intel. Drag the app into Applications and open it there.

To browse or build the source, open `AwakeLite.xcodeproj` in Xcode.

## 中文

**醒着 Lite 是一个离线的 Mac 菜单栏防休眠工具。** 下载、导出或跑本地任务时，可以让 Mac 合盖后继续工作。界面是一块原生玻璃，只有三个开关：

1. **合盖后保持 Mac 清醒**。关闭开关或退出应用会释放本次控制。
2. **合盖后保持内建屏幕常亮**。只有系统仍让内屏在线、且它是唯一在线屏幕时，应用才请求常亮。内屏被系统关掉时会显示不可用。
3. **低电量时自动停止**。仅使用电池且电量低于 10% 时结束。

需要 **macOS 26 或以上**。到 [GitHub Releases](https://github.com/benphant/wakeup-lite/releases/latest) 下载 DMG，把应用拖进「应用程序」后打开。

菜单栏左键切换、右键打开菜单。关窗口后继续运行，退出应用释放防休眠。应用无需账号，离线运行，恢复记录和诊断日志只保存在本机。合盖运行时请留出散热空间。

欢迎提交建议或问题。报告合盖行为时，请附上 Mac 型号、macOS 版本、是否接电及是否连接外屏。

## License

[MIT](LICENSE)
