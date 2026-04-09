# 2026-04-07 MultiBunny Route Scripts

- Mogwai 在 Python `sceneUpdateCallback` 里不保证 `__file__` 仍然可用；后续还要解析 repo/resource 路径的脚本应在启动时固化 repo root，或让包装脚本显式传 `HYBRID_REPO_ROOT`。
- 对固定场景补 `ReadVoxelPass.binFile` 时，不要在首帧里再用 `m.activeGraph.updatePass()` 临时改路径；这会让 graph 处在未完成编译态并触发 `Can't fetch the output 'ToneMapper.dst'`，更稳的做法是启动前就给出明确 cache 路径，让 `ReadVoxelPass` 自己等待文件生成。
