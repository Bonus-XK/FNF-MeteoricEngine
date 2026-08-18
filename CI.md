# GitHub Actions 构建工作流

仓库根目录下的 `.github/workflows/build.yml` 提供完整的全端自动构建。

## 触发方式

- `push` / `pull_request` 到 `master` / `main` 分支
- 手动触发：GitHub 仓库 → Actions → **构建（Build）** → Run workflow

## 构建内容

| Job | 产物 | 上传 Artifact 名 |
|-----|------|-----------------|
| Android | `Meteoric-debug.apk`（arm64） | `meteoric-android-arm64` |
| Windows | x64 + x86 完整 bin 目录（含依赖 DLL） | `meteoric-windows-x64` / `meteoric-windows-x86` |
| macOS | x86_64 + arm64 两个 `Meteoric.app` | `meteoric-macos-x64` / `meteoric-macos-arm64` |

## 工作原理

引擎使用 **SDL3 移植版 lime**（lime 8.2.2 + SDL3 3.2.8 + 各库定制版本）。由于 lime 完整源码（含 SDL3）太大无法入库，CI 在构建前现场组装：

1. **`ci/install-deps.sh`** — 安装 haxelib 依赖（openfl 9.5.2 / flixel 6.2.0 / hxcpp 4.3.2 等，版本与本地开发环境对齐）
2. **`ci/setup-lime-sdl3.sh`** — 组装 SDL3 lime：
   - `git clone` lime `8.2.2`（含 submodule 库）
   - 应用 `ci/lime-sdl3-patch/` 中的 SDL3 定制文件（backend/sdl 后端、Build.xml、各 files.xml、SDL_build_config.h、GameActivity.java 等）
   - 拉取并替换 SDL3 `release-3.2.8` 源码
   - 对齐定制库版本（pixman 0.46.4 / cairo 1.18.2 / harfbuzz 8.2.0 / openal-soft 1.20.1 / curl 7.88.1 / efsw 1.6.3）
   - `haxelib dev lime` 指向组装结果

## 目录说明

```
.github/workflows/build.yml   # 主工作流（Android/Windows/macOS 三个并行 job）
ci/
├── install-deps.sh           # haxelib 依赖安装
├── setup-lime-sdl3.sh        # SDL3 lime 现场组装
└── lime-sdl3-patch/          # SDL3 移植定制文件（34 个，含全部 files.xml/后端/Build.xml 等）
```

> 注意：`ci/lime-sdl3-patch` 是 SDL3 移植的核心定制，**引擎源码的 lime 相关改动必须同步回这里**，否则 CI 产物与本地不一致。

## 常见问题

- **CI 构建失败在 haxelib install**：确认依赖版本在 haxelib 上存在（`haxelib install <name> <version>` 可查）
- **macOS job 的 Xcode 版本**：runner 自带 Xcode（15/16），SDL3 3.2.8 与引擎均兼容；若遇到 SDK 相关报错，可改用 `macos-15` 或 `macos-14`
- **本地预览工作流**：可用 [act](https://github.com/nektos/act) 模拟 GitHub Actions 环境
