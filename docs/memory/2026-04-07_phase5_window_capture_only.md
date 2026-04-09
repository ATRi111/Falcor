# 2026-04-07 Phase5 Window Capture Only

- Phase5/后续 hybrid takeover 验证不能再用 Mogwai 内置 capture API（如 `frameCapture`）做主截图；这台机器上它可能不可用，触发时会直接报 `frameCapture extension is unavailable`，导致验证脚本中断。
- 后续需要视觉验收时，统一只走“打开 Mogwai 到目标机位并自动退出”+“窗口级截图”路径，例如 `capture_phase5_takeover_window.py` 配合 `window-render-capture`；这样既避开 API 不稳定，也能保证抓到真实窗口内容。
- 如果为了窗口截图在 Mogwai Python 脚本里自己写长时间 `while pump()/sleep()` 持窗，Windows 很容易把主窗口标成“未响应”；正确做法是脚本只负责切机位并返回，把窗口消息泵交还给 Mogwai，再由外部包装脚本等待约 30 秒截图并显式关闭进程。
