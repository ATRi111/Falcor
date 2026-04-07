# 2026-04-06 Plan6 Phase5 Capture Validation Pitfalls

- Phase5 takeover 机位的 Mogwai 截图如果在启动后 10~18 秒内就抓，仍可能只拿到白窗或 `Mogwai [未响应]` 的加载阶段画面；这不是渲染结果本身，验证截图必须等到场景和 shader 首帧都稳定后，再让用户手动截图或显式延长 hold 时间。
- `window-render-capture` 技能脚本在这台机器上对 Mogwai 可能遇到 `Loading Configuration` 多窗口歧义，或者直接报 `Failed to query window bounds`；需要窗口证据时优先让用户手动截图，或者自行按主窗口句柄用 `GetWindowRect + CopyFromScreen` 做兜底，但不要把早期白窗误当成结果。
