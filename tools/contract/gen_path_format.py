#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""契约基线生成器 —— mods / 存档 / 容器的路径与格式字符串。

只读源码、只写自己的产物，不触碰任何引擎行为。
每个被发现的候选 token 必须被显式归类（契约 / 排除），否则判 FAIL —— 这是"无遗漏"的机械保证。

用法：
    python3 tools/contract/gen_path_format.py           # 生成/刷新
    python3 tools/contract/gen_path_format.py --check   # 只比对，退出码 0=一致

产物：tools/contract/path-format-surface.tsv + tools/contract/PATHS-BASELINE.md
"""
import argparse
import difflib
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "source")
OUT_TSV = os.path.join(ROOT, "tools", "contract", "path-format-surface.tsv")
OUT_MD = os.path.join(ROOT, "tools", "contract", "PATHS-BASELINE.md")
EXTS = ("json", "txt", "zip", "cnz", "log", "dat")
KNOWN_BARE = ("meoptions", "mods", "_containers", "_cnestage")
RE_QUOTED = re.compile(r"""['"](/?[A-Za-z0-9_./\-]{1,60})['"]""")
RE_EXT_ONLY = re.compile(r"^\.(?:%s)$" % "|".join(EXTS))

# 契约面：base 名 -> (kind, 用途)
INCLUDE = {
    "meoptions": ("save", "Android 权威设置文件：无扩展名 + JSON（写 ClientPrefs.hx:352 / 读 :585）"),
    "meteoric_dpi_mode.txt": ("format", "高清渲染档位落盘：单字符 '1'/'0'（ClientPrefs.hx:748-749）"),
    "mods": ("path", "mod 根目录名（AndroidStorage.hx:123 / ModInstaller.hx:445,652 / ContainerStore.hx:96）"),
    "modsList.txt": ("save", "mod 清单：Android 落 AndroidStorage.root()+'/modsList.txt'，桌面落 'modsList.txt'（Mods.hx:184-186）"),
    "pack.json": ("format", "mod 包描述（Mods.hx:161 / ModZipPlanner.hx:19）"),
    "weekList.txt": ("save", "周目清单（WeekData.hx:100、:128）"),
    "_containers": ("path", "容器根目录保留名，不得被扫成假 mod（ContainerStore.hx:24,25,30 / Mods.hx:38）"),
    "_cnestage": ("path", "CNE 暂存目录保留名，不得被扫成假 mod（CneZipStore.hx:29 / Mods.hx:42）"),
    "container.json": ("format", "容器清单文件名（ContainerManifestParser.hx:17）"),
    "cmd.txt": ("format", "容器命令通道（ContainerStore.hx:42）"),
    "phase.txt": ("format", "容器会话相位（ContainerStore.hx:43）"),
    "exit.txt": ("format", "容器退出码（ContainerStore.hx:34）"),
    "container.log": ("format", "容器运行日志（ContainerStore.hx:32）"),
    ".zip": ("format", "mod 打包扩展名（ModInstaller.hx:243 / CneZipStore.hx:32）"),
    ".cnz": ("format", "CNE mod 打包扩展名（CneZipStore.hx:32）"),
    "Offsets.txt": ("save", "角色偏移存档（CharacterEditorState.hx:1292）"),
    "dialogue.json": ("format", "对话数据（DialogueEditorState.hx:533）"),
    "events.json": ("format", "事件数据（ChartingState.hx:2997）"),
}
# 显式排除：base/pattern -> 理由
EXCLUDE = {
    "library.json": "图集运行时元数据，由资源管线消费；mod 自带该文件时已由 mods 契约覆盖",
    ".luagraph.json": "LuaGraph 工具自有保存格式（非 mod/存档/容器契约）",
    "readme.txt": "编辑器导出说明文件的过滤项（ChartingState.hx:934）",
    "last_stage.txt": "崩溃诊断落盘（CrashHandler）",
    "heartbeat.txt": "心跳诊断落盘（CrashHandler:961）",
    "dev_diag.txt": "开发诊断落盘（CrashHandler:894）",
    "profile.txt": "性能探针输出（MeteoricProfile:75）",
    "data/credits.txt": "引擎内置内容清单", "/data/credits.txt": "引擎内置内容清单",
    "data/characterList.txt": "编辑器素材清单", "data/stageList.txt": "编辑器素材清单",
    "data/introText.txt": "引擎内置文案", "data/freeplaySonglist.txt": "引擎内置曲单",
    "data/config/freeplaySonglist.txt": "引擎内置曲单",
    "images/noteSkins/list.txt": "皮肤素材清单", "images/noteSplashes/list.txt": "溅射素材清单",
    "weeks/weekList.txt": "内置周目素材清单",
    "/data/weeks/weeks.txt": "内置周目素材清单",
    "/Animation.json": "角色图集元数据路径", "/meta.json": "CNE 图集元数据路径",
    "/spritemap1.json": "角色图集元数据路径",
    "Animation.json": "角色图集元数据路径", "spritemap.json": "图集元数据路径",
    "assets/TEST/Animation.json": "示例资源路径", "assets/TEST/spritemap.json": "示例资源路径",
    "images/gfDanceTitle.json": "标题画面素材路径", "/library.json": "图集运行时元数据",
}
# 审计报告 §5 清单（正向覆盖检查）
CHECKLIST = [
    ("mods/<文件夹>", "mods"),
    ("mods/<名>.zip", ".zip"),
    ("mods/<名>.cnz（CNE 布局）", ".cnz"),
    ("保留目录 _containers", "_containers"),
    ("保留目录 _cnestage", "_cnestage"),
    ("存档 /meoptions（无扩展名+JSON）", "meoptions"),
    ("highDPIRender 单字符落盘", "meteoric_dpi_mode.txt"),
    ("容器 container.json", "container.json"),
    ("容器 cmd.txt", "cmd.txt"),
    ("容器 phase.txt", "phase.txt"),
    ("容器 exit.txt", "exit.txt"),
    ("pack.json", "pack.json"),
    ("modsList.txt", "modsList.txt"),
    ("weekList.txt", "weekList.txt"),
    ("Offsets.txt", "Offsets.txt"),
    ("dialogue.json", "dialogue.json"),
    ("events.json", "events.json"),
]


def candidates():
    """返回 [(raw_token, base, 'file:line')]。"""
    out = []
    for dp, _dn, fns in os.walk(SRC):
        for fn in sorted(fns):
            if not fn.endswith(".hx"):
                continue
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, ROOT)
            with open(p, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    for m in RE_QUOTED.finditer(line):
                        raw = m.group(1)
                        base = raw.rstrip("/").split("/")[-1]
                        keep = (base in KNOWN_BARE or base in INCLUDE or base in EXCLUDE
                                or raw in EXCLUDE or RE_EXT_ONLY.match(raw) is not None
                                or base.endswith(tuple("." + e for e in EXTS)))
                        if keep:
                            out.append((raw, base, "%s:%d" % (rel, i)))
    return out


def structural_rows():
    """§5「容器」行的非 token 部分：模块群 + 菜单 + Main 每帧钩子（结构化核验，不靠字符串）。"""
    out = []
    backend = os.path.join(SRC, "backend")
    for fn in sorted(os.listdir(backend)):
        if (fn.startswith("Container") or fn == "Phase.hx") and fn.endswith(".hx"):
            rel = "source/backend/" + fn
            out.append(("contract", "module", fn[:-3], fn[:-3], rel + ":1",
                        "容器模块（§5 容器行）"))
    menu = "source/states/ContainersMenuState.hx"
    if os.path.isfile(os.path.join(ROOT, menu)):
        out.append(("contract", "module", "ContainersMenuState", "ContainersMenuState",
                    menu + ":1", "容器菜单入口（§5 容器行）"))
    mainf = os.path.join(SRC, "Main.hx")
    with open(mainf, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            if "onContainerFrame" in line or "ContainerSession" in line:
                out.append(("contract", "hook", "Main.hx", "Container",
                            "source/Main.hx:%d" % i,
                            "容器每帧钩子/会话驱动（§5 容器行）"))
    return out


def classify(raw, base):
    if raw in INCLUDE:
        return "contract", INCLUDE[raw]
    if base in INCLUDE:
        return "contract", INCLUDE[base]
    if RE_EXT_ONLY.match(raw):
        return "exclude", ("文件名拼接片段（非完整契约 token）",)
    if raw in EXCLUDE:
        return "exclude", (EXCLUDE[raw],)
    if base in EXCLUDE:
        return "exclude", (EXCLUDE[base],)
    return "unclassified", ("?",)


def collect():
    rows, unclassified = [], []
    for raw, base, loc in candidates():
        verdict, meta = classify(raw, base)
        if verdict == "unclassified":
            unclassified.append((raw, loc))
            continue
        if verdict == "contract":
            kind, purpose = meta
            rows.append(("contract", kind, base, raw, loc, purpose))
        else:
            rows.append(("exclude", "excluded", base, raw, loc, meta[0]))
    rows.extend(structural_rows())
    rows.sort(key=lambda r: (r[0], r[2], r[4]))
    covered = {b for r in rows if r[0] == "contract" for b in [r[2]]}
    missing = [(label, tok) for label, tok in CHECKLIST if tok not in covered]
    stats = dict(total=len(rows), contract=sum(1 for r in rows if r[0] == "contract"),
                 excluded=sum(1 for r in rows if r[0] == "exclude"),
                 unclassified=len(unclassified), missing=missing, covered=len(CHECKLIST) - len(missing),
                 structural=sum(1 for r in rows if r[1] in ("module", "hook")))
    return rows, stats, unclassified


def render(rows, stats):
    out = [
        "# Meteoric Engine mods/存档/容器 路径与格式基线 —— 自动生成，请勿手改",
        "# generator: tools/contract/gen_path_format.py",
        "# schema: 1",
        "# columns: verdict<TAB>kind<TAB>base<TAB>raw_token<TAB>source_location<TAB>purpose_or_reason",
        "# counts: rows=%d contract=%d excluded=%d structural=%d unclassified=%d checklist_covered=%d/%d"
        % (stats["total"], stats["contract"], stats["excluded"], stats["structural"],
           stats["unclassified"], stats["covered"], len(CHECKLIST)),
        "# checklist_missing: %s" % (", ".join(l for l, _ in stats["missing"]) or "(none)"),
        "# 口径: 扫描 source/**/*.hx 中带引号的候选 token（含扩展名/json|txt|zip|cnz|log|dat、"
        "保留目录名、以及 /meoptions 这类无扩展名文件）；每个候选必须归入 contract 或 exclude，"
        "出现 unclassified 即判 FAIL。",
        "# 不变量：contract 行的 base 名与所属路径/格式语义只增不减；删除或改名 = 破坏 mod/存档/容器兼容。",
    ]
    for r in rows:
        out.append("\t".join(r))
    return "\n".join(out) + "\n"


def git_commit():
    try:
        return subprocess.check_output(["git", "-C", ROOT, "rev-parse", "HEAD"],
                                       stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return "(unknown)"


def render_md(rows, stats, commit, unclassified):
    contract = [r for r in rows if r[0] == "contract"]
    excl = [r for r in rows if r[0] == "exclude"]
    lines = ["# 路径与格式基线（mods / 存档 / 容器）", "",
             "本文件与 `path-format-surface.tsv` 一起构成**兼容契约的第二份门禁数据**。", "",
             "| 项 | 值 |", "|---|---|",
             "| 生成脚本 | `tools/contract/gen_path_format.py` |",
             "| 生成时 commit | `%s` |" % commit,
             "| 契约行数 | %d |" % len(contract),
             "| 排除行数 | %d |" % len(excl),
             "| 未归类 | %d |" % stats["unclassified"],
             "| §5 清单覆盖 | %d/%d |" % (stats["covered"], len(CHECKLIST)), "",
             "## 一、契约面（必须冻结）", "",
             "| kind | 名称 | 用途 | 站点数 |", "|---|---|---|---|"]
    seen = {}
    for r in contract:
        seen.setdefault((r[1], r[2], r[5]), []).append(r[4])
    for (kind, base, purpose), locs in sorted(seen.items()):
        lines.append("| %s | `%s` | %s | %d |" % (kind, base, purpose, len(locs)))
    lines += ["", "## 二、显式排除（附理由，防止静默遗漏）", "",
              "| 名称 | 理由 | 站点数 |", "|---|---|---|"]
    seen2 = {}
    for r in excl:
        seen2.setdefault((r[2], r[5]), []).append(r[4])
    for (base, reason), locs in sorted(seen2.items()):
        lines.append("| `%s` | %s | %d |" % (base, reason, len(locs)))
    lines += ["", "## 三、一条命令校验", "",
              "```bash", "python3 tools/contract/gen_path_format.py --check", "```", "",
              "## 四、已知边界", "",
              "1. 归类为**人工决策**：每个新出现的候选 token 必须在此文件登记（contract 或 exclude），否则 `--check` 判 FAIL。",
              "2. 本基线冻结的是**路径字符串与格式约定**，不含 Lua/HScript 入口名（见 `script-surface.tsv`）。",
              "3. `生成时 commit` = 生成时的 HEAD（基线自身入库前的父提交），属设计使然。"]
    if unclassified:
        lines += ["", "## 五、未归类（必须清零）", ""]
        for raw, loc in unclassified[:20]:
            lines.append("- `%s` @ %s" % (raw, loc))
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    rows, stats, unclassified = collect()
    text = render(rows, stats)
    if args.check:
        if not os.path.isfile(OUT_TSV):
            print("FAIL: 快照不存在")
            return 1
        cur = open(OUT_TSV, encoding="utf-8").read()
        ok = (cur == text) and stats["unclassified"] == 0 and not stats["missing"]
        if ok:
            print("PASS: 快照一致 / 无未归类 / §5 覆盖 %d/%d（contract=%d exclude=%d）"
                  % (stats["covered"], len(CHECKLIST), stats["contract"], stats["excluded"]))
            return 0
        if cur != text:
            diff = list(difflib.unified_diff(cur.splitlines(), text.splitlines(),
                                             "baseline", "current", lineterm=""))
            print("FAIL: 快照不一致（%d 行差异）" % len(diff))
            for line in diff[:20]:
                print("  " + line)
        if stats["unclassified"]:
            print("FAIL: 存在未归类 token %d 个（前 10）：%s"
                  % (stats["unclassified"], ", ".join(r for r, _ in unclassified[:10])))
        if stats["missing"]:
            print("FAIL: §5 清单缺项：%s" % ", ".join(l for l, _ in stats["missing"]))
        return 1
    with open(OUT_TSV, "w", encoding="utf-8") as fh:
        fh.write(text)
    with open(OUT_MD, "w", encoding="utf-8") as fh:
        fh.write(render_md(rows, stats, git_commit(), unclassified))
    print("已生成: tools/contract/path-format-surface.tsv")
    print("已生成: tools/contract/PATHS-BASELINE.md")
    print("统计: rows=%d contract=%d excluded=%d unclassified=%d §5=%d/%d"
          % (stats["total"], stats["contract"], stats["excluded"], stats["unclassified"],
             stats["covered"], len(CHECKLIST)))
    if stats["missing"]:
        print("⚠ §5 缺项:", ", ".join(l for l, _ in stats["missing"]))
    if unclassified:
        print("⚠ 未归类:", ", ".join("%s@%s" % (r, l) for r, l in unclassified[:10]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
