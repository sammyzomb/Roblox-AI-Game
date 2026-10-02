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
- ChatGPT 使用 `chatgpt-dev` 或 task-specific `chatgpt/*` 分支。
- Claude 使用 `claude-dev`。
- Cursor 使用由 ChatGPT 指派的 task-specific `cursor/*` 分支。
- Grok Bot 使用 `grok-dev`。
- 所有變更必須經 Pull Request。
- PR 必須說明：目的、修改內容、測試結果、風險與相依項目。
- 不可未經協調任意改動其他人的模組。
- 架構衝突或跨模組衝突由 ChatGPT 彙整後交由 Product Owner 決定。

## Roles

- **Product Owner — sammyzomb**：決定產品方向、優先順序與最終接受。
- **ChatGPT — Technical Lead**：系統架構、任務拆分、派工、整合、Review、Debug、衝突處理與驗收狀態管理。
- **Claude — Primary Programmer**：主要 Luau 程式實作與核心系統開發；對主要功能提供第一版實作與測試。
- **Cursor — Secondary Developer / Verification Engineer**：驗證 Claude 成果、執行 fresh-agent smoke test、regression/build 檢查、找可重現 bug、檢查整合風險，並在被指派時做小範圍且有測試依據的修正。
- **Grok Bot — Independent Reviewer / Prototype Developer**：提供獨立架構、玩法平衡、安全、漏洞面、網路與行動裝置觀點；必要時做隔離原型，不與 Claude 平行重寫同一核心。

## Default Workflow

1. Claude 負責主要實作。
2. Cursor 負責驗證、回歸測試、整合前檢查與範圍明確的小型修正。
3. Grok Bot 負責獨立 review、平衡／安全檢查與必要的隔離原型。
4. ChatGPT 負責 review、整合、衝突處理與是否可合併的判定。
5. Product Owner 透過 Roblox Studio 實測或接受實測證據後，才可把功能標示為真正可玩。

## Non-Duplication Rule

- Claude、Cursor、Grok Bot 不得自行對同一核心功能同時建立競爭版本。
- 若需要平行方案，必須由 ChatGPT 明確指定目的、範圍與比較標準。
- 發現架構分歧時，以 `[CONFLICT]` 或 review finding 記錄，不得自行覆蓋其他人的實作。

## Evidence Levels

所有完成聲明應明確區分：
1. 文件完成
2. 程式完成
3. 自動測試通過
4. 已整合
5. Roblox Studio 實測通過
6. 可玩流程驗收通過

不得用前一層的證據宣稱後一層完成。

## Communication

GitHub 是本專案的共同協作與交接平台。
重要決策、派工、衝突、測試證據與驗收結果應記錄於 Issue、Pull Request 或 docs 文件中，不只存在單一 AI 對話裡。
