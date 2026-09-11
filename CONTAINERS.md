# Meteoric Engine · 多版本容器（Containers）

> 目标：让玩家把**别的引擎**（Psych Engine 0.6.3 / 0.7.3 / 1.0.4、SeiunEngine 等各版本）直接放进
> 一个文件夹，在 Meteoric 内一键切换过去玩它的 mod，退出后 Meteoric 自己回来并重启。
> 容器与 Meteoric 本体**完全隔离**：容器里的 mod 不会出现在 Meteoric 的 Mod 列表里。

---

## 1. 玩家怎么用（4 步）

> **前提：必须先重新构建一次**（`./compile-mac.sh`）。容器功能的源码在仓库里，
> 但 `export/release/macos/bin/Meteoric.app` 是**旧产物**时，游戏里是看不到入口的
> （判断方法：`strings Meteoric.app/Contents/MacOS/Meteoric | grep -c ContainerSession`，
> 结果为 0 就说明产物没跟上源码）。

1. 启动游戏 → `设置 → 容器`（**唯一入口**：主菜单不放容器项，那里需要 `mainmenu/menu_*.png` 美术资源）；
2. 进来后**先点左下角「容器功能：已关闭」把它切到「已启用」**（`containersEnabled` 默认关闭，
   关闭状态下「切换到此容器」是灰的——这是给老玩家的零感知默认值，不是故障）；
3. 点「打开容器文件夹」，把目标引擎整个丢进去，形如 `mods/_containers/psych-063/`，
   并在同目录放一个 `container.json`（模板见下方第 2 节）；
4. 回游戏点「重新扫描」→ 选中该容器 →「切换到此容器」（或直接按 Enter）。

> **当前构建状态**：产物已重建（`Meteoric.app` 内含容器代码，校验：
> `python3 -c "d=open('.../MacOS/Meteoric','rb').read(); print(d.count(b'kill -CONT'))"` → 非 0），
> 且已放好一个空的示例容器 `示例-psych-0.6.3`（只有 `container.json`，等你把 `Psych Engine.app` 放进去）。
>
> 注意：源码树顶层那个 `mods/` 只是**新构建的模板**，游戏实际读的是
> `export/release/macos/bin/Meteoric.app/Contents/Resources/mods/`。用界面上的
> 「打开容器文件夹」按钮打开的就是后者，直接把目标引擎放进去即可。

切过去之后：Meteoric 窗口**隐藏**并把进程挂起（不占 CPU）→ 目标引擎被自动提到前台、独占屏幕与键盘 →
**直接关掉目标引擎窗口**（或 `Cmd+Q`）→ wrapper 唤醒宿主 → Meteoric 恢复窗口并整机重启，回到游戏。
（返回热键 `Ctrl + C` 仅在 Meteoric 窗口仍为前台时有效，详见第 3 节。）

### 目录布局

```
<Meteoric.app/Contents/Resources>/mods/
  _containers/                     ← 已登记进 Mods.ignoreModFolders ⇒ 不会变成“模组”
    psych-063/
      container.json               ← 清单（必需）
      Psych Engine.app/            ← 目标引擎（macOS：整个 .app；Windows：exe + 同目录资源）
      resources/                   ← 可选：要搬给目标引擎的 mod / 存档 / 数据
      runtime/                     ← 引擎生成（wrapper.sh / wrapper.bat、app.pid、exit.txt、container.log、activate.*）
```

> `_containers/` 与它下面的子目录都**不会**出现在 `Mods` 列表里，也不需要加进 `modsList.txt`。
> 实现方式：`Mods.ignoreModFolders` 里登记了 `'_containers'`（`getModDirectories()` 只认这张
> 白名单，**没有**「下划线前缀自动跳过」这条规则）。

> ⚠️ **硬约束：容器目录名必须是纯 ASCII（字母/数字/`-`/`_`/`.`）。**
> 实测结论（2026-09-10）：把 Meteoric 1.1.0 的 `.app` 放进名为 `示例-psych-0.6.3` 的容器后，
> 它每次启动都在 `lime.text.Font::__fromFile → NativeCFFI.lime_font_load_file` 抛
> `Error : Invalid UTF16` 秒退（退出码 255）；把**同一份字节完全相同**的 app 复制到纯 ASCII
> 路径（`/tmp/badcopy/...`）后立刻正常启动。已排除：文件清单/大小/md5、扩展属性、代码签名、
> 架构（都是 x86_64）、字体与 manifest 内容。**是路径里的非 ASCII 字符导致的**，
> 所以容器目录名与其中的 `README.txt` 等文件名一并保持 ASCII。显示名走 `displayName` 字段，
> 界面照样能显示中文。

---

## 2. container.json 模板

```json
{
  "displayName": "Psych Engine 0.6.3",
  "version": "1.0",
  "engine": "psych-0.6.3",
  "author": "Shadow Mario",
  "description": "官方 0.6.3 发行包。放这里是为了跑老 0.6.3 mod。",
  "app": "Psych Engine.app",
  "exitMode": "terminate",
  "suspendHost": true,
  "waitSeconds": 1.4,
  "env": { "SDL_HINT_NO_SIGNAL_HANDLERS": "1" }
}
```

### 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `app` | 否 | 主程序。可用 `.app` 目录名、bundle 内相对路径、或绝对路径；**留空则自动探测**（先找 `*.app` → 再找带执行位的文件 → 再找 `*.exe`） |
| `displayName` | 否 | 界面显示名，缺省用文件夹名 |
| `version` / `engine` / `author` / `description` | 否 | 纯展示，界面详情区显示 |
| `resources` | 否 | 自定义搬运规则数组：`[{"dir":"mods","to":"mods"}, {"dir":"config.json","to":"config.json","file":true}]`；留空则把 `resources/` 下每个条目按同名搬到目标引擎资源根 |
| `exitMode` | 否 | `terminate`（默认，先 SIGTERM 宽限 1.2s 再 SIGKILL，目标引擎有机会自己保存退出）/ `kill`（直接 SIGKILL） |
| `ExitKey`（存档字段 `containerExitKeys`） | — | 容器返回热键，默认 `[CONTROL, C]`；**组合键**语义（先按住 CONTROL 再按 C），见第 3 节 |
| `waitSeconds` | 否 | 拉起目标引擎后等多久让位并挂起，默认 `1.4`。老机器/大引擎可调到 `2.5` |
| `env` | 否 | 追加给目标引擎的环境变量（引擎默认已注入 `SDL_HINT_NO_SIGNAL_HANDLERS=1` 与 `SDL_VIDEO_CENTERED=1`） |

### 资源搬运规则（staging）

引擎会在每次启动前把 `resources/` 里的东西搬到**目标引擎的资源根**：

- `.app` bundle → `<X.app>/Contents/Resources/`
- 裸可执行档 → 可执行档同目录

搬运**只增不改**：不写目标引擎的配置、不改主程序、不删它的文件。工作目录（cwd）也设为该资源根，
所以 Psych 0.6.3 这类“`Paths.mods()` 是相对 cwd 的 `mods/`”的引擎能直接认到容器里的 mod。

---

## 3. 退出容器（怎么回来）

**主要方式：直接关掉目标引擎窗口**（窗口红叉 / `Cmd+Q`）。目标进程退出 → wrapper 检测到 →
`kill -CONT` 唤醒宿主 → 宿主恢复窗口并整机重启。实测已验证（`exit=0`，`phase` 落 `idle`）。

**返回热键 `Ctrl + C` 只在 Meteoric 窗口仍是前台时有效** —— 这是"目标引擎拿到焦点"的必然结果：
一旦目标引擎成为前台应用，键盘事件全部进它，宿主收不到（宿主还被 `SIGSTOP` 冻着）。
热键本身是真组合键：`CONTROL` 必须**按住**、`C` 必须**本帧刚按下**，单独按任一键都不会退出
（2026-09-11 修复：旧实现逐键独立判定，等价 `CONTROL || C`，导致"一按 Control 就回主引擎"）。

它是**容器专属字段**，不在 `keyBinds` 表里，所以改它不会动老存档的 `controls_v3`。
改法：直接编辑存档里的 `containerExitKeys` 数组（键名或键码都认，例如 `["F10"]`、`["CONTROL","C"]`）。

> 在**终端**里按 Ctrl+C 启动的游戏：终端 SIGINT 会同时打到两个进程，目标引擎退出 → wrapper 唤醒 Meteoric，
> 这条路径依然有效（wrapper 带 watchdog 兜底，不会把 Meteoric 留在挂起态）。
>
> 回到宿主时宿主会**主动抢回前台**（`restoreHostWindow()` → osascript 按 pid 置前）。
> 这一步不能省：宿主若停在失焦状态，flixel 在 `_lostFocus && FlxG.autoPause` 下**整机不更新**。

---

## 4. 实现概要（维护者视角）

| 文件 | 职责 |
|---|---|
| `backend/ContainerManifest.hx` | `container.json` 解析；解析永不抛异常，问题折成 `problem` 文案给界面 |
| `backend/ContainerStore.hx` | 目录发现 / 容器扫描 / 资源 staging / 文件系统小工具 |
| `backend/ContainerLauncher.hx` | 生成 `wrapper.sh`（macOS）/ `wrapper.bat`（Windows）+ 前台化脚本、拉起目标引擎、日志与运行期状态文件 |
| `backend/ContainerProcess.hx` | 跨平台进程原语：探活（macOS `kill -0` / Windows `tasklist`）、前台化、命令执行 |
| `backend/ContainerSession.hx` | 会话状态机：启动 → 让位 → 挂起 → 唤醒 → 整机重启 |
| `states/ContainersMenuState.hx` | 系统域界面（MD3 面板、列表 + 详情 + 操作条、三套输入） |
| `Main.hx` | `setupContainerHook()`：桌面端每帧驱动会话（宿主被 SIGSTOP 后由这一帧接上） |

### 为什么必须用 wrapper 脚本

1. 宿主一旦 `SIGSTOP`，它自己不可能再去 `wait` 子进程 —— 必须有一个**独立于宿主生命周期**的
   进程负责“目标引擎退出后唤醒宿主”。wrapper 用 `nohup … &` 后台化，宿主被 STOP/KILL 都不影响它。
2. 唤醒信号由 wrapper 发（`kill -CONT <宿主 pid>`），不依赖宿主自身事件循环，所以目标引擎
   崩溃 / 被 Ctrl+C 强杀 / 秒退，宿主都一定会回来。
3. 全程**文件通信**（`app.pid` / `exit.txt` / `cmd.txt` / `phase.txt`），宿主侧零线程、零阻塞读 ——
   规避本项目已确认的“工作线程分配 hxcpp GC 对象破坏堆”风险（见 `LoadingState.hx` 大段注释）。

### 为什么“让位”是隐藏窗口（2026-09-11 修正）

先前写的是“缩成 1×1”，实测证明**行不通**：缩小的窗口依然是 key window，macOS 认为
Meteoric 仍占据前台，于是目标引擎的前台化请求被判为“后台应用抢焦点”而拒绝 ——
症状正是“点标题栏能把它弄到最前、随即又掉到后面，键盘进不去”。
现在改为 `window.visible = false`（SDL_HideWindow）：SDL 交出窗口级焦点，目标窗口才拿得到键盘。

同时**前台化改由独立脚本负责**（`runtime/activate.sh`，`ContainerLauncher.buildActivator()` 生成）：
宿主在 `STOPPING` 阶段就已 `SIGSTOP`，之后任何宿主侧重试都不会执行，而 FNF 类目标引擎的窗口
要几百毫秒到数秒才创建。旧实现在 0.6s 只试一次就放弃，等于前台化从未成功过。
脚本用 `nohup` 独立于宿主生命周期，宿主冻结期间照样重试，并且：

1. 轮询 `app.pid` 直到目标引擎写出 pid（最多 60×0.1s）；
2. 每 2s 问一次 System Events：目标进程是否**已经**在前台 —— 是则什么都不做（不反复抢焦点）；
3. 不是则 `set frontmost ... to true`，成功即停；
4. 三道闸：进程已死 / 已在前台 / 连续 3 次失败即放弃并留痕（绝不无限刷日志，实测过这一点）。

实测记录（本机）：把 `motrix-next`(pid 9603) 从后台激活为 frontmost，try 0 成功；
目标 pid 不存在时 0 秒退出、零日志。

---

## 5. 已知边界（务必先读）

- **平台**：**macOS / Windows 双平台**（Android 按需求直接舍弃；容器界面/入口都有 `#if desktop`）。
  两平台的宿主让位机制**不同**，这是有意的：

  | | macOS | Windows |
  |---|---|---|
  | 包装器 | `runtime/wrapper.sh`（POSIX shell） | `runtime/wrapper.bat`（cmd） |
  | 宿主让位 | 缩窗 1×1 + `visible=false` + `kill -STOP` | `visible=false`，**不挂起** |
  | 唤醒方式 | wrapper `kill -CONT <hostPid>` | 宿主每帧 poll `exit.txt`（无需信号） |
  | 宿主 pid | **必须**（拿不到就拒绝启动） | 不需要（也不会因同名 exe 误杀） |
  | 退出码 | `wait $ME_APP` → `$?` | `start /WAIT` → `%ERRORLEVEL%` |
  | 前台化 | `osascript` + System Events（需「自动化」授权） | `activate.ps1` + `WScript.Shell.AppActivate`（无需授权） |
  | 默认热键 | **Ctrl + C**（组合键） | **F10**（单键） |
  | 退出核对 | 不需要（wrapper 语义可靠） | 宿主核对进程是否真的退出，超时 1.5s 则 `taskkill /F /T` |

  Windows 不挂起的理由：`kill -STOP` 没有干净等价物，`ntdll!NtSuspendProcess` 属未公开 API。
  隐窗后 SDL 不渲染隐藏窗口，CPU 接近零；代价是宿主进程留在内存（约数百 MB），
  好处是全程无信号、无未公开 API，且能被任务管理器正常看到、随时可结束。

- **自动前台化**：宿主隐窗后由独立脚本把目标引擎提到前台（macOS `activate.sh` / Windows `activate.ps1`）。
  macOS **首次会弹一次「自动化」授权**；拒绝只影响自动前台化（手动点一下目标引擎窗口即可），
  不影响启停与返回。授权被拒时脚本会在 `container.log` 里写明“放弃自动前台化”。Windows 无此授权要求。
- **不是窗口内嵌**：目标引擎是**独立进程 + 独立窗口**，Meteoric 让位。
  这条**不是偷懒，是系统限制**：Windows 上唯一的跨进程内嵌手段 `SetParent()` 官方明确要求
  「两个窗口必须由同一个进程创建」（A window can be a child window of another window only if both
  windows were created by the same process），而容器方案的本质就是两个独立进程；
  macOS 更是连等价 API 都没有。真要内嵌只能把目标引擎改成宿主加载的 DLL（逐个引擎改渲染循环，
  与“把现成发行包丢进容器就能用”互斥），故本版本不做。
- **Meteoric 侧退出即整机重启**：目标引擎退出后走 `FlxG.resetGame()`（等于“关掉再打开”），
  丢弃当前界面与局内状态。这是需求确认过的行为；好处是不存在“挂起那一刻的中间状态”残留。
- **多个容器同时只有一个**：`ContainerSession` 单例，已在运行时再次启动会被拒绝。
- **目标引擎需要写盘时**：`resources/` 的搬运是每次启动前执行，所以目标引擎自己在容器里
  产生的存档若写到了它自己的目录，会留在那个目录里（不会被 Meteoric 清掉）。
- **编译会重置 Resources**：`compile-mac.sh` 已把 `mods/_containers` 纳入备份/恢复，
  并额外做了一份 `tools/user_containers_prev/` 兜底快照。容器体积大时构建会变慢，属预期。

---

## 6. 排错

| 现象 | 看哪里 |
|---|---|
| 界面显示 ⚠ + 原因 | 详情区红字即 `problem`：缺 `container.json` / 找不到主程序 / JSON 语法错 |
| 切过去黑屏很久 | 调大 `waitSeconds`；看 `runtime/container.log`（目标引擎 stdout 也写在这里） |
| 回不来 | macOS 理论上不可能（wrapper 有 watchdog + 40×0.25s 超时兜底）。若真发生：`ps aux \| grep Meteoric` 找宿主 pid 后 `kill -CONT <pid>`。Windows 下宿主从未挂起，直接看目标窗口是否还在，必要时任务管理器结束它 |
| 目标引擎窗口没到前台（macOS） | 授权「自动化」给 Meteoric；看 `runtime/container.log` 里 `[ME] activator:` 的结论行（成功/放弃） |
| 目标引擎窗口没到前台（Windows） | 看 `runtime/container.log` 里 `[ME] activator:` 行；本机不需要授权，失败多为 `AppActivate` 拿不到窗口（目标还没建窗） |
| 单独按 Control 就回了标题 | 已修（组合键语义）。若仍发生，说明产物没重建 |
| 回到标题画面但节拍不跳 | 已修（返回路径补播标题音乐）。根因：`FlxG.resetGame()` → `FlxG.sound.destroy()` 把 `FlxG.sound.music` 置空，而标题音乐原本只由 `beatHit()` 的 `sickBeats==1` 自举 ⇒ 死锁 |
| 目标引擎找不到容器里的 mod | 确认它在 `resources/mods/...`，且引擎的工作目录（资源根）是它认的 mods 位置 |
| 想确认容器是否在跑 | 容器界面状态行；或看 `runtime/phase.txt`（`running` / `exiting` / `idle`） |
| 设置里根本看不到「容器」 | 产物没重建：跑 `./compile-mac.sh`。自查：`strings Meteoric.app/Contents/MacOS/Meteoric \| grep -c ContainerSession`，0 = 产物落后于源码 |
| 「切换到此容器」是灰的 | 左下开关没打开（默认关闭），或该容器自检未通过（详情区红字给出原因） |
