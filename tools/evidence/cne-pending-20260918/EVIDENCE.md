# Meteoric Engine · CNE 待办修复证据（2026-09-18）

对象：`/Users/raidbounce/Documents/FNF-MeteoricEngine-1.0.4`（`master@70c358a2`，工作树含上一轮 CNE 兼容未提交改动）
权威依据：DSH 会话 `session-4a2c7a16…`（标题「ME + CNE」）与 `session-c16cce91…`（CNE mod 支持，末条用户反馈）
规则遵守：只构建、不启动游戏（用户要求）；构建前 `pkill -9 -f Meteoric`。

---

## 1. 本轮修的两项（上一轮末尾明确"没动手"的内容）

### ① Really Happy 中途不变身（SMA）

- **上一轮假设（已修正）**：以为是 CNE `Change Character` 事件或多角色 strumLine 变体切换。
- **新证据（真实数据）**：
  - `tools/user_mods_prev/mods/SMA/songs/really-happy/charts/hard.json` 的 `events` 里
    `Change Character` 出现 0 次，但有 `Play Animation [0,"dance",true,"NONE"]`（65828ms）
    和 `Play Animation [0,"death",true,"LOCK"]`（187885ms）。
  - `CneExport.hx` 旧代码把 Psych 事件 `Play Animation` 的 value2 **硬编码成 `'bf'`**：
    `subEvents.push(['Play Animation', …, 'bf']);`
  - strumLine 0 是 `type=0`，角色 `reallyhappyrat`（有 `dance`/`death` 动画）；
    strumLine 1 才是 `type=1`、角色 `bfsma`（`bfsma.xml` **没有** `dance`/`death`）。
  - 结果：变身动画被打到 bfsma 身上 → 播放失败 → 对手全程不变身。
- **修法**：新增 `CneExport.animTarget(params, lineTypes)`，按 CNE `params[0]`（strumLine 索引）
  对应的 `line.type` 映射 Psych 角色槽：`0→'dad'`、`1→'bf'`、`2→'gf'`（越界/未知按 0）。
- **真实数据验证**：`RealSma`（用仓库真实 `CneExport.cneToPsych` 跑真实 SMA 谱面）输出
  `["Play Animation","dance","dad"]`、`["Play Animation","death","dad"]`，且不再出现 `…,"bf"`。

### ② Freeplay 小灰人（SMA meta.icon="face" 不存在）

- **根因**：SMA 5 首曲的 `meta.json` 全写 `"icon":"face"`；mod 内没有 `images/icons/face.png`
  也没有 `images/icons/face/icon.png`。Psych 的 `HealthIcon.changeIcon` 会落到
  `icons/icon-face.png`（引擎通用灰脸）→ Freeplay 显示小灰人。
- **修法**：`CneModCompat.cneFreeplayWeek` 在写 Freeplay 列表前校验 `meta.icon` 是否真能解析
  （`iconUsable`，顺序与 `HealthIcon.changeIcon` 实际一致：`icons/<名>.png` →
  `icons/icon-<名>.png` → `icons/<名>/icon.png`；`face` 不把引擎的 `icon-face.png` 当真图标）。
  解析不到时，从该曲谱面 `strumLines` 的 `type=1`（玩家）行里取**第一个图标可解析的角色名**兜底。
- **补充修正（真实数据发现）**：只取 `characters[0]` 不够 —— SMA `smile` 玩家线是
  `["boyfunkle","bfsma"]`，`boyfunkle` 没有图标，`bfsma` 才有 `images/icons/bfsma/icon.png`。
  因此实现改为按顺序取第一个 `iconUsable` 的 type 1 角色。
- **真实数据验证**：`RealSmaFreeplay` 用真实 `mods/SMA` 跑真实 `cneFreeplayWeek`：
  `Unhappy/Happy/Really Happy/Smile → bfsma`，`WHISPERS → bf`（引擎 `assets/preload/images/icons/icon-bf.png`），
  **没有任何一首落到 `face`**。

---

## 2. 改动文件与补丁

| 文件 | 改动 |
|---|---|
| `source/states/editors/content/CneExport.hx` | `Play Animation` 目标角色改为按 strumLine type 映射；新增 `animTarget()` |
| `source/cne/CneModCompat.hx` | `cneFreeplayWeek` 增加图标校验+兜底；新增 `iconUsable()` / `playerCharacterForSong()` / `intOf()` |
| `tools/cne_mod_compat_test/stubs/chart/Test.hx` | 新增 B25/B26：`Play Animation[strumLine 0/1] → dad/bf` |
| `tools/cne_mod_compat_test/stubs/mod/Test2.hx` | 新增 5b9/5b10：无效 meta.icon → 第一个可解析图标的玩家角色（含 `["noicon","pico"]` 跳坑场景） |
| `tools/cne_mod_compat_test/stubs/mod/backend/Paths.hx` | 测试替身补 `fileExists()`（与生产 `Paths.fileExists` 的 mods 段一致） |
| `tools/cne_mod_compat_test/stubs/mod/openfl/utils/AssetType.hx` | 新增测试替身（enum abstract，供 `Paths.fileExists` 签名用） |

补丁原文见 `diffs/01_CneExport_PlayAnimation.patch`、`diffs/02_CneModCompat_FreeplayIcon.patch`。

回滚：本轮改动前的两份源码已备份为
`source/states/editors/content/CneExport.hx.orig`、`source/cne/CneModCompat.hx.orig`（`*.orig` 已被 .gitignore）。
回滚命令：
```sh
cp source/states/editors/content/CneExport.hx.orig source/states/editors/content/CneExport.hx
cp source/cne/CneModCompat.hx.orig source/cne/CneModCompat.hx
```

---

## 3. 验证记录（全部实跑）

### 3.1 算法级测试套件（真实源码 + 替身，`haxe --interp`）

```sh
tools/cne_mod_compat_test/run.sh
```
结果：
```
chart_convert: PASS=43 FAIL=0
mod_compat:    PASS=69 FAIL=0
RESULT: ALL PASS
```
新断言原文：
```
PASS  B25 Play Animation[strumLine 0] → dad
PASS  B26 Play Animation[strumLine 1] → bf
PASS  5b9 meta.icon 无对应贴图 → 用玩家角色图标兜底   [pico]
PASS  5b10 无法兜底的第二首保留 meta.icon=face2     [face2]
```
完整日志：`chart_convert.log`、`mod_compat.log`。

### 3.2 真实 SMA 数据验证（一次性脚本，不属测试套件）

日志：`realdata_verify.log`。关键输出：
```
PASS  RealSma dance → dad
PASS  RealSma death → dad
PASS  RealSma 不再打到 bf
...
SONGS=[["Unhappy","bfsma",…],["Happy","bfsma",…],["Really Happy","bfsma",…],["Smile","bfsma",…],["WHISPERS","bf",…]]
PASS  RealSmaFreeplay 图标兜底（无灰脸）
```

### 3.3 类型检查 + release 构建

```sh
pkill -9 -f Meteoric
./compile-mac.sh typecheck   # ✔ 类型检查通过（app 未被改动）
./compile-mac.sh             # build_exit=0
```
构建产物：
```
export/release/macos/bin/Meteoric.app/Contents/MacOS/Meteoric
  size=20497552  mtime=2026-09-18 19:53:58  （新于全部被改源码）
  strings 命中 "CNE freeplay icon fallback"、"Play Animation"
```
日志：`build.log`。

---

## 4. 已知边界（未在本轮声称已修）

- `Play Animation` 的 CNE 参数 `[StrumLine 索引, 动画名, 强制?, 上下文]` 只映射了前两项+目标角色；
  `强制/上下文` 由 Psych `Play Animation` 固定为 `playAnim(anim, true)` + `specialAnim=true`，与 CNE 的
  `LOCK`/`SING` 等上下文不完全等价。
- CNE 单个 strumLine 多角色（如 SMA `Unhappy` 的 `["sadrat","happyrat","happierat"]`、`smile` 的
  `["randah","randy"]` / `["boyfunkle","bfsma"]`）仍只按 Psych 的三个角色槽承载；本轮只保证
  **Freeplay 图标**会选到可解析的角色图标，游戏内多角色切换不在本轮范围。
- Android / Windows 未构建；本轮只在 macOS x86_64 上跑 typecheck + release 构建。
