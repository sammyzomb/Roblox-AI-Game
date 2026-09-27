# AI Collaboration Rules

## Project Governance

此專案由 **ChatGPT 擔任 Technical Lead 與主要協調窗口**。

開始工作前，所有協作者必須閱讀：
- `README.md`
- `docs/AI_RULES.md`
- `docs/ARCHITECTURE.md`
- `docs/TASKS.md`

## Branch Rules

- 禁止任何 AI 或開發者直接修改 `main`。
- ChatGPT 使用 `chatgpt-dev`。
- Claude 使用 `claude-dev`。
- Grok 使用 `grok-dev`。
- 所有變更必須經 Pull Request。
- PR 必須說明：目的、修改內容、測試結果、風險與相依項目。
- 不可未經協調任意改動其他人的模組。
- 架構衝突或跨模組衝突由 ChatGPT 彙整後交由 Product Owner 決定。

## Roles

- **Product Owner — sammyzomb**：決定產品方向、優先順序與最終接受。
- **ChatGPT — Technical Lead**：系統架構、任務拆分、整合、Review、Debug、協調。
- **Claude — Primary Programmer**：主要 Luau 程式實作與核心系統開發。
- **Grok — Secondary Developer / Reviewer**：獨立功能、原型、第二解法、程式碼審查。

## Communication

GitHub 是本專案的共同協作與交接平台。
重要決策應記錄於 Issue、Pull Request 或 docs 文件中，不只存在單一 AI 對話裡。
