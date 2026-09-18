# CNE 模组兼容层 · 算法级实跑测试（无样本 mod、不启动游戏）

## 这是什么

`「CNE 模组兼容」`（设置 → 编程 → CNE 模组兼容）把 Codename Engine 格式的 mod 加载进 Meteoric：
CNE 谱面（`codenameChart`）转 psych_v1、CNE 音频布局回退、CNE 人物 XML → Psych 人物 JSON、
CNE 周目 XML → Psych 周目、`mods/*.zip` 透明暂存。

本轮**没有 CNE 样本 mod、也不允许启动游戏**（用户要求"只构建，不启动"），所以这里用另一种
可复核的验证方式：把**仓库真实源码逐字节复制**进 `/tmp` 临时工程，只把 flixel / lime / backend
依赖换成字段与语义一致的替身，然后 `haxe --interp` **直接执行真实代码**并跑断言。

| 被执行的**真实源码**（每次运行时从仓库复制，不在本目录留副本，避免与源码漂移） | 替身（本目录 `stubs/`） |
|---|---|
| `source/states/editors/content/CneExport.hx`（`cneToPsych` / `isCneFormat`） | `flixel/util/FlxSort.hx`（与 flixel 6.2.0 逐行一致）、`backend/Song.hx`+`backend/Section.hx`（typedef 逐字段一致） |
| `source/cne/CneModCompat.hx`（人物/周目/谱面定位/音频回退） | `backend/Paths.hx`（`formatToSongPath`/`modFolders`/`mods`/`modsRaw` 按仓库原文语义，仅根目录可注入）、`ClientPrefs`/`Mods`/`Difficulty`/`CoolUtil` |
| `source/cne/CneZipStore.hx`（zip 暂存/指纹/重映射） | `lime/utils/Bytes.hx`（deflate 分支替身，本测试的 zip 用 `zip -0` stored，**不覆盖 deflate 路径**） |
| `source/backend/ZipReader.hx`（解包） | — |

## 运行

```sh
tools/cne_mod_compat_test/run.sh
```

- 依赖：`haxe`（4.2.5 已验证）、`zip` / `unzip`。
- CNE 源码快照位置：默认 `~/Documents/CodenameEngine-main`（读它的官方 base 谱面做真实数据断言），
  可用 `CNE_SRC=/path/to/CodenameEngine-main` 覆盖。
- 输出：`out/chart_convert.log`、`out/mod_compat.log`；两个测试全过时退出码 0。

## 覆盖的断言

`chart_convert.log`（34 条，CNE 谱面 → psych_v1）

- 官方 base 谱面 `songs/bopeebo/charts/normal.json`：音符总数守恒、玩家线音符全部落列 `<4`、
  对手线全部落列 `>=4`、bpm 取自 `meta.json`、`format=psych_v1`、角色槽/stage 透传、类型名别名。
- 合成谱面覆盖全部分支：`Camera Movement`（strumLine 索引→`mustHitSection`）、`BPM Change`、
  `Time Signature Change`、`Alt Animation Toggle`、GF 线音符（取 mustHit 同向列 + `gfSection`）、
  长按长度、`Scroll Speed Change`↔`Change Scroll Speed`、自定义事件透传、
  镜头/变速/拍号/交替动画不再重复出现在 `events`。

`mod_compat.log`（47 条，兼容层）

- 人物：`sprite/icon/color/holdTime/scale/x/y/camx/camy/flipX/antialiasing` 全字段映射；
  `<anim>` 的 `name/anim/x/y/fps/loop` 与 `indices="2..4,0"` 区间展开。
- 谱面定位：默认难度 → `charts/normal.json`；指定难度缺谱 → **返回 null（不静默回退 normal）**。
- 音频回退：`songs/<song>/song/Inst|Voices` 命中；不接管 `Voices-Player`；非 `songs` 目录不接管；
  开关关闭时全部返回 null（零行为变化）。
- 周目：`<week name/chars/sprite/bgColor>` + `<song>` + `<difficulty name>` → Psych WeekFile；
  无 storymenu 背景图时 `weekBackground` 置空（不拼不存在的贴图路径）。
- zip：`mods/<名>.zip` 识别、`Paths.mods()` 入口重映射到 `mods/_cnestage/<名>/`、同名真实文件夹优先、
  `_cnestage` 自身不被重映射、zip 更新后（经 `clearCaches()`）指纹失效并重新解包。

## 明确未覆盖（不要当成已验证）

- **deflate（压缩）zip**：本测试只用 `zip -0`（stored）；真实引擎走 lime 原生 zlib（`ZipReader.hx:438-442`）。
- **实机运行**：本测试不启动游戏、不碰 `.app`；`Mods.updateModList`/`ModsMenuState`/`Character.hx`/
  `Song.hx`/`WeekData.hx` 的接线只经过 release 配置的类型检查，**运行时行为等第二轮实机测试**。
- CNE 舞台 `data/stages/*`、人物 `.hx`、`data/notes/*.hx`、`.pack`、独立 `events.json`：本轮不实现
  （见 `PROGRAMMING.md` 第 8 节"尚未覆盖"）。
- Android / Windows：本测试与构建都只在 macOS 上跑过。
