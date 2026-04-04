# 2026-04-05 Handoff Cleanup

- `docs/handoff/` 里的阶段性 handoff 一旦只剩历史背景、且关键信息已经被当前 `plan3/plan4` 或更晚的 stage handoff 吸收，就应直接删除；继续保留“已过期但写着历史说明”的 handoff 只会增加错误入口。
- 清理 handoff 时要先确认计划文档仍只指向保留文件，再删除旧 handoff；否则后续 Agent 会在文档搜索里先命中过期入口。
