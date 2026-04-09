# 2026-04-07 Hybrid Script Launch Defaults

- `Voxelization_HybridMeshVoxel.py` / `Voxelization_MainlineDirectAO.py` 如果被 profiling/validation 脚本用 `exec()` 间接加载，直接依赖外层 `__file__` 会把 repo 根目录误判到 `build/profiling/...`，表现为 graph 打印 `voxel cache: <none>`；应优先从显式 repo root 或当前工作区标记目录解析资源路径，避免把真实 `resource` 目录找丢。
- hybrid/mainline 启动脚本默认不要打开 profiler，否则截图或窗口抓取会被 profiler 面板干扰；只有在 profiling/批验证确实需要时，再显式传 `HYBRID_OPEN_PROFILER=1` 或 `DIRECTAO_OPEN_PROFILER=1`。
