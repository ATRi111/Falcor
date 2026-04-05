# 2026-03-24 DirectAO Planning

- Codex 桌面版内置的 `rg.exe` 在这个工作区可能触发“拒绝访问”；做源码搜索或文档引用检查时应改用 PowerShell 的 `Get-ChildItem` 和 `Select-String`。
- 给后续 AI 的计划文档要直接写成执行手册，明确修改文件、通过条件和失败排查点；如果只写方案说明，实施时会不断回到架构讨论。
