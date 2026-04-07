# 2026-04-07 Notebook Weekly Zip Encoding

- `docs/notebook_draft/周记/周记.zip` 用 PowerShell `Expand-Archive` 解压时中文目录名和文件名会乱码，但正文内容仍可正常读取；批量分析时不要依赖解压后的文件名判断周次。
- 更稳妥的做法是按解压后的文件顺序直接读文本内容，或优先保留原始目录结构信息，避免因为乱码文件名误判周记位置。
