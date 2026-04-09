# 2026-03-24 Mainline DirectAO Stage2

- `RayMarchingTraversal.slang` 只适合放 `HitResult` 和 traversal/visibility helper；如果把资源声明或 pass 专属常量也一起抽进去，原 `RayMarchingPass` 和新 `RayMarchingDirectAO` 会失去各自的 define/scene 绑定边界。
- `RayMarchingDirectAO.ps.slang` 在 Falcor 第一次创建 `FullScreenPass` 时会先做一次预热编译；如果 `CHECK_ELLIPSOID`、`CHECK_VISIBILITY`、`CHECK_COVERAGE`、`USE_MIP_MAP` 没有 shader 内默认值，日志会报一串“undefined identifier in preprocessor expression”，现象像 shader 接线错了，实际需要在 shader 顶部补默认宏。
- 阶段 2 的命令行烟测只能确认 `--script` 和 `--script --scene` 启动不崩；真正的 `NormalDebug`/`CoverageDebug` 命中轮廓仍依赖 GUI 里先给 `ReadVoxelPass` 选 cache 并点击 `Read`，否则新 pass 只能停在 miss 背景。
