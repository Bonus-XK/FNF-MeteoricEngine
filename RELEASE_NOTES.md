# Meteoric Engine v1.1.2

> 基于 Psych Engine 0.7.1h 深度魔改的 FNF 引擎。v1.1.2 以 **Mac 高帧率与安卓大谱面/存储兼容** 为核心：帧率上限与画质档位设置、JS 引擎 9 项优化融合、CastNote 管线接通安卓（226 万音符可玩）、Android 12 根目录 `.meteoric` 释放修复，并完成一批渲染/HUD 修复与性能工具。

---

## ✨ 版本亮点

**Meteoric Engine 1.1.2** —— 新增「帧率上限」（120 / 240 / 480 / 无上限）、「高清渲染」「性能模式」画质档位；设置二级页不再被遮挡父级白绘（帧率 ~900 → ~1300+）；PlayState 万帧稳定（GC 尖峰 120ms → ≤24ms）；移植 JS 引擎 9 项优化（默认全部原版行为）；安卓端接通 CastNote 轻量管线并修复 RGBPalette 移动端空指针；根治 Android 12 定制 ROM 上 `isExternalStorageManager()` 不可靠导致的「资源释放不到根目录 `.meteoric`」；设置 ◀▶ 支持长按连续调节。版本校验索引升级为 3。

---

## ⚡ 高帧率与性能

- **「帧率上限」设置**：`120 / 240 / 480 / 无上限` 四档，切换即时生效；桌面默认无上限，移动端默认 120 防过热
- **「高清渲染」**：`meteoric_dpi_mode.txt` 运行时模式文件（1x 高性能 / 2x 高清），重启生效，1x 下 Retina 帧率约 3 倍
- **「性能模式」（perfMode）**：渲染开销收紧，游戏中实时生效
- **设置二级页**：父级 `persistentDraw = false`（内容本就被完全遮住），二级页真实帧率 ~900 → ~1300+
- **PlayState 万帧稳定**：自定义 FlxGame 帧循环（桌面 100000 哨兵）；已消费音符引用定期释放，GC 尖峰 120ms → ≤24ms
- **FPS 计数器修复**：`_lastStamp` 时间戳修正，标题栏/角标读数真实并显示引擎版本
- 移除高开销 **FPS 波动图**

## 🧩 JS 引擎优化融合（9 项设置）

全部默认关闭 / 原版行为，可在 设置 → 性能 逐项开启：

- **HUD Only**：只渲染 HUD + 音符（角色/舞台与全屏雨滤镜不再绘制）
- **Allow GC**：关闭 GC 消除高帧率尖峰
- **Strum 呼吸灯 ×3**（对手 / 自动 / 玩家）
- **评分弹窗 / 连击弹窗**：可关（大谱面高密度命中不掉帧）
- **Less Botplay Lag**：自动游玩只计分不弹窗
- **No Hit Lua Calls**：关闭 goodNoteHit / opponentNoteHit 回调

## 🎨 渲染与 HUD 修复

- 「提前渲染音符」全朝左 bug：`recycleNote` 补 `defaultRGB()` + `tryUseBakedGraphic()`，复生音符按当前轨道着色/换烘焙图
- 血条图标飞出回位加速（600% 爆发后约 0.8s 回位，原 3~4s）
- RGBPalette 移动端 NRE：克隆条件改为 `allowNew && enabled && 值不同`（着色器未渲染时不再触碰 null uniform）

## 📱 安卓兼容与存储修复

- **CastNote 轻量管线接通安卓**（12 处 `#if android` → `#if false`，旧分支保留可回退）：Flocc Hard 226 万音符可加载可游玩，不再原生崩溃
- **Android 12 `.meteoric` 释放修复**：
  - 真实写探测权限判定（绕开定制 ROM `isExternalStorageManager()` 不可靠）
  - 授权后先迁移回退数据再建目录 → mods/assets 搬到根目录 `.meteoric`
  - 资源写盘失败不再静默跳过
  - 授权跳转三层兜底：按应用 → 全局总览 → 应用详情页
  - 未授权时显示手动授权路径，授权后重启自动迁移
- **设置 ◀▶ 长按连续调节**（0.5s 延迟；数字按 scrollSpeed 连续滚、字符串 0.2s 一档；开关仅单次切换）
- 9 项 JS 优化与「帧率上限」在安卓端验证可用

## 🧰 开发与诊断

- **MeteoricProfile**：每帧耗时探针（`-D METEORIC_PROFILE`，默认零开销）
- **GlErrorWatchdog**（Seiun 移植）：GL 错误轮询写入 CrashHandler 日志环
- **CrashHandler**：结构化日志环（最近 60 条）随崩溃报告输出

## 🔧 构建基础设施

- `ci/lime-sdl3-patch`：高精度性能计数器事件循环、高 DPI 模式文件开关
- CI：lime-full 缓存 key 纳入 `ci/lime-sdl3-patch/**`，setup 重试收紧

## 🔢 版本与更新校验

- 引擎版本 **1.1.2**，更新校验索引 **3**（`gitVersion.txt` = 1.1.2 / 3）
- APK 包版本 `versionName = 1.1.2`（与引擎版本一致；versionCode 由 lime 构建自动递增）
