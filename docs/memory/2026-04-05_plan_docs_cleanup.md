# 2026-04-05 Plan Docs Cleanup

- Codex 桌面版内置的 `rg.exe` 在这个工作区仍会因为“拒绝访问”而无法启动；做文档清理或全仓引用检查时要改用 PowerShell 的 `Get-ChildItem` + `Select-String`，否则会误以为搜索命令或仓库本身有问题。
- `.FORAGENT/ai_doc_navigation.txt` 这类导航文件可能同时包含多个过时或不存在的路径；删除旧计划文档前应先用 `Test-Path` 验证导航目标，再统一改导航和 handoff，最后再删旧文件。
