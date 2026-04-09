# 2026-04-05 Plan4 Phase2 Mesh Direct

- `HybridMeshDebugPass` 这类基于 `FullScreenPass` 的 Slang 改动，即使 `HybridVoxelMesh` 和 `Mogwai` 都能编过，像 `FLT_MAX` 这种 shader 符号错误也可能只在 Mogwai 首帧真正 link/pass execute 时才暴露，现象是窗口标题变成 `Error` 或直接弹 Falcor 异常框。  
- 排查这类问题不要只看 `cmake --build`；必须实际启动 Mogwai 并检查 `build/logs/*stderr.log`，否则很容易把“纯白/没出图”误判成光照或截图时机问题。
