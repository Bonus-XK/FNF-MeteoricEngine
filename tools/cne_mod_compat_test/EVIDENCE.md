# CNE 模组兼容 · 本轮交付证据（macOS，2026-09-18）

> 工作副本：`/Users/raidbounce/Documents/FNF-MeteoricEngine-1.0.4`，`master@70c358a2`，版本 1.1.3 / 校验码 4。
> 本轮用户约束：**只构建，不启动**（UI 与实机由用户第二轮测试）；没有 CNE 样本 mod。

## 1. 类型检查（release 配置）

```
$ ./compile-mac.sh typecheck
[typecheck] ✔ 类型检查通过（app 未被改动）        exit 0
```
完整日志：`out/typecheck.log`

## 2. 算法级实跑测试（执行仓库真实源码）

```
$ tools/cne_mod_compat_test/run.sh
chart_convert: PASS=34 FAIL=0 ; mod_compat: PASS=47 FAIL=0
RESULT: ALL PASS                                  exit 0
```
- `out/chart_convert.log`：CNE 谱面 → psych_v1。含 CNE 官方 base 谱面 `songs/bopeebo/charts/normal.json`
  的**真实数据**断言（118 音符守恒、玩家线 59 全落列 <4、对手线 59 全落列 >=4、bpm=100 取自 meta.json），
  以及覆盖 `Camera Movement`/`BPM Change`/`Time Signature Change`/`Alt Animation Toggle`/GF 线/
  长按/事件映射的合成谱面断言。
- `out/mod_compat.log`：CNE mod 兼容层。人物 XML→Psych JSON（全字段 + `indices="2..4,0"` 展开）、
  周目 XML→WeekFile、谱面定位（缺难度返回 null，不静默回退）、音频回退（含 `Voices-Player` 不接管）、
  zip 识别/暂存/指纹重解/`Paths.mods()` 入口重映射/同名文件夹优先。
- 运行方式与替身边界见 `README.md`（含**未覆盖项**：deflate 压缩 zip 未走通、实机接线未跑）。

## 3. 发布构建与产物

```
$ ./compile-mac.sh                                exit 0
export/release/macos/bin/Meteoric.app/Contents/MacOS/Meteoric
  size = 20,447,616 bytes    mtime = 2026-09-18 12:09:13
  find source Project.xml -newer <bin>  → 空（产物新于全部源码）
```
构建尾部日志：`out/build_tail.log`（含 `[post-build] restored user mods from tools/user_mods_prev/`）。

## 4. 新代码确实进入产物（二进制内字符串）

Haxe 字面量在本构建中是 **UTF-16LE**（已用已知串 `设置` ×33 校准），因此按两种编码分别统计：

| 串 | UTF-8 命中 | UTF-16LE 命中 | 含义 |
|---|---|---|---|
| `CNE 模组兼容` | 0 | **3** | 设置→编程 的新选项已编译（标签 + 说明） |
| `CNE 式 HScript 编程层` | 0 | 1 | 校准用（上一轮已存在的标签） |
| `codenameChart` | **3** | 0 | CNE 谱面格式探测在产物内 |
| `data/weeks/weeks` | **3** | 1 | CNE 周目扫描路径在产物内 |
| `mods/_cnestage` | 0 | 1 | zip 暂存目录在产物内 |
| `cneModCompat` / `[CNE-MOD]` / `_cnestage` | `strings` 命中 3 / 1 / 2 | — | 存档字段、日志前缀、暂存目录 |

## 5. 本轮**没有**做的验证（不要当成已验）

- **实机运行**：不启动游戏（用户明确要求），所以 `Mods.updateModList`/`ModsMenuState`/`Character.hx`/
  `Song.hx`/`WeekData.hx` 的接线只有类型检查级证据。
- **真实 CNE mod**：本轮没有样本 mod；第二轮由用户实机测试。
- **deflate（压缩）zip**：算法测试只用 `zip -0`（stored）；真实引擎的压缩分支走 lime 原生 zlib。
- **CNE 未覆盖面**：舞台 `data/stages/*`、人物 `.hx`、`data/notes/*.hx`、`.pack`、独立 `events.json`。
- Android / Windows 未验（本轮只在 macOS 上构建与测试）。

## 6. 第二轮（CNE mod 实测反馈后的改动，2026-09-18 12:49 构建）

改动：① CNE 舞台 XML → 背景图层 + 角色站位/相机偏移/zoom（`cne/CneModCompat.stageFile/stageSpriteNodes`
+ 新增 `states/stages/CneXmlStage.hx`，挂点 `backend/StageData.getStageFile` 与 `PlayState` 舞台 switch 的 default）；
② 人物加载优先级：mod 的 CNE `data/characters/<名>.xml` 现在排在**引擎内置 JSON 之前**（`objects/Character.hx`）；
③ 事件布尔参数归一化为 `'1'/'0'`（`CneExport.paramText`）。

证据（本轮按要求**只构建、不启动**，实机由用户截图验证）：
- `./compile-mac.sh typecheck` → ✔ 类型检查通过（`out/typecheck.log`）
- `tools/cne_mod_compat_test/run.sh` → chart_convert 41 + mod_compat 66 = **107 条断言全过**（新增 10 条舞台用例：zoom/三站位/相机偏移/图层节点）
- `./compile-mac.sh`（构建前先 `pkill -9 -f Meteoric`）→ exit 0；产物 12:49，`find source Project.xml -newer 产物` 为空
- 产物字符串：`CneXmlStage`×3、`CNE stage`×3、`stageSpriteNodes`×2、`data/stages/`（UTF-8 1 + UTF-16LE 1）
- 现场：SMA 已装入 `Resources/mods/SMA`（含补齐的 `data/characters/gf.xml`）、`modsList.txt` 首行 `SMA|1`、用户原 `mods/custom_events/Camera Flash.lua` 已还原

仍待用户截图确认：背景是否出现（street2 图层）、GF 是否改用 mod 的 `images/characters/gf/` 图集、角色站位是否符合 CNE 舞台 XML。

## 7. 第三轮（Unhappy 闪光弹 / 小图标 / NOTE 贴图，2026-09-18 13:0x 构建）

- **Camera Flash 参数映射**（修「1:42 闪光弹」）：CNE 参数是 `[reversed?, color, timeSteps, camera]`，
  而 Psych 同名自定义事件（用户装的 `mods/custom_events/Camera Flash.lua`）把 value1 当**时长(秒)**；
  上一轮的 bool→`'0'` 归一化让 `doTweenAlpha(...,0,...)` 变零时长 → 全屏白片永不淡出。
  现按 CNE 公式换算 `duration = (stepCrochet/1000) * timeSteps`、value2 = 颜色（`-1`/非法 → `ffffff`）。
- **小图标**：`HealthIcon.changeIcon` 增加 CNE 目录形态 `images/icons/<名>/icon.png` 兜底（SMA 的图标全是这种）。
- **NOTE 贴图**：新增 `CneModCompat.noteSkin()`，扫 mod 的 `images/game/notes/NOTE_assets*.png`
  → 写入 `SONG.arrowSkin`（`StrumNote.hx:59` / `Note.hx:994` 优先认它），SMA 的 `NOTE_assets_mack` 因此生效。
- 验证：`run.sh` → chart_convert 41 + mod_compat 67 = **108 条断言全过**（含 Camera Flash→`1.2`/`ffffff`、noteSkin 扫描）；
  typecheck ✔；release 构建 exit 0（构建前先 pkill），产物新于全部源码；产物含 `CNE note skin`/`Camera Flash`/`game/notes/` 等串。
- 本轮按要求**不启动游戏**，实机由用户截图验证。
