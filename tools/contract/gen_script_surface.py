#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""契约基线生成器 —— 脚本兼容入口（Lua 回调名 / HScript preset 名）。

本脚本只读源码、只写自己的产物，不触碰任何引擎行为。

用法（在仓库根目录执行）：
    python3 tools/contract/gen_script_surface.py           # 生成/刷新基线
    python3 tools/contract/gen_script_surface.py --check   # 只比对不写，退出码 0=完全一致

产物：
    tools/contract/script-surface.tsv   确定性快照（可重复生成，逐字节一致）
    tools/contract/BASELINE.md          基线元信息（生成时 commit + 统计数值）
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "source")
LUA_ROOT = os.path.join(SRC, "psychlua")
HSX_FILE = os.path.join(SRC, "psychlua", "HScript.hx")
OUT_TSV = os.path.join(ROOT, "tools", "contract", "script-surface.tsv")
OUT_MD = os.path.join(ROOT, "tools", "contract", "BASELINE.md")

RE_LUA = re.compile(r"""Lua_helper\s*\.\s*add_callback\s*\(\s*[^,]+,\s*[\"']([A-Za-z0-9_]+)[\"']""")
RE_LUA_ANY = re.compile(r'Lua_helper\s*\.\s*add_callback\s*\(')
RE_HSX = re.compile(r"set\('([A-Za-z0-9_]+)'")


def scan_lua():
    """返回 (rows, dynamic_count)；rows = [(kind, name, 'file:line')]。"""
    rows, dynamic, dyn_sites = [], 0, []
    for dirpath, _dirnames, filenames in os.walk(LUA_ROOT):
        for fn in sorted(filenames):
            if not fn.endswith(".hx"):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT)
            with open(path, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    m = RE_LUA.search(line)
                    if m:
                        rows.append(("lua", m.group(1), "%s:%d" % (rel, i)))
                    elif RE_LUA_ANY.search(line):
                        dynamic += 1  # 名字不是字符串字面量（运行期动态注册）
                        dyn_sites.append("%s:%d" % (rel, i))
    return rows, dynamic, dyn_sites


def scan_hscript():
    rows = []
    rel = os.path.relpath(HSX_FILE, ROOT)
    with open(HSX_FILE, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            for m in RE_HSX.finditer(line):
                rows.append(("hscript", m.group(1), "%s:%d" % (rel, i)))
    return rows


def collect():
    lua, dynamic, dyn_sites = scan_lua()
    hsx = scan_hscript()
    rows = sorted(lua + hsx, key=lambda r: (r[0], r[1], r[2]))
    stats = {
        "lua_unique": len({n for k, n, _ in rows if k == "lua"}),
        "hscript_unique": len({n for k, n, _ in rows if k == "hscript"}),
        "total_unique": len({n for _, n, _ in rows}),
        "registrations": len(rows),
        "dynamic_or_unparsed": dynamic,
        "dynamic_sites": dyn_sites,
        "pairs_unique": len({(k, n) for k, n, _ in rows}),
        "multi_site": sorted({(k, n) for k, n, _ in rows if sum(1 for kk, nn, _ in rows if (kk, nn) == (k, n)) > 1}),
    }
    return rows, stats


def render(rows, stats):
    out = [
        "# Meteoric Engine 脚本兼容入口基线 —— 自动生成，请勿手改",
        "# generator: tools/contract/gen_script_surface.py",
        "# schema: 1",
        "# columns: kind<TAB>name<TAB>source_location",
        "# counts: lua_unique=%d hscript_unique=%d pairs_unique=%d bare_name_unique=%d registrations=%d dynamic_sites=%d"
        % (stats["lua_unique"], stats["hscript_unique"], stats["pairs_unique"], stats["total_unique"],
           stats["registrations"], stats["dynamic_or_unparsed"]),
        "# 口径: pairs_unique = 唯一 (kind,name) 对数（= 契约条目数）；bare_name_unique = 跨命名空间去重后的裸名数（Lua 与 HScript 有 26 个同名，属两份独立契约）",
        "# dynamic_sites: %s" % (", ".join(stats["dynamic_sites"]) or "(none)"),
        "# 动态点口径: 名字非字面量（运行期由脚本经 FunkinLua.customFunctions / MenuScript.addLocalCallback 注册），基线只冻结内建字面量面。",
        "# multi_site: %s" % (", ".join("%s.%s" % (k, n) for k, n in stats["multi_site"]) or "(none)"),
        "# kind=lua    : source/psychlua/** 下 Lua_helper.add_callback 的字符串字面量",
        "# kind=hscript: source/psychlua/HScript.hx 的 set('…') 预设变量",
        "# 不变量：本文件中的名字只增不减；删除或改名 = 破坏 mod 兼容，必须人工评审。",
    ]
    for kind, name, loc in rows:
        out.append("%s\t%s\t%s" % (kind, name, loc))
    return "\n".join(out) + "\n"


def git_commit():
    try:
        return subprocess.check_output(["git", "-C", ROOT, "rev-parse", "HEAD"],
                                       stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return "(unknown)"


def render_md(stats, commit):
    return """# 脚本兼容入口基线（契约冻结基准）

本目录是**所有重构增量的门禁数据**：任何改动都必须让本基线「只增不减」。

| 项 | 值 |
|---|---|
| 生成脚本 | `tools/contract/gen_script_surface.py` |
| 快照文件 | `tools/contract/script-surface.tsv`（确定性，可重复生成） |
| 生成时 commit | `%s` |
| Lua 唯一名 | %d |
| HScript 唯一名 | %d |
| 契约条目数（唯一 kind+name 对） | %d |
| 裸名去重后 | %d |
| 注册点总数 | %d |
| 非字面量注册（待人工确认） | %d |

## 一条命令校验

```bash
python3 tools/contract/gen_script_surface.py --check   # 退出码 0 = 与快照完全一致
```

## 不变量

1. `script-surface.tsv` 里的名字**只增不减**；任何删除/改名都视为破坏 mod 兼容，需人工评审并显式更新本基线。
2. 快照为确定性输出（无时间戳、无环境相关字段），因此「重新生成后 diff 为空」是硬性要求。
3. 本基线**不含** mods/存档/容器的路径与格式字符串 —— 那由另一份基线（`路径与格式基线快照` 小类）负责。
""" % (commit, stats["lua_unique"], stats["hscript_unique"], stats["pairs_unique"], stats["total_unique"],
       stats["registrations"], stats["dynamic_or_unparsed"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只比对不写；退出码 0=一致")
    args = ap.parse_args()

    rows, stats = collect()
    text = render(rows, stats)

    if args.check:
        if not os.path.isfile(OUT_TSV):
            print("FAIL: 快照不存在: %s" % OUT_TSV)
            return 1
        cur = open(OUT_TSV, encoding="utf-8").read()
        if cur == text:
            print("PASS: 快照与当前源码一致（lua=%d hscript=%d total=%d registrations=%d）"
                  % (stats["lua_unique"], stats["hscript_unique"], stats["total_unique"], stats["registrations"]))
            return 0
        import difflib
        diff = list(difflib.unified_diff(cur.splitlines(), text.splitlines(),
                                         "baseline", "current", lineterm=""))
        print("FAIL: 快照与当前源码不一致（%d 行差异，前 20 行）" % len(diff))
        for line in diff[:20]:
            print("  " + line)
        return 1

    with open(OUT_TSV, "w", encoding="utf-8") as fh:
        fh.write(text)
    with open(OUT_MD, "w", encoding="utf-8") as fh:
        fh.write(render_md(stats, git_commit()))
    print("已生成: %s" % os.path.relpath(OUT_TSV, ROOT))
    print("已生成: %s" % os.path.relpath(OUT_MD, ROOT))
    print("统计: lua_unique=%d hscript_unique=%d total_unique=%d registrations=%d dynamic_or_unparsed=%d"
          % (stats["lua_unique"], stats["hscript_unique"], stats["total_unique"],
             stats["registrations"], stats["dynamic_or_unparsed"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
