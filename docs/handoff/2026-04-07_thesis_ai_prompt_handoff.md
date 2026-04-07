# Thesis AI Prompt Handoff

## 模块职责

这次补的是一份给其他 AI 使用的详细论文写作提示词，目标是约束后续模型按照开题报告主线和当前仓库真实状态来写毕业论文。

## 当前状态

- 新增文档 `docs/development/2026-04-07_thesis_ai_writing_prompt.md`。
- 文档内容已经覆盖：
  - 论文的总体定位。
  - 当前实现状态的真实边界。
  - 禁止夸大的说法。
  - 推荐使用的论文口径。
  - 推荐的章节结构。
  - 实验分析的写法。
  - 必须优先参考的本地开题报告、脚本、代码和 handoff 文件。
  - 让 AI 写摘要、绪论、结论时的额外要求。
- 新增 memory `docs/memory/2026-04-07_thesis_ai_prompt_constraints.md`，记录论文提示词要先锁定“定位 + 禁写项 + 文件入口”。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\docs\development\2026-04-07_thesis_ai_writing_prompt.md`
- `E:\GraduateDesign\Falcor_Cp\docs\development\2026-04-07_thesis_system_design_and_outline.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\kaity_report_extract.txt`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`

## 后续继续时优先看

- 如果下一步要直接调用别的 AI 写论文，优先复制这份 prompt 原文，不要再临时口述系统状态。
- 如果后续论文定位变化，需要先改这份 prompt，再让模型继续生成各章节，避免新旧口径混用。
