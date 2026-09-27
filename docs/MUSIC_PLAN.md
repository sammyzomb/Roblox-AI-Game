# MUSIC PLAN（音樂企劃）

> Owner: Grok-Music-Planner（Music Planner / 音樂策畫）· Task: Issue #11
> Status: Draft v1，待 ChatGPT（Technical Lead）統合、Product Owner（sammyzomb）確認
> 依據文件（main @ `1f62828`）：`README.md`、`docs/AI_RULES.md`、`docs/AI_COORDINATION_PROTOCOL.md`、`docs/GAME_DESIGN.md`、`docs/ARCHITECTURE.md`、`docs/CREATIVE_TEAM.md`、`docs/TASKS.md`、`docs/PROJECT_STATUS.md`，以及 Issue #3 的 Owner 產品決策
> 撰寫時**尚未存在**：`docs/ART_DIRECTION.md`（Issue #8）、`docs/SFX_PLAN.md`（Issue #10）。本文件先採 theme-neutral 寫法，兩份文件落地後需再對齊一次（見 §12）。

**本文件範圍：** 只定義音樂（BGM、music layers、music stingers/cues）。不改 gameplay 規則、不改 engineering architecture。凡是會影響 gameplay clarity、mobile performance 或實作範圍的地方都標了 **[→ ChatGPT]**。
**標示規則：** 「**假設**」是因世界主題未定而暫定的內容，不是既定事實。

---

## 0. TL;DR

- **音樂識別：** 「**Hybrid Orchestral Fantasy**」：管弦樂打底，加上現代打擊與合成器質感。整部作品共用一個 4 音上行主題 **「Ascension Motif」**，對應「逐步解鎖、變強」的成長核心。
- **三種戰鬥 archetype 各有代表音色：** 近戰重擊 = 低音銅管、大鼓（taiko 類）；遠程物理 = 撥弦、木管、快速 ostinato；魔法 = 合唱、鐘琴/celesta、合成器琶音。防禦（護盾/屏障）= 持續的銅管 chorale 墊音。
- **動態音樂：** 每個 PvE 區域用一套**同 BPM、同調性、同 loop 長度的 stems（L0–L4）**做 vertical layering（探索 → 警戒 → 戰鬥 → 高強度）。Hub、Boss、PvP 則用 horizontal re-sequencing（整首切換，對齊小節）。
- **短 cue 與完整 BGM 的分工：** 預期持續 **< 30 秒**，或屬於一次性回饋的事件（升級、解鎖、勝敗、Boss 換階段），一律用 stinger/cue，不切 BGM。
- **Roblox：** 音樂只在 client 播放（MusicController），server 只同步狀態（attributes/remotes）。用 SoundGroups 分 bus，ducking 用腳本 tween。MVP 約需 **10 個音訊上傳**：stingers 合併成一個 asset，再用 `PlaybackRegion` 切段。

---

## 1. 遊戲整體音樂風格與音樂識別（Musical Identity）

### 1.1 設計理念
`GAME_DESIGN.md` 的核心是「**成長解鎖新選擇，而不只是數值膨脹**」與「**Build 選擇**」。音樂識別要呼應這兩點：
1. **成長感（Progression）：** 主題動機隨玩家進度「長大」。新手區只有單一樂器的旋律，高階區/Boss 則是全編制，並加上轉調。
2. **多樣但統一（Many builds, one game）：** 三種 archetype 各有代表音色，但都回到同一個主題動機與同一套和聲語彙。
3. **可讀性優先（Gameplay clarity）：** 戰鬥音樂以節奏驅動為主，旋律密度偏低，把中高頻讓給 telegraph/命中音效（見 §9）。

### 1.2 風格定義
| 項目 | 規格 |
|---|---|
| 類型 | Hybrid Orchestral Fantasy（管弦 + 現代打擊 + 輕度合成器） |
| 情緒弧線 | 溫暖／好奇（Hub、探索）→ 緊張（警戒）→ 熱血、推進（戰鬥）→ 史詩（Boss）→ 競技、冷冽（PvP） |
| 主要調式 | Dorian／自然小調為主（冒險感，不過度陰暗）；Hub 與勝利用大調／Lydian |
| 速度家族 | Hub 90 BPM · 探索與 PvE 戰鬥 stems 100 BPM · PvP 128 BPM · Boss 140 BPM |
| 拍號 | 4/4 為主（小節對齊好算、stems 好剪）；Boss Phase 3 可短暫用 7/8 製造壓迫感（可選） |
| 禁忌 | 不用有歌詞的人聲（避免版權、分散注意力、影響在地化）；戰鬥中不放高頻持續音（會蓋掉 telegraph）；不用風格太強烈的 EDM drop |

> **假設：** 世界主題未定。若 Owner 採用和風／東方主題（Ronin 原型只是參考），只要把「代表音色」換成尺八、箏、太鼓，結構與動機都不用改。若採西式奇幻，維持上表即可。**[→ ChatGPT / Owner：世界主題定案後通知 Music Planner]**

### 1.3 主題動機「Ascension Motif」
- **形狀：** 4 音上行（例如 D–E–A–C，Dorian 色彩），最後一音停在不穩定的 7 級，表示「還沒到頂」。
- **變奏規則：**

| 情境 | 變奏 |
|---|---|
| Hub | 大調、慢速、單把木管或鋼琴 |
| 探索 | 動機片段藏在墊音或撥弦裡，每 16 小節出現一次 |
| 戰鬥 | 縮短成節奏動機（前 2 音 + 重音），由銅管或弦樂 staccato 演奏 |
| Boss | 完整動機 + 轉調（Phase 3 升半音） |
| PvP | 反向（下行）與切分節奏，表現「對手」 |
| 升級／解鎖 stinger | 完整動機上行，**最後一音解決到主音**，代表「這一步完成了」 |

### 1.4 Archetype 音色語彙（Instrument Palette）
| Archetype／系統 | 代表音色 | 用途 |
|---|---|---|
| 近戰重擊 Close-Range Power | 低音銅管、太鼓類大鼓、低音弦 marcato | 戰鬥 L3/L4 的重拍 |
| 遠程物理 Ranged Physical | 撥弦（pizzicato／魯特琴類）、木管快速 ostinato | 探索 L1、戰鬥 L3 的推進層 |
| 魔法 Magic | 合唱 "Ah/Oh" pad、celesta、合成器琶音 | 探索 L0 氛圍、Boss 的魔法段落 |
| 防禦 Defense | 持續的銅管 chorale、低音弦長音 | Boss 階段轉換、勝利 cue |

> 註：MVP **不做**「依玩家當前 build 動態換音色」（成本高、多人同場無意義）。調色盤只當作曲指引。依 build 變化列入 P2 研究項目。

---

## 2. 各場景音樂表（Scene / State Music Table）

| 場景／狀態 | 類型 | 資產 ID | BPM | 播放方式 | 進入條件 | 離開條件 |
|---|---|---|---|---|---|---|
| Spawn／Hub | BGM（loop） | MUS_HUB_MAIN | 90 | 單軌 loop | 玩家加入、傳送回 Hub | 傳送到區域或 Arena |
| Hub 商店／鍛造 UI（可選） | Layer | MUS_HUB_SHOP_L1 | 90 | 疊在 Hub 上的輕打擊層 | 開啟商店 UI | 關閉 UI |
| PvE 探索 | BGM（stems L0+L1） | MUS_Z1_L0／L1 | 100 | vertical layering | 進入區域 | 見 §6 狀態機 |
| 發現敵人／警戒 | Layer | MUS_Z1_L2 | 100 | 淡入 L2 | 敵人鎖定玩家（aggro） | aggro 解除 |
| 一般戰鬥 | Layer | MUS_Z1_L3 | 100 | 淡入 L3、L1 降量 | 造成或受到傷害 | 見 §6 hysteresis |
| 高強度戰鬥 | Layer | MUS_Z1_L4 | 100 | 淡入 L4 | 強度分數 ≥ 閾值（§6.3） | 分數回落 |
| Boss | BGM（分階段） | MUS_BOSS_*（§5） | 140 | horizontal，依 phase 切段 | 進入 Boss 區或 Boss 啟動 | Boss 死亡或全滅 |
| PvP Arena 大廳／排隊 | BGM | MUS_HUB_MAIN（變奏可選） | 90 | 沿用 Hub | 進入排隊 | 比賽開始 |
| PvP 對戰 | BGM + Layer | MUS_PVP_MATCH、MUS_PVP_FINAL_L | 128 | 單軌 loop + 最後階段層 | 倒數結束 | 比賽結束 |
| 勝利 Victory | Cue | CUE_VICTORY | – | 一次性 5–8 秒 | Boss 擊殺、PvP 勝利 | 播完回到上一個 BGM 或 Hub |
| 失敗 Defeat／死亡 | Cue | CUE_DEFEAT | – | 一次性 4–6 秒 | 玩家死亡、PvP 落敗、Boss 全滅 | 重生後回到區域 BGM |
| 升級 Level-up | Stinger | CUE_LEVELUP | – | 一次性 3–4 秒，疊在 BGM 上 | server 發出升級事件 | – |
| 武器／技能解鎖 Unlock | Stinger | CUE_UNLOCK | – | 一次性 4–5 秒 | 解鎖事件 | – |
| 稀有掉落 Rare loot | Stinger | CUE_LOOT_RARE | – | 一次性 2–3 秒 | 稀有度 ≥ Epic（待定） | – |
| 任務完成 | Stinger | CUE_QUEST | – | 一次性 2–3 秒 | 任務完成 | – |
| 新區域發現 | Stinger | CUE_ZONE_DISCOVER | – | 一次性 4–6 秒，接著區域 BGM | 首次進入區域 | – |
| 菁英怪出現 | Stinger | CUE_ELITE | – | 一次性 2 秒 | 菁英怪 aggro | – |
| Boss 登場 | Cue | CUE_BOSS_INTRO | 140 | 一次性 4–8 秒，接 Phase 1 | Boss 啟動 | – |
| PvP 倒數 3-2-1 | Cue | CUE_PVP_COUNTDOWN | 128 | 對齊 server 倒數 | 比賽開始前 3–4 秒 | – |

### 2.1 何時用短 cue、何時用完整 BGM
用 **Cue／Stinger**（不切 BGM），只要符合以下任一條：
1. 事件本身是**瞬間**的：升級、解鎖、掉落、任務完成、菁英出現、Boss 換階段。
2. 該狀態預期持續 **< 30 秒**：例如死亡到重生的等待、PvP 回合間 < 30 秒的空檔。
3. 事件可能**高頻重複**（每分鐘 ≥ 1 次）：用 BGM 會一直重啟，很煩。
4. 需要**對齊 server 時機**的提示：PvP 倒數、Boss 登場。

用 **完整 BGM／layer**：預期持續 ≥ 30 秒的「場所」或「狀態」，例如 Hub、區域探索、戰鬥、Boss、PvP 對戰。

**Stinger 規則：**
- 同一時間只播 **1 個** music stinger，其餘排隊或丟棄（優先序：Victory/Defeat > Boss intro/phase > Unlock > Level-up > Zone discover > Rare loot > Quest > Elite）。
- 同一個 stinger 冷卻 **3 秒**。1 秒內連續升級只播一次 CUE_LEVELUP。
- Stinger 播放時，BGM bus duck **−6 dB**：attack 0.1 s、release 1.0 s。
- Stinger 的調性要能疊在任何區域 BGM 上：只用主音與五度的和聲，或寫成無調性的打擊加鐘聲。
- **與 SFX 分工 [待 SFX_PLAN 對齊]：** SFX 負責 UI 點擊、金幣、「叮」之類的短音效（< 1 秒）；Music 負責有和聲與旋律的 2–8 秒 fanfare。同一事件兩者可以同時存在，但 SFX 先發聲（0 ms），music stinger 可延後最多 1 拍。

---

## 3. PvE 音樂規劃

### 3.1 結構
PvE 是主要遊玩時間（`GAME_DESIGN.md`：PvE 為主要成長來源），所以耐聽度是第一優先。
- 每個區域一套 **Zone Suite**，共 5 條 stems：同 BPM（100）、同調、同長度（48 小節 = 115.2 秒）。

| Layer | 內容 | 探索 | 警戒 | 戰鬥 | 高強度 |
|---|---|---|---|---|---|
| L0 Ambient Bed | 合唱 pad、低音長音、環境質感 | 100% | 100% | 70% | 60% |
| L1 Explore Melody | 撥弦／木管旋律、動機片段 | 100% | 60% | 30% | 0% |
| L2 Tension Pulse | 低音 ostinato、輕打擊、心跳感 | 0% | 100% | 100% | 100% |
| L3 Combat Drive | 完整打擊、弦樂 staccato、銅管重拍 | 0% | 0% | 100% | 100% |
| L4 High Intensity | 合唱強奏、高音銅管、節奏加倍 | 0% | 0% | 0% | 100% |

（百分比為相對音量，實作時換算成 dB 或線性 Volume。）

### 3.2 PvE 規則
- **只有在敵人鎖定本地玩家時**才進警戒（L2）。不能「附近有敵人就變音樂」，否則等於洩漏隱藏敵人的位置，破壞探索驚喜。**[→ ChatGPT：需要 server 在 enemy 上設 `TargetUserId` attribute，或提供等價訊號]**
- 組隊時，**隊友進入戰鬥不會**拉高本地玩家的音樂，除非本地玩家在 40 studs 內（避免遠處隊友戰鬥時音樂亂跳）。
- 採集／farming 這類重複動作不觸發 music stinger，只用 SFX。
- 靜默段：探索 loop 每播 2 次（約 4 分鐘）可以插入 20–40 秒只剩 L0 的「呼吸段」，減少聽覺疲勞（P1）。

---

## 4. PvP 音樂規劃

### 4.1 原則
`GAME_DESIGN.md`：PvP 共用戰鬥基礎，要避免 pay-to-win 與不公平。音樂這邊的延伸原則是：
1. **資訊公平：** PvP 中**停用所有「敵人接近／偵測」的觸發**。音樂強度只跟公開資訊走：比賽計時、比分、回合數。
2. **聽覺空間：** PvP 最依賴聽腳步、蓄力、施法前搖等音效。PvP BGM 整體比 PvE 戰鬥低 **3 dB**，旋律更少、以節奏為主，2–5 kHz 刻意留空。
3. **識別：** 使用 Ascension Motif 的**反向（下行）**，搭配更現代的合成器低音與電子打擊，和 PvE 的「冒險」做出區隔。

### 4.2 流程
| 階段 | 音樂 |
|---|---|
| 排隊／大廳 | 沿用 MUS_HUB_MAIN（或 P2 的 Arena lobby 變奏） |
| 進場、讀取 | Hub 淡出 1.5 s |
| 倒數 3-2-1 | CUE_PVP_COUNTDOWN（128 BPM、4 拍），**最後一拍對齊 server 的「Fight」**；倒數音效本身由 SFX 負責 |
| 對戰中 | MUS_PVP_MATCH loop（64 小節 ≈ 120 秒） |
| 最後 30 秒／Sudden death／賽點 | 疊加 MUS_PVP_FINAL_L（打擊加倍、上升音型），淡入 1 小節 |
| 回合結束（多回合制） | 本地玩家視角的 CUE_ROUND_WIN 或 CUE_ROUND_LOSE（2–3 秒），BGM duck 到 −12 dB 但不停 |
| 比賽結束 | CUE_VICTORY 或 CUE_DEFEAT，然後回 Hub BGM |

> **待決：** PvP 模式（1v1／團隊／FFA、回合制或計時制）尚未定義。上表以「計時 + 可選回合」撰寫。**[→ ChatGPT]**

---

## 5. Boss 音樂規劃（分階段 Phases）

### 5.1 結構（horizontal re-sequencing + 階段轉換 stinger）
| 段落 | 資產 | 長度 | 內容 | 觸發 |
|---|---|---|---|---|
| Intro | CUE_BOSS_INTRO | 8 小節 @140 ≈ 13.7 s（可縮為 4 小節 ≈ 6.9 s） | 低音長音、動機預告，結尾接 Phase 1 下拍 | Boss 啟動 |
| Phase 1（HP 100–66%） | MUS_BOSS_P1 | 32 小節 ≈ 54.9 s loop | 主題陳述、銅管 + 打擊 | Intro 結束 |
| Phase 轉換 | CUE_BOSS_PHASE | 2 小節 ≈ 3.4 s | 打擊 fill 加上合唱「hit」 | server `BossPhase` 改變 |
| Phase 2（66–33%） | MUS_BOSS_P2 | 32 小節 ≈ 54.9 s loop | 加入合唱、音域擴大、節奏密度增加 | 轉換 stinger 結束 |
| Phase 3／Enrage（< 33%） | MUS_BOSS_P3 | 32 小節 ≈ 54.9 s loop | 升半音、雙倍打擊、動機完整強奏 | 轉換 stinger 結束 |
| Boss 擊殺 | CUE_BOSS_DEFEAT → CUE_VICTORY | 1 小節切斷 + 5–8 s | 在下一拍硬切，接勝利 fanfare | Boss HP = 0 |
| 全滅／失敗 | CUE_DEFEAT | 4–6 s | – | 所有參戰玩家死亡 |

### 5.2 規則
- **階段轉換要對齊小節：** 收到 phase 變更後，在**下一個小節線**播 CUE_BOSS_PHASE，stinger 結尾接新 phase 的第 1 小節。最長延遲 1 小節（約 1.7 s），可接受。
- **Boss telegraph 優先：** Boss 大招前搖期間，音樂 bus duck **−6 dB** 並做 2–4 kHz 的 EQ 凹陷（§9）。**[→ ChatGPT：需要 client 能收到「telegraph 開始」事件]**
- **階段數要資料化：** Boss 定義裡用 `MusicPhases = {1.0, 0.66, 0.33}` 這類設定，不同 Boss 可以有 2 或 3 個 phase。MVP 只做 **2 phase**（P1、P3）以控制成本，P2 列入 P1 優先級。
- 前 3 個 Boss 可共用一套「Generic Boss」音樂。區域最終 Boss 才有專屬主題（P2）。

---

## 6. 動態音樂狀態與轉場（Dynamic Music State Machine）

### 6.1 狀態機
```
          aggro on local player            damage dealt/taken
EXPLORE ─────────────────────────▶ ALERT ─────────────────────────▶ COMBAT
   ▲                                  │                               │  intensity ≥ 6
   │ 4 bars in ALERT, no aggro        │ aggro cleared > 4 s          │─────────────▶ HIGH_INTENSITY
   │◀─────────────────────────────────┘                               │◀───────────── (intensity ≤ 3 for 4 s)
   │                                                                  │
   │        COMBAT_END (no combat events 6 s + min dwell met)         │
   └────────── COOLDOWN (4 bars: L3/L4 out, L2 stays) ◀───────────────┘

Global overrides (horizontal switch): BOSS, PVP_MATCH, HUB, DEAD
```

| 狀態 | 啟用層 | 進入條件 | 離開條件 |
|---|---|---|---|
| EXPLORE | L0 + L1 | 預設 | aggro → ALERT |
| ALERT | L0 + L1(60%) + L2 | 任一敵人鎖定本地玩家 | 有傷害往來 → COMBAT；aggro 解除超過 4 s → EXPLORE |
| COMBAT | L0(70%) + L1(30%) + L2 + L3 | 本地玩家造成或受到傷害（或 ALERT 中敵人進入 15 studs） | 6 s 沒有戰鬥事件 **且** 已在 COMBAT 至少 8 s → COOLDOWN |
| HIGH_INTENSITY | L0(60%) + L2 + L3 + L4 | 強度分數 ≥ 6 | 分數 ≤ 3 持續 4 s → COMBAT |
| COOLDOWN | L0 + L1(淡回) + L2(淡出) | COMBAT 結束 | 4 小節後 → EXPLORE；期間重新開戰 → 直接回 COMBAT（不播 stinger） |
| DEAD | BGM 降到 20% + low-pass | 本地玩家死亡 | 重生 → EXPLORE（重新從 L0 淡入） |

### 6.2 轉場規則（Transition Rules）
| 轉場 | 方式 | 時機 | 淡入／淡出時間 |
|---|---|---|---|
| Layer 淡入（強度往上） | Vertical，調整 layer Volume | **下一拍**（不等整小節，反應要快） | 1 小節（100 BPM ≈ 2.4 s）；L3 可用 0.5 小節 |
| Layer 淡出（強度往下） | Vertical | 下一個小節線 | 2 小節（≈ 4.8 s） |
| 區域 ↔ 區域、Hub ↔ 區域 | Horizontal crossfade | 傳送／讀取畫面期間，不需對齊 | 出 1.5 s，入 2.0 s |
| 探索 → Boss | Horizontal | 小節線，先淡出區域 stems 1 小節，接 CUE_BOSS_INTRO | 出 2.4 s |
| Boss phase → phase | Stinger 橋接 | 小節線（§5.2） | 舊 phase 在 stinger 第 1 拍硬切 |
| 任何 → Victory/Defeat | Cue 覆蓋 | **立即**（≤ 1 拍） | BGM 0.3 s 快速淡出，或 duck 到 −18 dB |
| 死亡 | 濾波 | 立即 | 0.3 s 內 low-pass（EqualizerSoundEffect HighGain −30 dB 或等效設定），音量降到 20% |

- **Bar-sync 計算：** `barLen = 60 / BPM * 4`；`nextBar = ceil(master.TimePosition / barLen) * barLen`；在 `nextBar - master.TimePosition` 秒後執行轉場。
- **Hysteresis／Cooldown 參數**（全部資料化，放 `Shared/Config` 的 music 設定表，交由 ChatGPT/Claude 決定位置）：

| 參數 | 預設 | 目的 |
|---|---|---|
| `CombatExitDelay` | 6 s | 最後一次戰鬥事件後多久算脫戰 |
| `CombatMinDwell` | 8 s | 進戰鬥後至少停留多久，避免狀態來回跳 |
| `AlertClearDelay` | 4 s | aggro 解除後多久回探索 |
| `ReentrySkipStinger` | 10 s | 脫戰後 10 s 內再開戰，不播進戰 stinger 或 intro |
| `IntensityUp` / `IntensityDown` | 6 / 3 | 高強度進入／退出閾值（中間留 3 分緩衝） |
| `IntensityDownHold` | 4 s | 分數低於退出閾值要持續多久才退 |
| `CooldownBars` | 4 | 脫戰後的過渡小節數 |

### 6.3 強度分數（Intensity Score，每 0.5 s 在 client 計算）
```
score = 1 × (鎖定本地玩家的一般敵人數，上限 4)
      + 3 × (鎖定本地玩家的菁英數)
      + 2 × (本地玩家 HP < 35% ? 1 : 0)
      + 1 × (5 s 內受到的傷害 > 最大 HP 20% ? 1 : 0)
```
- 只用 client 已知、而且與本地玩家有關的資訊。PvP 中停用此公式（§4.1）。
- 權重屬於 tuning 值，放進設定表。

### 6.4 所需狀態訊號 **[→ ChatGPT：確認由哪個 service 提供]**
| 訊號 | 建議來源 | 傳遞方式（建議） |
|---|---|---|
| 敵人鎖定本地玩家 | Enemy AI（server） | enemy model attribute `TargetUserId` |
| 戰鬥事件（造成／受到傷害） | Combat service（#6） | 已有的受擊或回饋 remote；或 player attribute `LastCombatTime` |
| 本地玩家 HP | Humanoid 或 combat service | 已複製到 client |
| Boss phase、telegraph | Boss 邏輯 | boss model attribute `BossPhase`、`TelegraphUntil` |
| PvP 比賽狀態、剩餘時間 | PvP round service | ReplicatedStorage 的 match state 或 attributes |
| 區域 ID | Zone system | player attribute `ZoneId`，或 client 端以 region 判定 |
| 升級、解鎖、掉落、任務 | Progression service | 既有的 `StateChanged` remote（PR #4）上的事件類型 |

> 盡量沿用 attributes 與既有 remotes，**不為音樂新增 remote**。若一定要新增，由 ChatGPT 決定。

---

## 7. Loop 與長度建議（Per-BGM）

| 資產 | BPM | 小節數 | Loop 長度 | 備註 |
|---|---|---|---|---|
| MUS_HUB_MAIN | 90 | 48 | 128.0 s | Hub 停留時間長，長 loop 可減少疲勞；可做 A/B 兩段 |
| MUS_Z{n}_L0–L4（每條） | 100 | 48 | 115.2 s | 5 條 stems **必須完全等長**，loop 點要精確到 sample |
| MUS_BOSS_P1 / P2 / P3 | 140 | 32 | 54.9 s | Boss 戰通常 1–4 分鐘，32 小節夠用 |
| MUS_PVP_MATCH | 128 | 64 | 120.0 s | 對應約 2–3 分鐘的比賽 |
| MUS_PVP_FINAL_L | 128 | 16 | 30.0 s | 與 MATCH 同步疊加（長度是 MATCH 的 1/4，可整除） |
| CUE_BOSS_INTRO | 140 | 4–8 | 6.9–13.7 s | 不 loop |
| CUE_BOSS_PHASE | 140 | 2 | 3.4 s | 不 loop |
| CUE_PVP_COUNTDOWN | 128 | 2 | 3.75 s | 不 loop |
| CUE_VICTORY | – | – | 5–8 s | 不 loop，含自然尾音 |
| CUE_DEFEAT | – | – | 4–6 s | 不 loop |
| CUE_LEVELUP | – | – | 3–4 s | 不 loop |
| CUE_UNLOCK | – | – | 4–5 s | 不 loop |
| CUE_LOOT_RARE / QUEST / ELITE | – | – | 2–3 s | 不 loop |
| CUE_ZONE_DISCOVER | – | – | 4–6 s | 不 loop |

**製作規格（交給作曲者或採購時使用）：**
- Loop 檔：開頭與結尾**不做淡入淡出**。殘響尾巴要「繞回」檔案開頭（wrap-around tail），才能無縫循環。
- 檔案長度必須是**整數小節**。匯出後要驗證 `TimeLength` 等於小節數 × 小節長度（誤差 < 1 ms）。
- 格式：OGG 或 WAV 上傳（Roblox 會轉碼），**≤ 48 kHz**、stereo 2.0。
- 響度（建議值，待 SFX_PLAN 對齊）：BGM 約 −16 LUFS integrated、true peak ≤ −1 dBTP；stinger 約 −14 LUFS short-term。stems 單獨匯出時，所有層加總後不能 clip。

---

## 8. 不同區域／世界的音樂個性

> **假設：** 區域主題未定，以下是依 progression 常見的「區域原型」預先配好的音樂個性。實際名稱與視覺以 `ART_DIRECTION.md` 為準，對齊後再改。

| 區域原型 | 進度位置 | 調式／色彩 | 代表樂器 | 情緒關鍵字 |
|---|---|---|---|---|
| Z1 新手區（森林／草原） | 1–10 級 | D Dorian，溫暖 | 撥弦、長笛、柔和弦樂 | 好奇、安全、輕快 |
| Z2 廢墟／荒漠 | 中前期 | E Phrygian dominant | 手鼓、低音弦、民族木管 | 神秘、乾燥、古老 |
| Z3 雪山／高地 | 中期 | F Lydian，空曠 | 鐘琴、玻璃質合成器、女聲合唱 | 冷冽、壯闊、孤獨 |
| Z4 火山／腐化之地 | 後期 | C 小調 + 減和弦 | 低音銅管、金屬打擊、失真低音 | 壓迫、危險、終局感 |
| PvP Arena | 解鎖後 | 動機反向，現代 hybrid | 合成器低音、電子打擊、銅管 | 競技、冷靜、專注 |
| Hub | 全程 | G 大調／Lydian | 鋼琴或木管主奏、溫暖弦樂 | 家、成長、休整 |

**一致性規則：** 每個區域的 L1 旋律都要引用 Ascension Motif 至少一次。每個區域的 L3 共用同一套「戰鬥節奏骨架」，只換音色與調式，讓玩家從節奏就能認出「進入戰鬥」。

---

## 9. 與 SFX 的混音優先規則（Mix & Ducking）

> `docs/SFX_PLAN.md` 尚未存在。以下是 Music 端的提案，**需要與 SFX Planner（#10）確認 bus 命名與數值後定案**。

### 9.1 SoundGroup 階層（提案）
```
SoundService
└─ Master (SoundGroup)
   ├─ Music (SoundGroup)            ← 玩家「音樂音量」滑桿
   │  ├─ Music_BGM (SoundGroup)     ← 所有 BGM／stems
   │  └─ Music_Stinger (SoundGroup) ← 所有 music cue
   ├─ SFX (SoundGroup)              ← 玩家「音效音量」滑桿（子群組由 SFX_PLAN 定義）
   │  ├─ SFX_Critical  (telegraph、低血警告、PvP 倒數)
   │  ├─ SFX_Combat    (命中、揮擊、技能)
   │  ├─ SFX_UI        (介面、獎勵)
   │  └─ SFX_Ambience  (環境)
   └─ Voice (SoundGroup, 預留)
```

### 9.2 優先層級（Priority Tiers）與 ducking
| Tier | 內容 | 對 Music 的處理 | Attack / Release |
|---|---|---|---|
| T0 Critical | Boss telegraph、低 HP 警告、PvP 倒數或開打 | Music_BGM **−8 dB** + 2–4 kHz 凹陷 −4 dB | 0.05 s / 0.8 s |
| T1 Combat burst | 玩家大招、重擊命中、爆擊 | Music_BGM **−3 dB**（只在 0.5 s 內 ≥ 3 個 T1 事件時觸發） | 0.05 s / 0.5 s |
| T2 Music Stinger | 升級、解鎖、勝敗 | Music_BGM **−6 dB**（勝敗為 −18 dB） | 0.1 s / 1.0 s |
| T2 UI/Reward SFX | 金幣、介面 | 不 duck | – |
| T3 Ambience | 環境音 | 不 duck 音樂；反過來在 COMBAT 狀態時 **SFX_Ambience −6 dB** | 1 s / 2 s |

- Ducking 用**腳本控制**：TweenService 調整 SoundGroup.Volume，結果可預測、好除錯。`CompressorSoundEffect` 的 sidechain 當作 P2 選項，需要 Studio 實測效果與效能。
- 多個 duck 同時存在時**取最大衰減，不疊加**。

### 9.3 頻段分配（Frequency Space）
| 頻段 | 優先給 | 音樂作曲、混音要求 |
|---|---|---|
| < 80 Hz | 重擊命中、爆炸 SFX | 戰鬥層低音在命中密集時不要持續壓在 40–80 Hz；BGM 在 60 Hz 以下 shelf −3 dB |
| 80–500 Hz | 音樂主體（低音弦、鼓） | 音樂主場 |
| 500 Hz–2 kHz | 音樂旋律、人聲（未來） | 共用 |
| **2–5 kHz** | **Telegraph、腳步、揮擊、UI 提示** | 戰鬥與 PvP 音樂在此頻段保持稀疏：不放持續高音弦、不放明亮 lead |
| > 5 kHz | 魔法 shimmer SFX、音樂空氣感 | 音樂只留少量空氣感 |

### 9.4 預設音量（提案，全部可在設定調整）
Master 1.0 · Music 0.5 · SFX 0.8。**手機喇叭**上音樂容易蓋掉音效，所以音樂預設值刻意偏低。

---

## 10. Roblox 實作注意事項

> 以下平台數字於 2026-09-27 查證 Roblox Creator Hub（`create.roblox.com/docs/audio/assets`、`/docs/projects/assets/privacy`、Open Cloud usage-assets guide）。平台規則會變，上傳前請再確認一次。

### 10.1 架構（符合 `ARCHITECTURE.md`：server authoritative、client 只做表現）
- **音樂只在 client 播放：** 做成 `StarterPlayer/StarterPlayerScripts` 下的 `MusicController`（遵循 PR #4 的 Controllers + ServiceLoader 模式：Init/Start）。Server **不播**音樂，也不建立 BGM 的 Sound。
- Server 只提供**狀態**（§6.4 的 attributes 與 remotes）。Client 負責判斷狀態、計算強度、做轉場。
- 非位置性（2D）音樂的 Sound 放在 `SoundService` 底下（不要放進 Part），並把 `SoundGroup` 指定到 Music_BGM 或 Music_Stinger。
- 維持 `SoundService.RespectFilteringEnabled = true`（預設）。client 播的音樂只有自己聽得到，這正是我們要的。
- 設定資料（音樂音量、靜音）會透過 PlayerDataService 儲存。**[→ ChatGPT/Claude：player data model 需要 `Settings.MusicVolume` 欄位]**

### 10.2 Sound API 用法
| 需求 | API | 注意 |
|---|---|---|
| Loop | `Sound.Looped = true` | 用 `Sound.DidLoop` 事件同步 layer |
| 位置、對齊 | `Sound.TimePosition` | 用來算 bar-sync（§6.2）；stems 之間用它做漂移校正 |
| 切段播放（stinger sheet） | `Sound.PlaybackRegionsEnabled = true` + `Sound.PlaybackRegion = NumberRange.new(a, b)` | 多個短 cue 合併成 1 個 asset，節省上傳配額；每段之間留 ≥ 0.5 s 靜音 |
| 載入狀態 | `Sound.IsLoaded`、`Sound.Loaded` | 還沒載入就不要啟動 layer 組 |
| 淡入淡出 | TweenService 調 `Sound.Volume` 或 `SoundGroup.Volume` | 不要每幀手動改 Volume |
| 濾波（死亡、telegraph） | `EqualizerSoundEffect`（放在 SoundGroup 下） | 用 tween 調 High/Mid/LowGain |
| 新 Audio API（可選） | `AudioPlayer`（有 `Looping`、`LoopRegion`、`PlaybackRegion`、`TimePosition`、`Play(atTime)`）+ `Wire` + `AudioDeviceOutput` | 新 API 路由彈性較高，但 MVP 建議先用 `Sound` + `SoundGroup`，較簡單、資料也多。`Play(atTime)` 能否做到精準對拍，需 Studio 實測後再評估 |

**Stem 同步（重要）：** Roblox 不保證多個 Sound 做到 sample 級同步。做法：
1. 同一組 stems 全部**在同一幀 `:Play()`**，未啟用的層 Volume = 0，**不要**用 Play/Stop 開關層。
2. 以 L0 為 master，每 2 s 檢查其他層：`abs(layer.TimePosition - master.TimePosition) > 0.05` 就把 `layer.TimePosition` 設成 master 的值（只對 Volume = 0 的層、或在小節線上校正，避免聽得到跳針）。
3. 手機上同一組最多 **5 條** stems，同時「有聲」的 ≤ 4 條（見 10.4）。

### 10.3 預載（Preloading）
- **加入遊戲的載入畫面：** `ContentProvider:PreloadAsync({MUS_HUB_MAIN, CUE_STINGER_SHEET})`，只載 Hub 與 stinger sheet。
- **進入區域前**（接近傳送門或讀取畫面時）：預載該區 5 條 stems。預載完成前先播 L0 或保持靜音，**不要**讓 stems 分批開始（會不同步）。
- **Boss：** 接近 Boss 房時預載 CUE_BOSS_INTRO 與 P1。P2、P3 在 Boss 戰開始後背景預載。
- 離開區域後，把該區 stems `:Stop()` 並 `:Destroy()`（或移出 SoundService），釋放記憶體。
- `PreloadAsync` 會 yield，**要放在 task.spawn 裡**，不能卡住主要初始化。

### 10.4 行動裝置效能（Mobile）
- 同時播放的音樂 Sound 預算：**≤ 6**（5 條 stems + 1 個 stinger），其中有聲的 ≤ 4。
- 可提供「低效能音樂模式」（P1）：只用 2 層（L0+L1 合併的探索混音，加上 L3 戰鬥混音），做 crossfade。
- 記憶體只保留：Hub、當前區域、stinger sheet，戰鬥中再加上 Boss。
- 別用大量 `SoundEffect` 疊加（reverb、chorus 等）。殘響在製作時就混進檔案，runtime 只保留 EQ 與 ducking。

### 10.5 上傳限制、權限、隱私（依 2026-09-27 查到的官方文件）
- **格式：** `.mp3`、`.ogg`、`.wav`、`.flac`，單一音軌。
- **大小與長度：** **< 20 MB** 且 **< 7 分鐘**；sample rate **≤ 48 kHz**；聲道 mono 或 stereo 2.0（也支援 3.0、5.1）。
- **上傳配額：** Creator Hub「Audio assets」頁面寫：ID verified 每 30 天 **2,000** 個，未驗證 **100** 個。Open Cloud 的 usage-assets guide 仍寫 ID verified **100**／月、未驗證 **10**／月。兩份官方文件不一致，**以上傳帳號在 Creator Hub 實際顯示的配額為準**。規劃時保守抓 MVP ≤ 10 個 asset（本文件的 P0 清單約 10 個）。
- **合法性：** 只能上傳擁有權利的音訊（自製、委託買斷，或授權明確允許在 Roblox 使用）。AI 生成音樂要確認工具條款允許商用與再散布。**不要**上傳商業歌曲。
- **Creator Store：** 有大量 Roblox 與合作夥伴提供、可免費使用的音樂與音效，適合當 MVP placeholder。仍要逐一確認 asset 可在本遊戲使用。
- **權限：** 上傳的音訊預設是受限制的，要在 Creator Dashboard → Development Items → Audio → Permissions → Experiences 用 Universe ID 授權給本遊戲。**對遊戲的授權一旦給出就不能撤銷。**
- **建議由擁有該 experience 的帳號或群組上傳**（Owner 帳號，或未來的 Group），免得權限問題導致 runtime 無聲（Output 會出現權限錯誤）。**[→ Owner：決定上傳帳號／群組]**
- **歌曲分類：** Roblox 會自動把上傳的音訊分類成 sound effect 或 song。符合條件的 song 可能會出現在遊戲頁面上，可在 asset 的 Configure 頁面關閉。
- **Repo 規範：** repo 內**只存 asset ID 的佔位**（例如 `Shared/Config` 裡 `MusicAssets.MUS_HUB_MAIN = "rbxassetid://0"`），不存音檔本體。音檔原始檔放在 repo 之外（Owner 指定的雲端資料夾）。

### 10.6 MusicController 骨架（pseudocode，最終實作由 Claude/ChatGPT 決定）
```lua
-- StarterPlayerScripts/Controllers/MusicController (sketch only)
local MusicController = { Priority = 50 }

function MusicController:Init(registry)
    -- build SoundGroups (§9.1) if not present, read Config.Music (BPM, bars, thresholds, asset IDs)
end

function MusicController:Start()
    -- preload hub + stinger sheet in task.spawn, then play hub
    -- listen: player ZoneId attribute, enemy TargetUserId, LastCombatTime, BossPhase, match state, StateChanged events
    -- every 0.5 s: evaluate state machine (§6.1) + intensity (§6.3) → schedule layer tweens on next beat/bar
    -- every 2 s: drift-correct stems against master (§10.2)
end

-- public API (for UI settings): SetMusicVolume(v), SetMuted(bool), PlayStinger(name)
return MusicController
```

---

## 11. 未來需要製作／取得的音樂素材清單

**命名規則：** `MUS_<區域或模式>_<名稱>[_L<層>]` 表示 BGM 與 layer；`CUE_<事件>` 表示一次性 cue。
**優先級：** **P0** = MVP 必要 · **P1** = 第一次內容擴充 · **P2** = 之後再做。
**上傳數** = 實際佔用的 Roblox 音訊上傳配額。

| ID | 名稱 | 類型 | Loop／長度 | BPM | 優先級 | 上傳數 | 備註 |
|---|---|---|---|---|---|---|---|
| MUS_HUB_MAIN | Hub 主題「Home of Ascension」 | BGM | 48 小節／128.0 s loop | 90 | P0 | 1 | 動機大調版 |
| MUS_Z1_L0 | 新手區 Ambient Bed | Layer | 48 小節／115.2 s loop | 100 | P0 | 1 | master 層 |
| MUS_Z1_L1 | 新手區 Explore Melody | Layer | 115.2 s loop | 100 | P0 | 1 | |
| MUS_Z1_L2 | 新手區 Tension Pulse | Layer | 115.2 s loop | 100 | P0 | 1 | |
| MUS_Z1_L3 | 新手區 Combat Drive | Layer | 115.2 s loop | 100 | P0 | 1 | 戰鬥節奏骨架 |
| MUS_Z1_L4 | 新手區 High Intensity | Layer | 115.2 s loop | 100 | P1 | 1 | MVP 可先省略，改用 L3 + 音量 |
| MUS_BOSS_P1 | Generic Boss Phase 1 | BGM | 32 小節／54.9 s loop | 140 | P0 | 1 | |
| MUS_BOSS_P3 | Generic Boss Phase 3（Enrage） | BGM | 54.9 s loop | 140 | P0 | 1 | MVP 採 2 phase |
| MUS_BOSS_P2 | Generic Boss Phase 2 | BGM | 54.9 s loop | 140 | P1 | 1 | |
| MUS_PVP_MATCH | PvP Arena 對戰 | BGM | 64 小節／120.0 s loop | 128 | P0 | 1 | 動機反向 |
| MUS_PVP_FINAL_L | PvP 最後階段層 | Layer | 16 小節／30.0 s loop | 128 | P1 | 1 | |
| CUE_STINGER_SHEET | Stinger 合輯（以 PlaybackRegion 切段） | Cue | 單檔約 60–90 s，不 loop | – | P0 | 1 | 內含 VICTORY、DEFEAT、LEVELUP、UNLOCK、LOOT_RARE、QUEST、ELITE、BOSS_INTRO、BOSS_PHASE、BOSS_DEFEAT、PVP_COUNTDOWN、ROUND_WIN、ROUND_LOSE、ZONE_DISCOVER |
| CUE_VICTORY | 勝利 fanfare | Cue | 5–8 s | – | P0 | （sheet 內） | |
| CUE_DEFEAT | 失敗 | Cue | 4–6 s | – | P0 | （sheet 內） | |
| CUE_LEVELUP | 升級 | Cue | 3–4 s | – | P0 | （sheet 內） | 動機完整、解決到主音 |
| CUE_UNLOCK | 武器／技能解鎖 | Cue | 4–5 s | – | P0 | （sheet 內） | |
| CUE_BOSS_INTRO | Boss 登場 | Cue | 6.9–13.7 s | 140 | P0 | （sheet 內） | 結尾對齊 P1 下拍 |
| CUE_BOSS_PHASE | Boss 階段轉換 | Cue | 3.4 s | 140 | P0 | （sheet 內） | |
| CUE_BOSS_DEFEAT | Boss 擊殺 | Cue | 1–2 s | 140 | P0 | （sheet 內） | 接 CUE_VICTORY |
| CUE_PVP_COUNTDOWN | PvP 倒數 | Cue | 3.75 s | 128 | P0 | （sheet 內） | |
| CUE_ROUND_WIN / CUE_ROUND_LOSE | 回合勝／負 | Cue | 2–3 s | – | P1 | （sheet 內） | 視 PvP 規則而定 |
| CUE_LOOT_RARE | 稀有掉落 | Cue | 2–3 s | – | P1 | （sheet 內） | |
| CUE_QUEST | 任務完成 | Cue | 2–3 s | – | P1 | （sheet 內） | |
| CUE_ELITE | 菁英出現 | Cue | 2 s | – | P1 | （sheet 內） | |
| CUE_ZONE_DISCOVER | 新區域發現 | Cue | 4–6 s | – | P1 | （sheet 內） | |
| MUS_HUB_SHOP_L1 | Hub 商店層 | Layer | 128.0 s loop | 90 | P2 | 1 | |
| MUS_Z2_L0–L4 | 區域 2 Zone Suite | Layer ×5 | 115.2 s loop | 100 | P1 | 5 | 依 ART_DIRECTION 定主題 |
| MUS_Z3_L0–L4 | 區域 3 Zone Suite | Layer ×5 | 115.2 s loop | 100 | P2 | 5 | |
| MUS_Z4_L0–L4 | 區域 4 Zone Suite | Layer ×5 | 115.2 s loop | 100 | P2 | 5 | |
| MUS_BOSS_<NAME>_P1–P3 | 區域最終 Boss 專屬主題 | BGM ×3 | 54.9 s loop | 140 | P2 | 3／Boss | |
| MUS_PVP_LOBBY | Arena 大廳變奏 | BGM | 64 小節 loop | 128 | P2 | 1 | |
| MUS_Z1_LOWSPEC_EXPLORE / _COMBAT | 低效能模式混音 | BGM ×2 | 115.2 s loop | 100 | P1 | 2 | §10.4 |

**P0 上傳總數：** HUB 1 + Z1 L0–L3 共 4 + BOSS P1/P3 共 2 + PVP 1 + STINGER_SHEET 1 = **9**（加上 L4 共 10）。
**取得方式建議：** MVP 先用 Creator Store 可免費使用的曲目當 placeholder，驗證狀態機與轉場。正式版再委託製作 stems（必須是同 BPM、同長度的分軌交付，否則無法 layering）。**[→ Owner：預算與來源決定]**

---

## 12. 相依、待決問題與後續

| # | 項目 | 對象 |
|---|---|---|
| 1 | 世界／區域主題定案後，更新 §1.2 樂器與 §8 區域個性 | Owner / Art Planner (#8) |
| 2 | `docs/SFX_PLAN.md` 落地後，對齊 SoundGroup 命名、ducking 數值、響度目標、level-up 等事件的 SFX 與 music 分工 | SFX Planner (#10) |
| 3 | §6.4 的狀態訊號（`TargetUserId`、`LastCombatTime`、`BossPhase`、`TelegraphUntil`、match state）由哪些 service 提供；是否能不新增 remote | ChatGPT / Claude (#4, #6) |
| 4 | Player data 新增 `Settings.MusicVolume` / `Settings.MusicMuted` | ChatGPT / Claude |
| 5 | PvP 模式規則（1v1／團隊、回合／計時） | ChatGPT / Owner |
| 6 | 音訊上傳帳號／群組、上傳配額確認（兩份官方文件數字不一致） | Owner |
| 7 | 音樂來源與預算（Creator Store placeholder → 委託製作） | Owner |
| 8 | Studio 實測：多 Sound stem 同步漂移、`AudioPlayer:Play(atTime)` 可行性、手機同時播放數 | Claude（實作時）／ Music Planner 協助驗收 |

**建議下一步：** ChatGPT 統合 → Claude 在 combat core（#6）之後實作 `MusicController` 的 MVP：Hub + Z1 L0–L3 + stinger sheet + Boss 2 phase + PvP 1 首。Music Planner 可同時整理 Creator Store placeholder 候選清單（P0 共 9–10 個）。
