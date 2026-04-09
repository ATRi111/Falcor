# Phase5 Window Capture Only Handoff

## 模块职责

把 Phase5 以及后续 hybrid takeover 的视觉验证规则固定为“仅允许窗口截图”，避免再使用 Mogwai 内置 capture API 造成错误截图或脚本中断。

## 本轮落地

- `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\capture_phase5_tonemapper_output.py`
  - 改成显式拒绝运行，并提示改用 `capture_phase5_takeover_window.py` + `window-render-capture`。
- `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\capture_phase5_takeover_window.py`
  - 外部截图模式下不再用长时间 Python 循环持窗，而是在机位/settle 完成后直接返回，把窗口控制权交回 Mogwai，避免主窗口变成 `Mogwai [未响应]`。
- `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\capture_phase5_window_screenshot.ps1`
  - 新增稳定包装脚本，固定执行“启动 Mogwai -> 等 30 秒 -> 精确按主窗口句柄截图 -> 关闭 Mogwai -> 写日志”。
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-07_phase5_window_capture_only.md`
  - 记录了这台机器上 `frameCapture` 不可靠/不可用，以及后续统一只走窗口截图的约束。

## 后续验证怎么做

1. 用 `capture_phase5_window_screenshot.ps1` 启动整条链路，不要再手写“先开 Mogwai 再抢截图”的临时命令。
2. `capture_phase5_takeover_window.py` 只负责切机位和稳定首帧；真正等待、截图、关窗由 PowerShell 包装脚本处理。
3. 只把窗口截图当成最终视觉证据，不再尝试 Mogwai 内置 capture API。

## 下一个 AI 优先看

- `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\capture_phase5_takeover_window.py`
- `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\capture_phase5_window_screenshot.ps1`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-07_phase5_window_capture_only.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-07_phase5_window_capture_only_handoff.md`
