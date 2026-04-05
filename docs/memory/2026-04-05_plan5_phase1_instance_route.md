# 2026-04-05 Plan5 Phase1 Instance Route

- `GeometryInstanceData.flags` 的 route 默认值必须让 `Blend = 0`；老场景实例数据和未显式覆写的 builder 路径都会先落成零值，若把 `Blend` 编成非零会让所有未配置实例在 runtime 里被误判成别的 route。
- 用 Mogwai 验证 `Arcade` route debug 时必须传绝对 `--scene` 路径，并在有多个 Mogwai 窗口时按显式窗口句柄抓图；从 `build\windows-vs2022\bin\Release` 用相对场景路径会弹出 `Can't find scene file` 假失败，对 `ProcessName=Mogwai` 的模糊截图也容易抓错窗口。
