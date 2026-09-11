# Meteoric Engine × Material Design 3 —— 设计系统 Skills 包

本目录是 Meteoric Engine（Psych Engine 0.7.1h 基座，v1.1.2+）的 **Agent Skills 规则库**，
结构对齐 [emilkowalski/skills](https://github.com/emilkowalski/skills)（每个 skill 一个目录，
内含带 `name` / `description` frontmatter 的 `SKILL.md`，可被兼容 `skills.sh` 的工具安装）。

设计基线（v1.1.2 现状）：

- **手绘域（保留 FNF 气质）**：主菜单、Story Mode、Freeplay、Gameplay。**不引入 MD3 组件**，
  只借用"即时反馈、清晰状态、触控友好"的交互原则。
- **系统域（MD3 化）**：Options、Pause、GameOver、Results、Mods 管理、联机、脚本/输入类子界面。
  使用 MD3 令牌 + 圆角面板 + 统一动效，延续现有"圆角磨砂玻璃面板 + 鼠标/触控/键盘三套操作"语言。
- **取色策略**：固定色板 + 设置内用户可选主题色；**不做**壁纸动态取色（Material You 桥接留待二期）。

## 安装 / 使用

```bash
# 仓库发布到 GitHub 后：
npx skills@latest add <owner>/FNF-MeteoricEngine

# 本地开发：直接把本目录交给 AI 代理，或按 skill name 引用：
meteoric-design   # 总纲：分域原则 + MD3 令牌 + 动效框架 + 审阅格式
meteoric-menu     # 主菜单 / Story / Freeplay（手绘域）
meteoric-system   # Options / Pause / GameOver / Results / Mods（系统域）
meteoric-mobile   # Android 触控 / 性能 / 系统界面适配
```

## 索引

| Skill | 作用域 | 关键源文件（供代理定位） |
| --- | --- | --- |
| `meteoric-design` | 全部 UI | `source/options/BaseOptionsMenu.hx`、`source/objects/MenuText.hx` |
| `meteoric-menu` | 手绘域 | `source/states/MainMenuState.hx`、`StoryMenuState.hx`、`FreeplayState.hx` |
| `meteoric-system` | 系统域 | `source/options/*`、`source/substates/PauseSubState.hx`、`ResultsSubState.hx`、`GameOverSubstate.hx`、`source/states/ModsMenuState.hx` |
| `meteoric-mobile` | Android | `source/objects/MobileControls.hx`、`source/objects/MobileControlsSubState.hx` |

## 维护约定

1. **改任何界面代码 → 同步更新对应 SKILL.md**；规则与实现脱节的 skill 会被标记失效。
2. 评审界面改动时，**必须**使用 `meteoric-design` 的 Before / After 表格格式。
3. 新增界面先判定归属域（手绘域 / 系统域），再按其规范实现，禁止跨域混用。
