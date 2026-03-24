# 2026-03-24 DirectAO Planning

- Codex 桌面版内置的 `rg.exe` 在这个工作区会触发“拒绝访问”，现象是文本搜索命令直接失败；排查或读源码时应改用 PowerShell 的 `Select-String` 和 `Get-ChildItem` 兜底。
- 仓库里最初没有 `docs/memory/` 和 `docs/handoff/` 目录，按 AGENTS 规则沉淀文档前需要先创建目录；否则本轮计划文档无法落盘。
- `.FORAGENT/plan.md` 默认锚定到仓库里已存在的 `VoxelDirectAOPass` 实现；如果用户要求“从主线链路独立推导方案”，必须先完成独立分析，再把它只当比较对象。
- 给后续 AI 的计划文档如果仍然写成“方案说明书”，实施时会反复回到架构讨论；要直接写成执行手册，逐阶段列出修改文件、通过条件和失败排查点，才能明显减少返工。
