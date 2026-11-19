# wakeup-lite · 醒着 Lite

[简体中文](#中文) · [MIT License](LICENSE)

**Keep your Mac awake with the lid closed when a task needs more time.** wakeup-lite is a small, offline macOS menu bar utility with three switches and a Liquid Glass window.

- **Stay awake with the lid closed.** Keep a download, render, or local job running when you step away.
- **Keep the built-in display on, where supported.** The app requests display wakefulness when the built-in panel is the only online display. Some Macs or macOS configurations turn off the panel when the lid closes.
- **Stop on low battery.** Automatically release wakefulness below 10% while running on battery.

Left-click the menu bar icon to toggle. Right-click for the menu. Closing the window keeps the current session running. Turning the main switch off or quitting releases the app's wakefulness request.

## Build and run

Requires macOS 26 or later, Xcode with the macOS 26 SDK or later, and Python 3. Open `AwakeLite.xcodeproj` to build and preview in Xcode. Build and run the self-checks from the terminal with:

```sh
./Scripts/build.sh
```

Lid control needs the app and its bundled helper signed by the same Apple development team. Set the team for both targets in Xcode, or use:

```sh
AWAKE_LITE_TEAM=YOUR_TEAM_ID ./Scripts/build.sh
```

Move the signed app to Applications. In wakeup-lite, click **设置合盖辅助服务** (Set up lid helper), follow the macOS approval prompt, then turn on the first switch. The current interface is in Simplified Chinese. The helper records the previous sleep setting before taking control and restores it when the session ends or its connection times out. Leave room for ventilation when running a closed Mac.

The source release builds for Apple silicon and Intel. Hardware validation has focused on Apple silicon. To make a local DMG, run `AWAKE_LITE_TEAM=YOUR_TEAM_ID ./Scripts/package.sh`. The generated DMG is not notarized by default.

## 中文

**醒着 Lite 是一个离线的 Mac 菜单栏防休眠工具。** 下载、导出或跑本地任务时，可以让 Mac 合盖后继续工作。界面是一块原生玻璃，只有三个开关：

1. **合盖后保持 Mac 清醒**。首次使用需签名并授权辅助服务。关闭开关或退出应用会释放本次控制。
2. **合盖后保持内建屏幕常亮**。只有系统仍让内屏在线、且它是唯一在线屏幕时，应用才请求常亮。内屏被系统关掉时会显示不可用。
3. **低电量时自动停止**。仅使用电池且电量低于 10% 时结束。

需要 **macOS 26 或以上**。用 Xcode 打开 `AwakeLite.xcodeproj`，为主程序和辅助进程配置同一个 Apple 开发团队。也可运行 `AWAKE_LITE_TEAM=你的团队ID ./Scripts/build.sh`。把构建好的应用放入「应用程序」，首次点击「设置合盖辅助服务」，按系统提示授权。

菜单栏左键切换、右键打开菜单。关窗口后继续运行，退出应用释放防休眠。应用无需账号，离线运行，恢复记录和诊断日志只保存在本机。合盖运行时请留出散热空间。

欢迎提交建议或问题。报告合盖行为时，请附上 Mac 型号、macOS 版本、是否接电及是否连接外屏。

## License

[MIT](LICENSE)
