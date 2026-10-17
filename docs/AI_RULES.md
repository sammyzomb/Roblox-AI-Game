# AI Collaboration Rules

## Project Governance

依 Product Owner 2026-10-17 決定：
- **Product Owner（sammyzomb）** 決定方向、優先順序與最終接受。
- **Claude Code** 擔任主開發，負責所有程式修改與整合到候選分支，並維護 `STATUS.md`。
- **ChatGPT** 擔任顧問／審查：可以提供設計與審查意見，但不派工、不把關、不決定能否合併。

開始工作前，所有協作者必須閱讀：
- `STATUS.md`
- `README.md`
- `docs/AI_RULES.md`
- `docs/ARCHITECTURE.md`
- `docs/TASKS.md`

## Branch Rules

- 禁止任何 AI 或開發者直接修改 `main`；合併到 `main` 需經 Product Owner 同意。
- 目前候選分支記錄在 `STATUS.md`（現為 `candidate/v1`）。Claude Code 在候選分支或任務分支上工作，並負責整合到候選分支。
- Cursor 只在指定的候選分支上做唯讀檢查，不建立分支、不修改、不合併。
- ChatGPT 的意見以 Issue 或 PR 留言提出；如需提交文件草稿，使用 `chatgpt/*` 分支並開 PR，由 Claude Code 評估是否採用。
- Grok Bot 使用 `grok-dev`。
- PR 必須說明：目的、修改內容、測試結果、風險與相依項目。
- 架構衝突或跨模組衝突由 Claude Code 整理選項與建議，交由 Product Owner 決定。

## Roles

- **Product Owner — sammyzomb**：決定產品方向、優先順序與最終接受。
- **Claude Code — 主開發**：所有程式修改、架構維護、整合到候選分支、測試、維護 `STATUS.md`，並向 Product Owner 回報。
- **Cursor — 第二開發（唯讀檢查）**：在指定候選分支上讀程式碼、跑測試、找可重現的問題並回報；不直接修改或合併。
- **ChatGPT — 顧問／審查**：玩法與架構討論、審查計畫或 PR、提出風險與建議。意見僅供參考，由 Claude Code 評估採用與否；有分歧時交 Product Owner 決定。
- **Grok Bot — Independent Reviewer / Prototype Developer**：提供獨立架構、玩法平衡、安全、漏洞面、網路與行動裝置觀點；必要時做隔離原型，不與 Claude 平行重寫同一核心。
- **Animation Designer（Creative Grok Bot）**：負責動畫方向、動作狀態、戰鬥可讀性、武器持握與動畫優先級，不負責玩法規則或 production gameplay code。
- **Sound Effects Planner（Creative Grok Bot）**：負責戰鬥／魔法／UI／環境／成長回饋音效規劃與事件 mapping，不負責 production gameplay code。
- **Music Planner（Creative Grok Bot）**：負責音樂識別、場景／戰鬥／Boss／PvP 音樂結構、動態轉場、loop 與 intensity layers，不負責 production gameplay code。

## Default Workflow

1. Product Owner 決定要做什麼與優先順序。
2. Claude Code 實作、測試，並整合到候選分支，更新 `STATUS.md`。
3. Cursor 在候選分支上做唯讀檢查並回報。
4. ChatGPT、Grok Bot 視需要提供審查意見（僅供參考）。
5. Product Owner 在 Roblox Studio 實測；實測通過才可標示為真正可玩，並由 Product Owner 決定是否合併到 `main`。

## Non-Duplication Rule

- Claude、Cursor、Grok Bot 不得自行對同一核心功能同時建立競爭版本。
- 若需要平行方案，必須由 Product Owner 同意，並明確指定目的、範圍與比較標準。
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
