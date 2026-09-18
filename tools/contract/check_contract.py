#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""契约自检单一入口（只读）。

一条命令校验「脚本入口只增不减 + 路径/格式契约零变化」，输出 PASS/FAIL 与差异明细
（缺失 / 新增 / 位置变更 三分类）。本脚本**不写任何文件**。

用法：
    python3 tools/contract/check_contract.py             # 自检（退出码 0=PASS）
    python3 tools/contract/check_contract.py --selftest  # 对照用例（临时副本上做真实源码突变）
"""
import argparse
import filecmp
import os
import shutil
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE)) if os.path.basename(os.path.dirname(HERE)) == "tools" \
    else os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gen_script_surface as G1  # noqa: E402
import gen_path_format as G2     # noqa: E402

BASE_SCRIPT = os.path.join(HERE, "script-surface.tsv")
BASE_PATHS = os.path.join(HERE, "path-format-surface.tsv")
MAX_DETAIL = 12


def read_rows(path):
    if not os.path.isfile(path):
        return None
    return [l.rstrip("\r\n").split("\t") for l in open(path, encoding="utf-8")
            if l.strip() and not l.startswith("#")]


def diff_keys(base_rows, cur_rows, keyfn):
    def index(rows):
        d = {}
        for r in rows:
            d.setdefault(keyfn(r), []).append(r)
        return d
    b, c = index(base_rows), index(cur_rows)
    bk, ck = set(b), set(c)
    missing = sorted(bk - ck)
    added = sorted(ck - bk)
    moved = []
    for k in sorted(bk & ck):
        lb = sorted(x[2] if len(x) > 2 else "" for x in b[k])
        lc = sorted(x[2] if len(x) > 2 else "" for x in c[k])
        if lb != lc:
            moved.append(k)
    return missing, added, moved


def diff_rows(base_rows, cur_rows):
    """行级多重集比对：任何基线行（字符串+站点）在当前不存在 → 缺失。"""
    from collections import Counter
    cb = Counter(tuple(r) for r in base_rows)
    cc = Counter(tuple(r) for r in cur_rows)
    return sorted((cb - cc).elements()), sorted((cc - cb).elements())


def show(title, missing, added, moved, total_b, total_c):
    print("[%s] 基线 %d 条 / 当前 %d 条 → 缺失 %d  新增 %d  位置变更 %d"
          % (title, total_b, total_c, len(missing), len(added), len(moved)))
    for label, items in (("缺失(破坏兼容)", missing), ("新增(允许，需人工确认是否冻结)", added),
                         ("位置变更(仅声明位置移动)", moved)):
        for k in items[:MAX_DETAIL]:
            print("    %s: %s" % (label, " | ".join(str(x) for x in (k if isinstance(k, tuple) else (k,)))))
        if len(items) > MAX_DETAIL:
            print("    %s: … 另有 %d 条" % (label, len(items) - MAX_DETAIL))


def run_check(verbose=True):
    base_s = read_rows(BASE_SCRIPT)
    base_p = read_rows(BASE_PATHS)
    if base_s is None or base_p is None:
        print("FAIL: 基线文件缺失（先跑两个生成器）")
        return 1
    cur_s, stats_s = G1.collect()
    cur_p, stats_p, unclassified = G2.collect()

    ms, as_, mv = diff_keys(base_s, cur_s, lambda r: (r[0], r[1]))
    bp_c = [r for r in base_p if r[0] == "contract"]
    cp_c = [r for r in cur_p if r[0] == "contract"]
    bp_e = [r for r in base_p if r[0] == "exclude"]
    cp_e = [r for r in cur_p if r[0] == "exclude"]
    # 路径族：行级判定（“路径字符串零变化”）——只改 N 个站点中的 1 个也必须 FAIL
    pm, pa = diff_rows(bp_c, cp_c)
    em, ea = diff_rows(bp_e, cp_e)
    # 条目级仅作信息展示
    _, ap, mvp = diff_keys(bp_c, cp_c, lambda r: (r[1], r[2], r[3]))
    _, ae, mve = diff_keys(bp_e, cp_e, lambda r: (r[2], r[3]))

    if verbose:
        show("1/3 脚本兼容入口", ms, as_, mv, len(base_s), len(cur_s))
        print("[2/3 路径与格式契约] 基线 %d 行 / 当前 %d 行 → 行级缺失 %d  行级新增 %d ｜ 条目级新增 %d 条目级位置变更 %d"
              % (len(bp_c), len(cp_c), len(pm), len(pa), len(ap), len(mvp)))
        for r in pm[:MAX_DETAIL]:
            print("    缺失(路径/格式字符串变化或站点消失): %s" % " | ".join(r))
        for r in pa[:MAX_DETAIL]:
            print("    新增(须人工确认为新契约): %s" % " | ".join(r))
        print("[3/3 路径排除表] 基线 %d 行 / 当前 %d 行 → 行级缺失 %d  行级新增 %d"
              % (len(bp_e), len(cp_e), len(em), len(ea)))

    ok = True
    reasons = []
    if ms:
        ok = False; reasons.append("脚本入口缺失 %d 个（破坏 mod 兼容）" % len(ms))
    if pm:
        ok = False; reasons.append("路径/格式契约缺失 %d 行（路径字符串变化或站点消失，破坏 mod/存档/容器兼容）" % len(pm))
    if stats_p["unclassified"]:
        ok = False; reasons.append("路径候选存在未归类 %d 个" % stats_p["unclassified"])
        for raw, loc in unclassified[:MAX_DETAIL]:
            print("    未归类候选（必须显式归入 contract 或 exclude）: %s @ %s" % (raw, loc))
    if stats_p["missing"]:
        ok = False; reasons.append("§5 清单缺项: %s" % ", ".join(l for l, _ in stats_p["missing"]))
    print("RESULT: %s%s" % ("PASS" if ok else "FAIL",
                            "" if ok else "  ← " + "; ".join(reasons)))
    if as_ or ap or ae:
        print("提示: 有新增条目（只增不减是允许的），请人工确认是否要把它们视为新契约并刷新基线。")
    return 0 if ok else 1


def _run(path_sub, args=None):
    r = subprocess.run([sys.executable, os.path.join(path_sub, "tools", "contract", "check_contract.py")]
                       + (args or []), cwd=path_sub, capture_output=True, text=True)
    if not (r.stdout or "").strip():
        r.stdout = "RESULT: <空输出>  stderr=" + (r.stderr or "")[:200]
        r.returncode = 99  # 空输出一律视为用例失败
    return r


def _has(text, pattern):
    """计数断言用词边界匹配，避免 "缺失 1" 被 "缺失 12" 误满足。"""
    return re.search(pattern, text) is not None


def selftest():
    """在临时副本上做真实源码突变，验证三类判定与明细输出。"""
    tmp = tempfile.mkdtemp(prefix="ct-selftest-")
    try:
        shutil.copytree(os.path.join(ROOT, "source"), os.path.join(tmp, "source"))
        shutil.copytree(HERE, os.path.join(tmp, "tools", "contract"))
        # 用例 0（红队 #8）：未突变副本必须先 PASS —— 否则后续用例的"FAIL"可能来自别处
        r0 = _run(tmp)
        cases = [("未突变副本→PASS", r0.returncode == 0 and "RESULT: PASS" in r0.stdout,
                  next((l for l in r0.stdout.splitlines() if l.startswith("RESULT")), ""))]
        # ① 删 1 个名 → 期望 FAIL
        hsx = os.path.join(tmp, "source", "psychlua", "HScript.hx")
        s = open(hsx, encoding="utf-8").read()
        assert "set('" in s
        mut = s.replace("set('", "setDisabled('", 1)
        assert mut != s, "对照用例① 突变未生效"
        open(hsx, "w", encoding="utf-8").write(mut)
        r = _run(tmp)
        cases.append(("删1个名→FAIL", r.returncode == 1 and _has(r.stdout, r"脚本入口缺失 1 个(?![0-9])")
                      and _has(r.stdout, r"行级缺失 0(?![0-9])") and "RESULT: FAIL" in r.stdout,
                      next((l for l in r.stdout.splitlines() if l.startswith("RESULT")), "")))
        shutil.copy2(os.path.join(ROOT, "source", "psychlua", "HScript.hx"), hsx)
        # ② 增 1 个名 → 期望 PASS 且列出新增
        misc = os.path.join(tmp, "source", "psychlua", "functions", "MiscCommands.hx")
        with open(misc, "a", encoding="utf-8") as fh:
            fh.write('\n// selftest\nfunction _ctSelfTest(lua) { Lua_helper.add_callback(lua, "zzSelfTestApi999", null); }\n')
        r = _run(tmp)
        cases.append(("增1个名→PASS+列出新增", r.returncode == 0 and _has(r.stdout, r"新增 1(?![0-9])") and "RESULT: PASS" in r.stdout,
                      next((l for l in r.stdout.splitlines() if l.startswith("RESULT:") or l.startswith("提示")), "")))
        shutil.copy2(os.path.join(ROOT, "source", "psychlua", "functions", "MiscCommands.hx"), misc)
        # ③ 改 1 条路径串 → 期望 FAIL
        mods = os.path.join(tmp, "source", "backend", "Mods.hx")
        s = open(mods, encoding="utf-8").read()
        # 精确替换带引号的字面量（避免命中注释），且断言突变确实发生
        assert "'/modsList.txt'" in s, "对照用例③ 前置不符：找不到 '/modsList.txt' 字面量"
        mutated = s.replace("'/modsList.txt'", "'/mods_list.txt'", 1)
        assert mutated != s, "对照用例③ 突变未生效"
        open(mods, "w", encoding="utf-8").write(mutated)
        r = _run(tmp)
        cases.append(("改1条路径串(2站点中改1)→FAIL", r.returncode == 1 and _has(r.stdout, r"行级缺失 1(?![0-9])")
                      and _has(r.stdout, r"\[1/3[^\n]*缺失 0(?![0-9])") and "RESULT: FAIL" in r.stdout,
                      next((l for l in r.stdout.splitlines() if l.startswith("RESULT")), "")))
        shutil.copy2(os.path.join(ROOT, "source", "backend", "Mods.hx"), mods)
        # ④ 真改名（删+增）→ 期望两侧同时点亮：缺失 1 + 新增 1（红队 #3：原用例只覆盖"纯删除"）
        s2 = open(hsx, encoding="utf-8").read()
        assert "set('FlxG'" in s2, "对照用例④ 前置不符：找不到 set('FlxG'"
        mut2 = s2.replace("set('FlxG'", "set('FlxGProbe999'", 1)
        assert mut2 != s2, "对照用例④ 突变未生效"
        open(hsx, "w", encoding="utf-8").write(mut2)
        r = _run(tmp)
        cases.append(("真改名(删+增)→FAIL且两侧点亮", r.returncode == 1 and _has(r.stdout, r"缺失 1(?![0-9])") and _has(r.stdout, r"新增 1(?![0-9])"),
                      next((l for l in r.stdout.splitlines() if l.startswith("[1/3")), "")))
        shutil.copy2(os.path.join(ROOT, "source", "psychlua", "HScript.hx"), hsx)
        print("=== 对照用例 ===")
        allok = True
        for name, passed, last in cases:
            allok &= passed
            print("  %-28s %s   (%s)" % (name, "PASS" if passed else "FAIL", last[:70]))
        print("SELFTEST: %s" % ("PASS" if allok else "FAIL"))
        return 0 if allok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    return selftest() if args.selftest else run_check()


if __name__ == "__main__":
    sys.exit(main())
