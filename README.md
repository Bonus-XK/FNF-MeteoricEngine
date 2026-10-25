<div align="center">

# Meteoric Engine

**基于 Psych Engine 0.7.1h 深度重构的 Friday Night Funkin' 模组引擎**

*An FNF mod engine rebuilt for performance engineering and a CNE-grade scripting stack.*

![engine](https://img.shields.io/badge/engine-FNF%20%2F%20Psych%200.7.1h-8A2BE2)

![haxe](https://img.shields.io/badge/Haxe-4.2.5-orange)

![platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Android-blue)

![scripting](https://img.shields.io/badge/scripting-Lua%20%2B%20hscript--meteoric-green)

![license](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

## 这是什么

Meteoric Engine 不是换皮的 Psych——它把 Psych 0.7.1h 的脚本、加载、UI、回放与工程化底座  
全部翻新了一遍，并把脚本语言能力推进到与 Codename Engine 同级、部分领先的水平：

- 自研 HScript 方言 **[hscript-meteoric](https://github.com/Bonus-XK/hscript-meteoric)**  
  （独立仓库 / haxelib），补齐并超过 CNE 的脚本语法面
- 保留 Psych 的 Lua 生态（FunkinLua 全家桶），并与 HScript 双轨互通
- 工程纪律：双语 i18n 自检、契约基线冻结、typecheck/i18n 双门禁、实机验证文化

## 脚本系统

| 能力        | hscript-meteoric                                             |
| --------- | ------------------------------------------------------------ |
| 正则字面量     | `~/[a-z]+/i`                                                 |
| 字符串插值     | `'Hello $name'` / `'x=${expr}'`                              |
| switch 强化 | 守卫 `case 10 if (x > 5):`、或模式 `case 1 \| 2:`                  |
| 推导式       | `[for (k => v in m) k => v]`（Map 推导，支持守卫）                    |
| 解构        | 默认值 / 嵌套 / 重命名 / `...rest`                                   |
| 调用与函数     | spread `f(...arr)`、rest `f(a, ...rest)`、泛型 `f<T>`            |
| 空值        | `a?.b`、`a ?? b`、`a ??= b`                                    |
| 迭代        | `for (k => v in map)`                                        |
| 顶层声明      | `import`（含 `pkg.*` 与 `as`）/ `using` / `package` / 顶层 `class` |
| 脚本类       | 顶层类定义即可实例化；**继承引擎类**（编译期壳类，实例是真引擎子类）                         |
| 跨脚本状态     | `static` 变量真共享                                               |

Lua 侧沿用 Psych 的 API 面，参见 [LUA\_CLASS.md](LUA_CLASS.md)。

## 性能与加载工程

- **TuoboLoad** 极简加载档位：跳过 GF 构造等非必要路径
- **visualFold**：密集谱下同步压缩全局对象数量
- **墙钟 lime.ndll**：修正 M 系列亚毫秒帧间隔截断（自编 arm64 ndll）
- **songScore / 统计字段 Int64 化**：长谱不溢出
- **load_report.sh**：从日志统计进曲加载耗时

## 回放与容器

- **回放系统**：输入回放（回放模式不加载 Lua/HScript，保证确定性）
- **多版本容器**：同一次安装并行多个 mod 版本（`containersEnabled` 默认关闭，见 [CONTAINERS.md](CONTAINERS.md)）

## 界面体系

统一控件与主题令牌（[docs/UI-DESIGN.md](docs/UI-DESIGN.md) 是权威规范）：

- 开关一律 `objects.ToggleSwitch`（96×32 胶囊 + 滑块）
- 主题色走 `DesignTokens.*` 运行时令牌，禁止硬编码
- 脚本管理器等面板以 `ScriptManagerSubstate` 为几何基线

## 构建

```bash
# macOS（Intel Homebrew 工具链跑在 Rosetta 下）
METEORIC_BACKUP_MODS=0 METEORIC_BACKUP_CONTAINERS=0 ./compile-mac.sh typecheck  # 类型检查门禁
METEORIC_BACKUP_MODS=0 METEORIC_BACKUP_CONTAINERS=0 ./compile-mac.sh            # 完整构建
```

```bash
# Windows
./compile-windows.sh
```

```bash
# Android（宿主机按需选择 ANDROID_HOST）
./compile-android.sh
```

工具链：Haxe 4.2.5 · Lime 8.2.2 · OpenFL 9.2.1 · hxcpp 4.3.2。  
仓库自带双语 i18n 自检（`python3 tools/i18n/check_i18n.py`）与契约基线  
（[tools/contract/BASELINE.md](tools/contract/BASELINE.md)）。

## 文档导航

| 文档                                                                   | 内容                                            |
| -------------------------------------------------------------------- | --------------------------------------------- |
| [PROGRAMMING.md](PROGRAMMING.md)                                     | CNE 式 HScript 编程层：F5 热重载、StateRedirects、脚本库复用 |
| [LUA\_CLASS.md](LUA_CLASS.md)                                        | Lua 脚本 API 类参考                                |
| [CONTAINERS.md](CONTAINERS.md)                                       | 多版本容器：目录结构、开关与限制                              |
| [docs/UI-DESIGN.md](docs/UI-DESIGN.md)                               | 界面规范：控件、主题令牌、几何与文案                            |
| [CI.md](CI.md)                                                       | CI 构建说明                                       |
| [CHANGELOG.md](CHANGELOG.md) / [RELEASE\_NOTES.md](RELEASE_NOTES.md) | 版本历史                                          |
| [AGENTS.md](AGENTS.md)                                               | 贡献者与自动化代理的工程约束                                |

## 模组开发

把模组放进 `mods/`（或使用 [example\_mods/modTemplate.zip](example_mods/modTemplate.zip) 模板）：

```
mods/MyMod/
├── pack.json
├── data/          # 谱面、角色、周目配置
├── scripts/       # 全局 Lua / HScript
├── scripting/     # 编程层：states/（状态脚本）、lib/（脚本库）、redirects.txt（状态重定向）
└── images/ sounds/ music/ videos/ ...
```

脚本兼容：Psych 的 Lua API 原样可用；CNE 式 HScript 走 `hscript-meteoric`。

## 致谢

### 项目与库

- [Friday Night Funkin'](https://github.com/FunkinCrew/Funkin) 与  
  [Psych Engine](https://github.com/ShadowMario/FNF-Psych-Engine) 0.7.1h —— 本引擎的基座
- [HaxeFoundation/hscript](https://github.com/HaxeFoundation/hscript) 与  
  [hscript-meteoric](https://github.com/Bonus-XK/hscript-meteoric) —— 脚本解释器
- [Codename Engine](https://github.com/CodenameCrew/CodenameEngine) 与  
  [hscript-improved](https://github.com/CodenameCrew/hscript-improved) —— 壳类脚本设计来源
- [hscript-seiun](https://github.com/mohong2/hscript-seiun) —— 基准测试方法论、静态运算符表与  
  `Map.copy()` 优化来源
- [linc\_luajit](https://github.com/nebulazorua/linc_luajit) —— Lua 运行时

### 朋友与社区

- **[陌鸿](https://github.com/mohong2)** —— ME 的一生之敌，也为 ME 提供了许多优秀的想法
- **[ZeroSeven](https://space.bilibili.com/1951803423)** —— 提供 Lua 优化方案
- **[暮雪](https://space.bilibili.com/3493084289566971)** —— Neko Engine 开发者，贡献了许多想法并协助排查引擎 Bug
- **[Pico皮科](https://space.bilibili.com/3546752359598592)** —— 找出无数 Bug，助力引擎稳定性与质量
- **[小狼夜瑛](https://space.bilibili.com/3493115727972533)** —— 为 ME 提出众多想法
- **idk** 与 **GC** —— 为 ME 的性能优化提出众多想法，并应用到引擎中

## License

见 [LICENSE](LICENSE)。
