# CNE 歌曲脚本运行时 + pluh 跳脸 — 证据（2026-09-18）

## 1. 本轮新增/改动（在上一轮 CNE 兼容工作树之上）

| 文件 | 改动 |
|---|---|
| `source/cne/CneScriptCompat.hx`（新增） | 扫描 `mods/<mod>/songs/<song>/scripts/*.hx`；注入 CNE globals（`stage.stageSprites` / `FunkinSprite` / `insert` / `add` / `remove`）；把 CNE 回调名 alias 到 Psych 回调名：`create→onCreate`、`createPost→onCreatePost`、`stepHit→onStepHit`、`beatHit→onBeatHit`。Psych 的 `callOnScripts('onStepHit')` 不传参，wrapper 从脚本变量 `curStep`/`curBeat` 取值再调 `stepHit(curStep)`。 |
| `source/cne/FunkinSprite.hx`（新增） | CNE `FunkinSprite` 真实子类；`makeGraphic` 协变返回 `FunkinSprite`（SScript 类型检查需要）；`screenCenter` 非 inline 覆盖（Flixel 的 `FlxObject.screenCenter` 是 inline，反射调用会 "Null Function Pointer"）。 |
| `source/backend/Paths.hx` | 新增 `getFrames(key)` = `getAtlas(key)`；**非 inline + `@:keep`**（release `--dce full` 会把只被反射调用的函数删掉，实测不加会 "Null Function Pointer"）。 |
| `source/states/stages/CneXmlStage.hx` | `<sprite name="...">` 注册进 `stageSprites:Map<String,FlxSprite>`；`public static var current` 暴露当前 CNE 舞台实例。 |
| `source/states/PlayState.hx` | `initHScript(file, ?cneGlobals, ?cneCallbacks)`：先 `new HScript(..., executeNow=false)` 注入 globals（CNE 脚本顶层就 `new FunkinSprite()`），再 `execute()`，之后挂回调别名，最后走既有 `onCreate`；`PlayState.create` 在角色/相机/舞台就绪后调用 `CneScriptCompat.loadSongScripts(this, songName)`。另有 debug-only `[DBG-PLAYANIM]` trace。 |
| `source/objects/Character.hx` | debug-only `[DBG-ANIM]`：请求不存在的动画时打印。release 不编译。 |
| `source/cne/CneModCompat.hx` | `stageSpriteNodes` 输出补 `name`；Freeplay 图标兜底改为**对手线优先**（SMA 老鼠），对手线内跳过无图标角色，全无图标才退玩家线。 |
| `source/states/editors/content/CneExport.hx` | `Play Animation` 目标按 strumLine type 映射（0→dad / 1→bf / 2→gf）。 |

## 2. 验证

- `./compile-mac.sh typecheck` → ✔ 通过（多次，最终版通过）。
- `./compile-mac.sh`（release）→ `release_build_exit=0`。
  - 产物：`export/release/macos/bin/Meteoric.app/Contents/MacOS/Meteoric`
    size=20456000  mtime=2026-09-18 21:46:09（新于全部被改源码）。
  - `export/release/macos/obj/src/backend/Paths.cpp` 保留 `getFrames`（6 处）→ 未被 DCE。
  - `export/release/macos/obj/src/cne/FunkinSprite.cpp` 含 `makeGraphic`/`screenCenter`。
  - binary strings 命中 `CNE song script`(2)、`FunkinSprite`(4)；`METEORIC_TEST_SONG`(0) —— release 不含调试直达钩子。
- 调试构建实跑（`METEORIC_TEST_SONG="really-happy|really-happy-hard|really-happy|2"`，debug 构建）：
  - `[CNE-MOD] CNE song script: mods/SMA/songs/really-happy/scripts/REALLYFUCKINGJOYOUS.hx`
  - 脚本 `create()` 完整跑完（插桩 trace `PLUH-13-ok`）；`stepHit` 在 128 / 760 / 768 均被调用。
  - `[DBG-PLAYANIM] t=65828 v1=dance v2=dad char=reallyhappyrat hasAnim=true` —— 1:05 变身事件确实触发。
  - 截图（`read_image` 已复核）：1:05 对手老鼠在跳舞；pluh 出现由用户本人确认「我看见了」。
- 诊断插桩脚本已还原：`mods/SMA/.../REALLYFUCKINGJOYOUS.hx` 中 `PLUH` trace 计数=0（app Resources 与 `tools/user_mods_prev` 两处均还原）。

## 3. 回滚

- 源码：`source/cne/CneScriptCompat.hx`、`source/cne/FunkinSprite.hx` 为新增，删除即可；其余改动按文件回退（上一轮已为 `CneExport.hx`/`CneModCompat.hx` 留 `.orig`）。
- 运行时：诊断时临时移走的 `mods/custom_events/Camera Flash.lua` 已由 trap 自动还原（验证：文件在位）。
- 诊断插桩：`/tmp/REALLYFUCKINGJOYOUS.hx.orig` 是原始脚本备份；已还原回两处 mod 目录。

## 4. 已知边界

- CNE 脚本 runtime 目前覆盖 SMA 这个脚本用到的 API；更复杂的 CNE 脚本类/回调（`.pack`、`data/notes/*.hx`、角色 `.hx`、完整 CNE 类库）仍未实现。
- `Play Animation` 的 CNE `强制/上下文` 参数未逐一代入 Psych 语义；当前与 Psych 内置一致（`playAnim(anim, true)` + `specialAnim=true`）。
- CNE 单 strumLine 多角色的游戏内切换仍未实现；本轮只保证 Freeplay 图标取到可解析角色。
- Android / Windows 未构建。
