# CLAUDE.md

## 每次工作的固定流程

1. **開始工作前，先讀根目錄的 `STATUS.md`**，確認分工、目前候選分支、已知問題與下一步。
2. **完成工作後，更新 `STATUS.md`**：最後更新日期、候選分支內容、已完成功能、已知問題、下一步。和程式變更放在同一個 commit 或緊接著的 commit。
3. 回報給 Product Owner 時使用繁體中文，假設對方不會寫程式。

## 分工與權限

- Claude Code 是主開發，負責程式修改與合併到候選分支（目前是 `candidate/v1`）。
- Cursor 是第二開發，只在候選分支上做唯讀檢查，不修改、不合併。
- ChatGPT 是顧問／審查，意見僅供參考：評估後採用，或在 PR／`STATUS.md` 記錄不採用的原因；有分歧時交 Product Owner 決定。不需要等 ChatGPT 同意才能繼續工作。
- 合併到 `main`、關閉 PR、發布遊戲都要先問 Product Owner。
- 不要 force-push 別人的分支，也不要改寫已推送的歷史。

## 驗證指令

在專案根目錄執行（版本固定在 `rokit.toml`：Rojo 7.7.0、Luau 0.740.0）：

```
luau tests/run.luau                                  # 遊戲邏輯單元測試
rojo build default.project.json -o build.rbxlx       # 確認 Rojo 可以建出 place 檔
python3 -m unittest discover -s tests -p 'test_*.py' # 自動化工具（scripts/）測試
```

Studio 實測步驟見 `docs/TRAINING_SMOKE_TEST.md`。這些離線測試通過不代表 Studio 實測通過，回報時要分開說明。
