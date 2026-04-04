# 2026-04-04 Mainline DirectAO Stage4 Cleanup

- `VoxelDirectAO*` 如果继续留在 `VoxelizationBase.cpp`、`CMakeLists.txt` 和旧脚本里，全仓搜索 DirectAO 时会同时看到废弃入口和主线入口，后续 Agent 很容易删错或改错文件；清理后应只保留 `RayMarchingDirectAO*` 和 `scripts\Voxelization_MainlineDirectAO.py`。
- `Voxelization_MainlineDirectAO.py` 当前输出已经是 pass 自己的 `color`，不需要再串 `RenderToViewportPass` 和 `AccumulatePass`；否则图里会多一层与当前稳定单帧验收无关的中转链路。
- `build\windows-vs2022` 同一个生成目录不要并行跑两个 `cmake.exe --build`；这次同时补编 `Voxelization` 和 `Mogwai` 时触发了 CMake 重新配置竞态，现象是 `external/glfw/CMakeLists.txt:337 configure_file` 找不到文件，串行重跑即可恢复。
- Windows 下用 `C:\Users\42450\.codex\skills\screenshot\scripts\take_screenshot.ps1` 抓 Mogwai 窗口时，脚本里的 `$home` 会撞 PowerShell 只读的 `$HOME` 变量；要么先修脚本变量名，要么像本轮一样直接按窗口句柄走 `CopyFromScreen` 兜底。
