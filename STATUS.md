# 專案進度 STATUS

最後更新：2026-10-17（Claude Code）

## 開發分工

依 Product Owner（sammyzomb）2026-10-17 指示：

- **Claude Code：主開發。** 負責所有程式修改與分支合併。合併到 `main`、關閉 PR、發布遊戲都要先經 Product Owner 同意。
- **Cursor：第二開發。** 只在指定的候選分支上做唯讀檢查（讀程式碼、跑測試、回報問題），不直接修改或合併。
- **Product Owner：** 在 Roblox Studio 實測、決定驗收標準與優先順序。

## 目前候選分支

`candidate/v1`，從 `main`（`116c3b0`）建立，合併了：

| 來源 | head | 內容 |
|---|---|---|
| PR #53（含其下整條堆疊：#4、#28–#36、#43–#52） | `357687f` | 基礎架構、戰鬥核心、訓練場 |
| PR #55 | `9340633` | 沒有玩家資料時拒絕換裝（#20 的一項防護） |

合併時只有 `docs/TRAINING_SMOKE_TEST.md` 有衝突（兩邊都在開頭加段落，已兩邊保留）。程式碼自動合併，沒有衝突。

驗證（2026-10-17，雲端環境，非 Studio）：

- `luau tests/run.luau`：166 passed, 0 failed
- `src/` 44 個腳本全部可編譯
- `rojo build`（Rojo 7.7.0）成功
- `python3 -m unittest discover -s tests -p 'test_*.py'`：44 tests OK

## 已完成功能（依 `candidate/v1` 實際程式碼）

**基礎架構**
- Rojo 專案設定（`default.project.json`、`rokit.toml` 固定 Rojo 7.7.0 / Luau 0.740.0）。
- 服務載入器：伺服器 6 個 Services、客戶端 2 個 Controllers，依 Priority → Init → Start 啟動。
- 玩家資料：載入、定時自動存檔、離開時存檔、v1→v2 資料遷移；Studio 未開 API 時自動改用記憶體存檔。
- 佔位遊戲循環：按 E（手把 X、觸控按鈕）Collect，得到金幣與 XP、會升級；頂部 HUD 顯示金幣、等級、XP 條。

**戰鬥核心（伺服器權威）**
- 武器 13 種：Training Sword、Iron Greatsword、Ash Spear、Twin Daggers、Hunting Bow、Heavy Crossbow、Development Training Rifle、Throwing Knives、Ember Staff、Frost Wand、Runeblade、Wooden Shield、Tower Shield。
- 護甲 6 件、消耗品 4 種（health_potion、mana_potion、barrier_scroll、fortifying_draught）。
- 傷害計算（物理／魔法／真實）、格擋與部分格擋、狀態效果（Stagger、Bleed、Burn、Chill、Barrier、FrostWard 等）。
- 體力、魔力、能量資源；投射物飛行與命中判定；PvE／PvP／Training 三種規則。
- 等級與里程碑解鎖裝備。
- 操作：左鍵／R2 攻擊、Q／R1 技能、R／L1 副手、F／L2 格擋、1／十字鍵上 喝藥水；手機有對應觸控按鈕。
- 戰鬥 HUD：體力、魔力、護盾條。

**訓練場（Issue #23，僅 Studio）**
- 開機時自動產生佔位場景：走道、平台、入口、出口、返回點、假人標記；重開不會重複產生，同名的非本系統物件不會被覆蓋。
- 進入／離開訓練：HP、MP、體力回滿；記住原本的規則與裝備，離開、死亡、斷線時還原。
- 三種職業預設：Swordsman（訓練劍＋木盾）、Mage（Ember Staff）、Archer（開發用訓練步槍，6 發彈匣、換彈）。訓練裝備只存在記憶體，不寫入存檔。
- 職業選單：伺服器確認後才亮起，游標移開後仍保持；附繁體中文操作指引。
- 訓練假人：出生區 3 隻被動假人，場地內 1 隻每 2.5 秒攻擊一次、用來練格擋的假人；死亡 3 秒後重生。
- 傷害數字：顯示伺服器算出的傷害，部分格擋為橘色。
- 訓練藥水：每次訓練 2 瓶，只存在記憶體，不扣正式庫存。
- 訓練中禁止改動正式裝備與消耗品。

**防護（Issue #20 的一部分）**
- 請求頻率限制、冷卻時間檢查。
- 沒有玩家資料時拒絕換裝（PR #55）。

## 已知問題與待修項目

- **還沒在 Studio 實測**：`candidate/v1`、PR #53、PR #55 都還沒有 Studio 測試紀錄。Product Owner 10/8 測過較早的版本（`8ea0d78`），判定不能算可玩。
- **畫面太簡陋**：場景、角色、介面都是佔位方塊（P1b 最低視覺／UI 品質尚未開始）。
- **沒有音效、背景音樂、動畫整合**：#10、#11、#17 只交付了規劃文件。
- **沒有結算畫面**：訓練完成後沒有結果、重試、退出流程。
- **手機版面未驗證**：選單是否遮擋 HUD 或觸控按鈕、安全區是否正確都還沒測。
- **數值都是開發用**：攻擊間隔、步槍傷害與彈匣、藥水數量都還沒有正式平衡（#21）。
- **防作弊未完成（#20）**：沒有裝備所有權驗證、移動防護；公開 PvP 與經濟系統不得開放。
- **存檔沒有 session lock**：快速換伺服器時，可能有兩台伺服器同時寫入同一位玩家。
- **PR #55 沒有自動化測試**：NoData 檢查只能靠 Studio 手動驗證。
- **Collect 只是佔位動作**，場景中沒有對應的物件。
- **訓練假人只在 Studio 出現**，正式伺服器不會生成。
- 之前回報過 Rojo 重複 Connect 的狀況，原因未確認。
- 專案中有許多舊的 draft PR 和分支（例如 #28–#36 的 `wip:` PR），內容已包含在 `candidate/v1` 中，尚未整理。

## 驗收標準

（Product Owner 之後補）

## 下一步

1. Product Owner 在 Studio 實測 `candidate/v1`：攻擊、防禦、死亡重生、操作手感。
2. Product Owner 補上「驗收標準」段落。
3. Cursor 對 `candidate/v1` 做唯讀檢查並回報。
4. 依實測結果，由 Claude Code 在 `candidate/v1` 上修正問題。
5. 之後依優先順序：P1b 最低視覺／UI 品質 → 音效、音樂、動畫整合 → 結算與重試流程 → 手機版面。
