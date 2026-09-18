# CNE 编程层实机冒烟证据（2026-09-17）

## 环境

- 仓库：`/Users/raidbounce/Documents/FNF-MeteoricEngine-1.0.4`，`master@70c358a2`，version 1.1.3
- 平台：macOS；Haxe 4.2.5；Lime 8.2.2 / OpenFL 9.2.1；Flixel 5.2.2 源码覆盖；SScript 4.0.1
- 构建：`./compile-mac.sh debug`（定义 `meteoric_debug`）exit 0
- 类型检查（release 配置，不改 app）：`./compile-mac.sh typecheck` exit 0

## 测试开关

- 正常玩家开关：设置 → 编程 → `CNE 式 HScript 编程层`（`ClientPrefs.data.cneScripting`，默认 false）。
- 无 UI 自动化冒烟：调试构建下 `METEORIC_CNE_FORCE=1` 环境变量无视存档总开关（仅 `#if meteoric_debug` 编译）。

## 测试 mod

`tools/cne_test_mod/`（仅测试，不随构建分发）：

- `data/global/LIB_cne_test_mod.hx`：`create` 落盘 `cne_smoke_global_create.txt`；`beatHit` 在 8 的倍数落盘 `cne_smoke_global_beat.txt`。
- `data/states/TitleState/LIB_cne_test_mod.hx`：`create` 落盘宿主类名；`update` 落盘一次；第 120 帧调用 `CNE.reloadCurrentStateScripts()`；`destroy` 落盘时间戳。

## 开（`METEORIC_CNE_FORCE=1`）

stdout（`on5.log`）：

```
[CNE] TitleState integration reached; force=1
[CNE] global scripts loaded (1)
[CNE] programming layer initialized
[CNE] state scripts loaded: TitleState (1)
```

落盘文件：

```
cne_smoke_global_create.txt   = ok
cne_smoke_global_beat.txt     = 8
cne_smoke_state_create.txt    = 1789654502443.88|states.TitleState
cne_smoke_state_update.txt    = ok
```

结论：全局脚本、状态脚本都被加载；`create`/`update`/`beatHit` 生命周期回调实际执行；`state` 变量正确注入为 `states.TitleState`。

## 原地热重载（`on4.reload.head.log` + 该轮落盘）

上一轮（同样 `METEORIC_CNE_FORCE=1`）在第 120 帧触发 `CNE.reloadCurrentStateScripts()`，同一轮落盘：

```
cne_smoke_reload_trigger.txt  = ok
cne_smoke_state_destroy.txt   = 1789654437622.39
cne_smoke_state_create.txt    = 1789654437622.45|states.TitleState   ← 新脚本 create 时间戳晚于旧脚本 destroy
```

结论：F5 对应的原地重建脚本组路径（旧脚本 `destroy` → 新脚本 `create`）实际跑通，宿主 state 不重建、不重进关卡。

## 关（无 `METEORIC_CNE_FORCE`，测试 mod 仍启用）

stdout（`off.log`）：

```
[CNE] TitleState integration reached; force=null
```

无 `global scripts loaded` / `state scripts loaded`，且无任何 `cne_smoke_*.txt` 落盘。

结论：总开关关闭时编程层不加载任何脚本，行为与改动前一致。

## 尚未验证 / 未实现

- `StateRedirects`（flags.ini `[StateRedirects]` + `preStateSwitch` 改写）未实现。
- `.pack` 合并脚本格式未移植；只支持 `.hx/.hscript/.hsc/.hxs`。
- zip 内 mod 脚本未验证（当前按 `sys.FileSystem` 文件夹路径读取）。
- Android / Windows 实机未验证；本轮只做 macOS 冒烟。
- 编程分区 UI 的视觉审阅（截图）未做；当前只验证了编译、开关与脚本行为。
- release 构建（不带 `meteoric_debug`）尚未做完整 playthrough；已做 release 配置 typecheck。
