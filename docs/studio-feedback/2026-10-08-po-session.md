# Product Owner Studio 實測反饋（2026-10-08）

**測試版本：** `8ea0d78cce21241399038b2bd6442e871e21866f`  
**測試者：** sammyzomb（Product Owner，Studio Play Solo）  
**環境：** Cursor 終端機 + Rokit/Rojo + Roblox Studio Rojo plugin  
**狀態：** 功能 smoke test **部分完成**；整體體驗反饋 **需 PO / TL 決策**  
**關聯 Issue：** #42、#23

---

## 一、設定流程（PO 親身操作）

| 步驟 | 結果 |
|---|---|
| `git checkout 8ea0d78` | ✅ |
| `rokit install`（trust luau + rojo） | ✅ |
| `rojo serve` | ✅（localhost:34872） |
| Studio 安裝 Rojo plugin + Connect + Accept sync | ✅（Connect 提示曾重複出現，需多次 Accept） |
| Play（F5）進入遊戲 | ✅ |

**設定體驗：** 對非工程背景 PO 門檻偏高（Rokit trust、Rojo 重複 Connect、Accept sync）。建議 TL 整理一份 **PO 專用 1 頁 Studio 啟動指南**。

---

## 二、功能驗證（Studio 實測）

| 項目 | 結果 | 備註 |
|---|---|---|
| Spawn / Boot | ✅ | 角色正常生成 |
| HUD（Coins / Level / XP bar） | ✅ | Level 20（Studio 測試設定） |
| Collect（E） | ✅ | Coins 0→1 正常 |
| 近战（左键 → TrainingDummy_L1） | ✅ | 假人 HP 下降 |
| 格挡（F） | ⏸️ 未完成 | 出生点三个假人为**被动**，不会攻击，无法验证格挡减伤 |
| 训练场入口（蓝色平台） | ✅ | 出现 Swordsman / Mage / Archer 选单 |
| 职业选择（Swordsman 点击） | ⚠️ 反馈差 | 滑鼠悬停变亮，但移开后**不保持选中高亮**；选单**不会消失**（文档称在训练区内属预期，但 PO 感到困惑） |
| 会攻击的场景假人 | ⏸️ 未测到 | 未走到 `TrainingDummyMarker` 完整训练流程 |
| Potion / Ranged / Magic / Death / Disconnect | ⏸️ 未测 | 本次中止 |

---

## 三、Product Owner 體驗反饋（重要）

> **「整個感覺很差，很陽春，很簡陋。」**

具體感受：

1. **視覺：** 绿色草地 + 灰色平台 + 彩色方块 + 黑色假人 → 像 unfinished prototype，不像可玩遊戲
2. **UI/UX：** 职业选单像 debug 面板；悬停/选中反馈不清晰；缺乏引导（不知道下一步该做什么）
3. **世界：** 没有完整地图感、没有氛围、没有动画/VFX/SFX
4. **预期落差：** 虽理解是 dev slice，但 **PO 主观感受离「可展示 / 可玩」差距大**

**TL 需区分：**

- ✅ **功能验证版**（当前）— 核心 combat / training 逻辑
- ❌ **Product Owner 可接受版** — 需最低限度的 UX 引导 + 视觉 pass（即使 placeholder 也应有 basic polish）

---

## 四、阻塞 / 问题（非 merge blocker，但影响 PO 验收）

| 严重度 | 项目 |
|---|---|
| 🟡 UX | 职业按钮选中状态不持久（仅 hover 变亮） |
| 🟡 引导 | 被动假人 vs 攻击假人未向玩家说明，导致格挡测试无法进行 |
| 🟡 流程 | Rojo Connect 重复弹出，增加 PO 操作负担 |
| 🟢 预期 | 整体视觉/UI 为 dev placeholder — **非 bug，但是 PO 验收 blocker** |

---

## 五、建议下一步（请 ChatGPT TL 决策）

1. **不标记为 COMPLETE / playable** — PO 体验未达标
2. 安排 **Issue #23 后续 increment**：最低限度 UX（选中反馈、简短 on-screen 引导、训练假人说明）
3. 排 **Art/UI polish milestone**（可与 Animation / Art Planner issues 对齐）
4. 产出 **PO Studio 启动 1-pager**（减少下次测试门槛）
5. 若需继续功能验证：PO 需被引导至 `TrainingDummyMarker` 完成攻击假人 + 格挡流程

---

**[HANDOFF]** — Studio 已连通且核心功能部分验证通过；**PO 体验反馈为负向**，建议暂停「playable」验收，转交 TL 排优先级。
