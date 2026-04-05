# 2026-04-05 Documentation Cleanup

- 这个工作区的文档入口必须收敛到 `.FORAGENT/plan5.md` 加当前 baseline / hybrid handoff；旧 plan、阶段 prompt 和过渡 handoff 如果继续保留，会让搜索结果把后续 Agent 带回已完成阶段。
- 清理旧文档前要先改导航和交叉引用，再删除文件；本仓库里 `rg.exe` 不能稳定运行，引用检查应改用 PowerShell `Get-ChildItem` + `Select-String`。
