# Notebook AI Style Review Handoff

## 模块职责

这次工作只分析 `docs/notebook_draft` 里周记和日记的 AI 腔问题，并基于样稿实际问题生成一版更定向的 Claude 润色提示词，不改原文内容。

## 当前状态

- 已通读 `docs/notebook_draft/日记` 下 30 组日记文本，并统计了句数、长度和高频词。
- 已读取 `docs/notebook_draft/周记/周记.zip` 中 8 组周记文本内容，确认周记问题主要是结构过于对称、句式模板化和“项目汇报感”偏重。
- 已新增 memory `docs/memory/2026-04-07_notebook_weekly_zip_encoding.md`，记录 PowerShell 解压周记 zip 时中文文件名乱码的问题。

## 后续继续时优先看

- 先看 `E:\GraduateDesign\Falcor_Cp\docs\notebook_draft\日记`，这里最明显的问题是“日期行 + 今天…… + 后面……”的重复模板。
- 再看 `E:\GraduateDesign\Falcor_Cp\docs\notebook_draft\周记\周记.zip`，重点控制每篇周记两段内容不要都写成完整的“进展总结 + 问题措施”报告腔。
- 如果后面要继续批量润色，优先沿用这次整理出的定向提示词，不要只给“去 AI 味”这种过泛要求。
