# 路径与格式基线（mods / 存档 / 容器）

本文件与 `path-format-surface.tsv` 一起构成**兼容契约的第二份门禁数据**。

| 项 | 值 |
|---|---|
| 生成脚本 | `tools/contract/gen_path_format.py` |
| 生成时 commit | `a73fd6a9923318b1a6c10b23898199b1c6c8d0fc` |
| 契约行数 | 76 |
| 排除行数 | 88 |
| 未归类 | 0 |
| §5 清单覆盖 | 17/17 |

## 一、契约面（必须冻结）

| kind | 名称 | 用途 | 站点数 |
|---|---|---|---|
| format | `.cnz` | CNE mod 打包扩展名（CneZipStore.hx:32） | 1 |
| format | `.zip` | mod 打包扩展名（ModInstaller.hx:243 / CneZipStore.hx:32） | 2 |
| format | `Meteoric.exe` | 容器包装器引用的宿主可执行名（ContainerLauncher.hx:229,241） | 2 |
| format | `activate.sh` | 容器前台化激活脚本名（ContainerStore.hx:39） | 1 |
| format | `cmd.txt` | 容器命令通道（ContainerStore.hx:42） | 1 |
| format | `container.json` | 容器清单文件名（ContainerManifestParser.hx:17） | 1 |
| format | `container.log` | 容器运行日志（ContainerStore.hx:32） | 1 |
| format | `dialogue.json` | 对话数据（DialogueEditorState.hx:533） | 1 |
| format | `events.json` | 事件数据（ChartingState.hx:2997） | 1 |
| format | `exit.txt` | 容器退出码（ContainerStore.hx:34） | 1 |
| format | `flags.ini` | CNE 状态重定向配置（mod 侧格式，StateRedirects.hx:47） | 1 |
| format | `meteoric_dpi_mode.txt` | 高清渲染档位落盘：单字符 '1'/'0'（ClientPrefs.hx:748-749） | 1 |
| format | `pack.json` | mod 包描述（Mods.hx:161 / ModZipPlanner.hx:19） | 2 |
| format | `phase.txt` | 容器会话相位（ContainerStore.hx:43） | 1 |
| format | `wrapper.bat` | 容器包装器脚本名·Windows（ContainerStore.hx:37） | 1 |
| format | `wrapper.sh` | 容器包装器脚本名·POSIX（ContainerStore.hx:35） | 1 |
| hook | `Main.hx` | 容器每帧钩子/会话驱动（§5 容器行） | 5 |
| module | `ContainerInfo` | 容器模块（§5 容器行） | 1 |
| module | `ContainerLauncher` | 容器模块（§5 容器行） | 1 |
| module | `ContainerManifest` | 容器模块（§5 容器行） | 1 |
| module | `ContainerManifestData` | 容器模块（§5 容器行） | 1 |
| module | `ContainerManifestParser` | 容器模块（§5 容器行） | 1 |
| module | `ContainerProcess` | 容器模块（§5 容器行） | 1 |
| module | `ContainerResourceSpec` | 容器模块（§5 容器行） | 1 |
| module | `ContainerSession` | 容器模块（§5 容器行） | 1 |
| module | `ContainerStore` | 容器模块（§5 容器行） | 1 |
| module | `ContainersMenuState` | 容器菜单入口（§5 容器行） | 1 |
| module | `Phase` | 容器模块（§5 容器行） | 1 |
| path | `_cnestage` | CNE 暂存目录保留名，不得被扫成假 mod（CneZipStore.hx:29 / Mods.hx:42） | 2 |
| path | `_containers` | 容器根目录保留名，不得被扫成假 mod（ContainerStore.hx:24,25,30 / Mods.hx:38） | 5 |
| path | `mods` | mod 根目录名（AndroidStorage.hx:123 / ModInstaller.hx:445,652 / ContainerStore.hx:96） | 27 |
| save | `Offsets.txt` | 角色偏移存档（CharacterEditorState.hx:1292） | 1 |
| save | `meoptions` | Android 权威设置文件：无扩展名 + JSON（写 ClientPrefs.hx:352 / 读 :585） | 2 |
| save | `modsList.txt` | mod 清单：Android 落 AndroidStorage.root()+'/modsList.txt'，桌面落 'modsList.txt'（Mods.hx:184-186） | 2 |
| save | `weekList.txt` | 周目清单（WeekData.hx:100、:128） | 2 |

## 二、显式排除（附理由，防止静默遗漏）

| 名称 | 理由 | 站点数 |
|---|---|---|
| `.json` | 文件名拼接片段（非完整契约 token） | 43 |
| `.luagraph.json` | LuaGraph 工具自有保存格式（非 mod/存档/容器契约） | 1 |
| `.txt` | 文件名拼接片段（非完整契约 token） | 10 |
| `Animation.json` | 示例资源路径 | 1 |
| `Animation.json` | 角色图集元数据路径 | 4 |
| `characterList.txt` | 编辑器素材清单 | 1 |
| `credits.txt` | 引擎内置内容清单 | 2 |
| `desktop.ini` | 压缩包内需忽略的系统垃圾文件（ZipReader.hx:187） | 1 |
| `dev_diag.txt` | 开发诊断落盘（CrashHandler:894） | 1 |
| `freeplaySonglist.txt` | 引擎内置曲单 | 2 |
| `gfDanceTitle.json` | 标题画面素材路径 | 1 |
| `heartbeat.txt` | 心跳诊断落盘（CrashHandler:961） | 1 |
| `introText.txt` | 引擎内置文案 | 1 |
| `last_stage.txt` | 崩溃诊断落盘（CrashHandler） | 2 |
| `library.json` | 图集运行时元数据 | 1 |
| `list.txt` | 溅射素材清单 | 1 |
| `list.txt` | 皮肤素材清单 | 1 |
| `meta.json` | CNE 图集元数据路径 | 4 |
| `profile.txt` | 性能探针输出（MeteoricProfile:75） | 1 |
| `readme.txt` | 编辑器导出说明文件的过滤项（ChartingState.hx:934） | 2 |
| `spritemap.json` | 示例资源路径 | 1 |
| `spritemap1.json` | 角色图集元数据路径 | 3 |
| `stageList.txt` | 编辑器素材清单 | 1 |
| `thumbs.db` | 压缩包内需忽略的系统垃圾文件（ZipReader.hx:187） | 1 |
| `weeks.txt` | 内置周目素材清单 | 1 |

## 三、一条命令校验

```bash
python3 tools/contract/gen_path_format.py --check
```

## 四、已知边界

1. 归类为**人工决策**：每个新出现的候选 token 必须在此文件登记（contract 或 exclude），否则 `--check` 判 FAIL。
2. 本基线冻结的是**路径字符串与格式约定**，不含 Lua/HScript 入口名（见 `script-surface.tsv`）。
3. `生成时 commit` = 生成时的 HEAD（基线自身入库前的父提交），属设计使然。
