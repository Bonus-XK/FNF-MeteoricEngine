#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""多语言（i18n）自检单一入口（只读）。

一条命令校验语言包的完整性与接线正确性，输出 PASS/FAIL 与明细。本脚本**不写任何文件**
（--update-baseline 例外，见下）。

检查项（任一 FAIL 即退出码 1）：
  1  语言包完整性   zh/en key 集合一致、无空值、值均为字符串
  2  字面量 key     源码里所有 Lang.t/tOr/tr/trOr('k') 的 k 都在语言包里
  3  派生 key       new Option(...) 派生的 option/optionDesc/optionValue/optionValueHint
                    luagraph 积木表派生的 lg.cat/lg.block/lg.blockDesc/lg.param
                    DesignTokens 主题名派生的 theme.*
                    Achievements 派生的 achievement.*
  4  Lang.t 安全性  Lang.t 的 key 必须存在（缺 key 时 Lang.t 返回 key 本身，
                    界面会直接显示 "xxx.yyy"）
  5  静态缓存       static 字段初始化里调用 Lang.t* —— 这类译文只求值一次，
                    运行时切换语言后不刷新。必须为 0。
  6  括号对称       拆成前后缀两个 key 时若只拆了一半，英文界面会出现 "(exit 1）"
  7  CJK 覆盖率     相对 intentional-skip.tsv 基线，新增未本地化项即 FAIL

用法：
    python3 tools/i18n/check_i18n.py                # 自检（退出码 0=PASS）
    python3 tools/i18n/check_i18n.py -v             # 附带明细
    python3 tools/i18n/check_i18n.py --update-baseline   # 认可当前剩余项并写回基线
"""
import argparse
import collections
import json
import os
import re
import sys

sys.dont_write_bytecode = True  # 不在仓库内落 __pycache__（曾被误入库，见 .gitignore）

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))   # tools/i18n -> 仓库根
sys.path.insert(0, HERE)
import hxscan  # noqa: E402

SRC = os.path.join(ROOT, "source")
PACKS = (os.path.join(ROOT, "assets/languages/zh.json"),
         os.path.join(ROOT, "assets/languages/en.json"))
BASELINE = os.path.join(HERE, "intentional-skip.tsv")
MAX_DETAIL = 12

# 派生 key 的前缀（这些 key 由运行时拼接，静态扫 Lang.tOr(' 抓不到）
DERIVED_PREFIX = ("option.", "optionDesc.", "optionValue", "optionValueHint.",
                  "lg.cat.", "lg.block.", "lg.blockDesc.", "lg.param.",
                  "theme.", "achievement.")


def hx_files():
    for r, _, fs in os.walk(SRC):
        for f in sorted(fs):
            if f.endswith(".hx"):
                yield os.path.join(r, f)


def read_pack(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    return d


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


# ---------------------------------------------------------------- 1 语言包
def check_packs(z, e):
    bad = []
    zk = set(z) - {"_meta"}
    ek = set(e) - {"_meta"}
    if zk != ek:
        bad.append(("zh 独有", sorted(zk - ek)))
        bad.append(("en 独有", sorted(ek - zk)))
    for name, d in (("zh", z), ("en", e)):
        empty = sorted(k for k, v in d.items() if k != "_meta"
                       and (not isinstance(v, str) or not v.strip()))
        if empty:
            # Lang.tOr 只判 None 不判空串，空值会让界面显示空白
            bad.append((f"{name} 空值（tOr 不判空串，会显示空白）", empty))
        # 转义过度：值里出现**字面**反斜杠+n（JSON 写成 "\\\\n"）而不是换行。
        # 症状 = 界面上直接显示 "\n" 两个字符，多行提示挤成一行（ModsMenuState 的
        # 「没有安装任何 Mod」就是这样查出来的）。判据：字符串里有 '\' + 'n' 两字符。
        # 对照组：Haxe 侧的 tOr 兜底原文一律写真换行（'\n\n崩溃日志…'），故语言包同义。
        lit_nl = sorted(k for k, v in d.items() if k != "_meta"
                        and isinstance(v, str) and "\\n" in v)
        if lit_nl:
            bad.append((f"{name} 转义过度：值里是字面 \\n 而非换行（JSON 少写一个反斜杠）", lit_nl))
    return zk, ek, bad


# ------------------------------------------------------- 2/4 字面量 key
LITERAL = re.compile(r"\b(?:Lang\.)?(?:t|tOr|tr|trOr)\s*\(\s*'([^']+)'")
PLAIN_T = re.compile(r"\b(?:Lang\.)?t\s*\(\s*'([^']+)'")


def check_literal_keys(zk, ek):
    missing, missing_t = set(), set()
    for p in hx_files():
        src = hxscan.strip_comments(open(p, encoding="utf-8", errors="ignore").read())
        for m in LITERAL.finditer(src):
            k = m.group(1)
            if k.endswith("."):
                continue          # 形如 'lg.block.' + id，运行时才成型
            if k not in zk or k not in ek:
                missing.add((rel(p), src[:m.start()].count("\n") + 1, k))
        for m in PLAIN_T.finditer(src):
            k = m.group(1)
            if k.endswith("."):
                continue
            if k not in zk or k not in ek:
                missing_t.add((rel(p), src[:m.start()].count("\n") + 1, k))
    return sorted(missing), sorted(missing_t)


# ------------------------------------------------------------- 3 派生 key
def check_option_keys(zk):
    """new Option(name, description, variable, type, options)"""
    need = {"option": set(), "optionDesc": set(), "optionValue": set()}
    for p in hx_files():
        if not os.sep + "options" + os.sep in p:
            continue
        src = open(p, encoding="utf-8").read()
        for m in re.finditer(r"new Option\s*\(", src):
            i = src.index("(", m.start())
            depth, j, q = 0, i, None
            while j < len(src):
                c = src[j]
                if q:
                    if c == "\\":
                        j += 2
                        continue
                    if c == q:
                        q = None
                    j += 1
                    continue
                if c in "\"'":
                    q = c
                elif c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            a = hxscan.split_args(hxscan.strip_comments(src[i + 1:j]))
            if len(a) <= 2:
                continue
            var = hxscan.unescape(a[2])
            if not var or not re.fullmatch(r"[A-Za-z_]\w*", var):
                continue
            need["option"].add(var)
            need["optionDesc"].add(var)
            if len(a) > 4:
                t = a[4].strip()
                if t.startswith("[") and t.endswith("]"):
                    n = len(hxscan.split_args(t[1:-1])) if t != "[]" else 0
                    for k in range(n):
                        need["optionValue"].add(f"{var}.{k}")
    miss = []
    for kind, keys in need.items():
        for k in sorted(keys):
            if f"{kind}.{k}" not in zk:
                miss.append(f"{kind}.{k}")
    return miss, sum(len(v) for v in need.values())


def check_luagraph_keys(zk):
    """LuaBlockDefs 积木表：label / desc / 参数标签，key 由积木 id 派生。"""
    path = os.path.join(SRC, "luagraph/LuaBlockDefs.hx")
    if not os.path.isfile(path):
        return [], 0
    src = open(path, encoding="utf-8").read()
    need = set()
    for m in re.finditer(r"\[(CAT_[A-Z]+),\s*('[^']*')\]", src):
        need.add("lg.cat." + m.group(1)[4:].lower())
    for m in re.finditer(r"\bnew BlockDef\s*\(", src):
        i = src.index("(", m.start())
        depth, j, q = 0, i, None
        while j < len(src):
            c = src[j]
            if q:
                if c == "\\":
                    j += 2
                    continue
                if c == q:
                    q = None
                j += 1
                continue
            if c in "\"'":
                q = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        a = hxscan.split_args(hxscan.strip_comments(src[i + 1:j]))
        bid = hxscan.unescape(a[0]) if a else None
        if not bid:
            continue
        need.add("lg.block." + bid)
        if len(a) >= 9 and hxscan.unescape(a[-1]):
            need.add("lg.blockDesc." + bid)
        for pm in re.finditer(r"new PDef\s*\(", a[4] if len(a) > 4 else ""):
            arr = a[4]
            k = arr.index("(", pm.start())
            depth, j = 0, k
            while j < len(arr):
                if arr[j] == "(":
                    depth += 1
                elif arr[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            pa = hxscan.split_args(arr[k + 1:j])
            pn, pl = hxscan.unescape(pa[0]), hxscan.unescape(pa[1])
            # 'X' / 'Y' 这类纯拉丁标签无需翻译（tOr 原样返回）
            if pn and pl and hxscan.CJK.search(pl):
                need.add(f"lg.param.{bid}.{pn}")
    # tweenDef 工厂：源码里没有 PDef 字面量，按工厂结构补齐
    for m in re.finditer(r"\btweenDef\s*\(\s*'([^']+)'", src):
        bid = m.group(1)
        need.add("lg.block." + bid)
        for pn in ("tag", "obj", "value", "dur", "ease"):
            need.add(f"lg.param.{bid}.{pn}")
        need.add("lg.blockDesc." + bid)
    miss = sorted(k for k in need if k not in zk)
    return miss, len(need)


def check_simple_derived(zk, pattern, path_rel, prefix):
    p = os.path.join(ROOT, path_rel)
    if not os.path.isfile(p):
        return [], 0
    src = open(p, encoding="utf-8").read()
    need = set()
    for m in re.finditer(pattern, src):
        v = m.group(1)
        if v:
            need.add(prefix + v)
    return sorted(k for k in need if k not in zk), len(need)


# ------------------------------------------------------- 5 静态缓存
# 「static 字段的初始化表达式里是否调用了 Lang.t*」
#
# 不能用单条正则：数组字面量的声明形态很多 ——
#   static final X:Array<String> = [Lang.tOr(..), ...];
#     static var Y:Array<Dynamic> = [ // 中间夹注释 ... Lang.tOr(..) ... ];
# 注释会打断正则，`=` 后也可能先出现 `[`。
# 改为结构化判定：定位声明 → 按括号深度取到 depth 0 的 `;` 为止的初始化表达式 → 在其中找调用。
# 调用点在**已剥注释**的源码上找，所以注释里的 Lang.t 不会误报。
STATIC_DECL = re.compile(r"\bstatic\s+(?:inline\s+)?(?:var|final)\s+(\w+)")
LANG_CALL = re.compile(r"(?:backend\.)?Lang\.(?:t|tOr|tr|trOr)\s*\(")


def check_static_cache():
    hits = []
    for p in hx_files():
        code = hxscan.strip_comments(open(p, encoding="utf-8", errors="ignore").read())
        for m in STATIC_DECL.finditer(code):
            name = m.group(1)
            # inline var 要求常量初始化，出现 Lang.t* 时编译器会直接报错，
            # 因此这里只需报出即可，不必再区分。
            i, depth, end = m.end(), 0, len(code)
            while i < end:
                c = code[i]
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    if depth == 0:
                        break
                    depth -= 1
                elif c == ";" and depth == 0:
                    break
                i += 1
            init = code[m.end():i]
            if LANG_CALL.search(init):
                hits.append((rel(p), code[:m.start()].count("\n") + 1, f"static {name} 的初始值里含 Lang.t*"))
    return hits


# ------------------------------------------------------- 6 括号对称
OPEN_TOR = re.compile(r"Lang\.tOr\('[^']+',\s*'[^']*（")


def check_bracket(path):
    p = os.path.join(ROOT, path)
    if not os.path.isfile(p):
        return []
    src = hxscan.strip_comments(open(p, encoding="utf-8").read())
    hits = []
    for l in hxscan.scan(src):
        if l.text.strip() != "）" and l.text.strip() != "）\\n\\n":
            continue
        if is_wrapped(src, l.start):
            continue
        if OPEN_TOR.search(src[max(0, l.start - 200):l.start]):
            hits.append((path, src[:l.start].count("\n") + 1, l.text))
    return hits


# ------------------------------------------------------- 7 CJK 覆盖率
def is_wrapped(src, pos):
    """该字面量是否正好是翻译调用的第 2 个实参（= 已处理的兜底原文）。

    不能只看「前面出现过 tOr(」：同一行里
        tOr('k','前段') + name + '后段中文'
    的后半段会被误判成已处理。
    """
    i = src.rfind("(", 0, pos)
    if i < 0:
        return False
    m = re.compile(r"\b(?:Lang\.)?(?:t|tOr|tr|trOr)\s*\(").search(src, max(0, i - 24), i + 1)
    if not m:
        return False
    return bool(re.fullmatch(r"""\s*(?:'[^'\\]*'|"[^"\\]*")\s*,\s*""", src[m.end():pos]))


def collect_cjk():
    out = collections.Counter()
    for p in hx_files():
        src = open(p, encoding="utf-8", errors="ignore").read()
        for l in hxscan.scan(src):
            if not hxscan.CJK.search(l.text):
                continue
            if is_wrapped(src, l.start):
                continue
            out[(rel(p), l.text)] += 1
            BEFORE.setdefault((rel(p), l.text), src[max(0, l.start - 260):l.start])
    return out


def esc(t):
    """转义控制字符：多行字面量含真实 \\t / \\n，直接写 TSV 会错列。"""
    return (t.replace("\\", "\\\\").replace("\t", "\\t")
             .replace("\r", "\\r").replace("\n", "\\n"))


def unesc(t):
    out, i = [], 0
    while i < len(t):
        if t[i] == "\\" and i + 1 < len(t):
            c = t[i + 1]
            out.append({"t": "\t", "n": "\n", "r": "\r", "\\": "\\"}.get(c, "\\" + c))
            i += 2
            continue
        out.append(t[i])
        i += 1
    return "".join(out)


# 有意不翻译的分类 —— 会作为「原因」列写进基线，使基线可审计。
# 新增一类未翻译项时，基线里会出现 ? 开头的未知原因，提醒补理由。
SKIP_REASONS = [
    ("source/luagraph/LuaBlockDefs.hx", "积木数据表：中文为唯一真源，显示走 BlockDef.labelOf/paramLabel"),
    ("source/options/", "Option 兜底原文：Option 构造函数统一走 option/optionDesc/optionValue"),
    ("source/backend/ContainerLauncher.hx", "写到磁盘的 PowerShell/.bat 脚本正文，非界面文案"),
    ("source/backend/CrashHandler.hx", "崩溃报告文件正文（写进 crash/*.txt，给开发者看）"),
    ("source/backend/Achievements.hx", "成就数据表 RAW：中文为唯一真源，显示走 nameOf/descOf/triggerOf"),
    ("source/backend/ClientPrefs.hx", "存档值字面量：改了会静默失效（显示由 optionValue.* 负责）"),
    ("source/backend/DesignTokens.hx", "主题名：显示走 themeNameAt()"),
    ("source/luagraph/LuaCodeGen.hx", "CUSTOM_BEGIN/MANAGED_BEGIN 是 .lua 往返标记"),
    ("source/luagraph/LuaGraphTemplates.hx", "misc_print 默认文本会写进用户生成的 .lua"),
    ("source/backend/ModInstallUI.hx", "m.title == '安装完成' 状态比较"),
    ("source/backend/CustomFadeTransition.hx", "MODE_* 是 static inline var 存档值"),
    ("source/psychlua/LuaClass.hx", "生成进用户 Lua 类的注释文本"),
    ("source/states/CreditsState.hx", "署名与角色描述（内容）"),
    ("source/flixel/", "引擎内部诊断日志"),
    ("source/openfl/", "存档值比较（FPS 配色档位）"),
    ("source/cne/", "CNE 兼容层的转换日志（log()，非界面文案）"),
    ("source/backend/Song.hx", "CNE 谱面转换日志（log()，非界面文案）"),
]


# 纯标点/符号（连接已翻译文本的分隔符，如 '）' '「' '   ·   ' '：' '……'）
PUNCT_ONLY = re.compile(r"^[\s\u3000-\u303f\uff00-\uffef\u2018\u2019\u201c\u201d\u2026\u00b7\u2190-\u21ff%0-9\-=/.:>+_#@&*\[\]()!?,;]+$")
# 存档值比较：data.xxx == '中文'
# 形如 ClientPrefs.data.timeBarType == '歌曲名称'（中间有字段名）/ switch 的 case '
SAVE_VALUE = re.compile(r"(?:ClientPrefs\.(?:data|defaultData)|\b\w+\.data)[\w.]*\s*[!=]==?\s*$|^\s*case\s*$")
# trace('/[Tag] ...') 可能跨行，所以不要求「到字面量为止无右括号」
DIAG = re.compile(r"(?:\btrace\s*\(|Sys\.print\w*\s*\(|FlxG\.log\.add\s*\(|\w[\w.]*\.log\s*\(|\blog\s*\()")
# 形如 '[Replay] ...' / '[Audio] ...' 的结构化诊断前缀
DIAG_TAG = re.compile(r"^\[[A-Za-z][A-Za-z ]*\]\s*")


def reason_of(path, text="", before=""):
    """判定「这条为什么有意不翻译」。先按内容特征，再退回按文件的分类表。

    返回 '?...xxx' 表示**未分类** —— 会让校验失败，提醒补理由。
    """
    if before:
        if PUNCT_ONLY.match(text or ""):
            return "分隔符/标点片段（连接已翻译文本，含中英括号成对拆分）"
        if DIAG.search(before) or DIAG_TAG.match(text or ""):
            return "诊断日志（trace / Sys.println / FlxG.log / [Tag] 前缀，release 不可见）"
        if SAVE_VALUE.search(before):
            return "存档值比较（改了会静默失效；显示由 optionValue.* 负责）"
    for prefix, why in SKIP_REASONS:
        if path.startswith(prefix):
            return why
    return "?未知原因，请补进 SKIP_REASONS 或按内容特征扩充判定"


def load_baseline():
    b = collections.Counter()
    if not os.path.isfile(BASELINE):
        return b
    for line in open(BASELINE, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3:
            try:
                b[(parts[0], unesc(parts[1]))] = int(parts[2])
            except ValueError:
                pass
    return b


# 字面量前的一小段源码，供 reason_of 做内容特征判定
BEFORE = {}


def write_baseline(counter):
    rows = sorted(counter.items(), key=lambda x: (x[0][0], x[0][1]))
    with open(BASELINE, "w", encoding="utf-8") as f:
        f.write("# 有意不翻译的剩余中文字面量基线（路径\\t字面量\\t处数）。\n")
        f.write("# 由 `python3 tools/i18n/check_i18n.py --update-baseline` 生成。\n")
        f.write("# 新增未翻译项会让 check_i18n 失败 —— 确认是有意保留后再更新基线。\n")
        for (p, t), n in rows:
            f.write(f"{p}\t{esc(t)}\t{n}\t{reason_of(p, t, BEFORE.get((p, t), ''))}\n")


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--update-baseline", action="store_true")
    args = ap.parse_args()

    z, e = read_pack(PACKS[0]), read_pack(PACKS[1])
    fails = []

    zk, ek, bad = check_packs(z, e)
    print(f"[1] 语言包完整性        zh {len(zk)} / en {len(ek)} key")
    for title, items in bad:
        fails.append(title)
        print(f"    FAIL {title}: {items[:MAX_DETAIL]}")
    if not bad:
        print("    PASS")

    lit, lit_t = check_literal_keys(zk, ek)
    print(f"[2] 字面量 key          缺失 {len(lit)}")
    if lit:
        fails.append("字面量 key 缺失")
        for x in lit[:MAX_DETAIL]:
            print(f"    FAIL {x[0]}:{x[1]}  {x[2]}")
    else:
        print("    PASS")

    om, on = check_option_keys(zk)
    print(f"[3a] Option 派生 key    需要 {on}，缺失 {len(om)}")
    if om:
        fails.append("Option 派生 key 缺失")
        for k in om[:MAX_DETAIL]:
            print(f"    FAIL {k}")
    else:
        print("    PASS")

    lm, ln = check_luagraph_keys(zk)
    print(f"[3b] luagraph 派生 key  需要 {ln}，缺失 {len(lm)}")
    if lm:
        fails.append("luagraph 派生 key 缺失")
        for k in lm[:MAX_DETAIL]:
            print(f"    FAIL {k}")
    else:
        print("    PASS")

    tm, tn = check_simple_derived(zk, r"'([a-z][a-zA-Z0-9]*)'",
                                  "source/backend/DesignTokens.hx", "theme.")
    print(f"[3c] 主题名派生 key      需要 {tn}，缺失 {len(tm)}")
    if tm:
        fails.append("主题名派生 key 缺失")
        for k in tm[:MAX_DETAIL]:
            print(f"    FAIL {k}")
    else:
        print("    PASS")

    print(f"[4] Lang.t key 缺失    {len(lit_t)}")
    if lit_t:
        fails.append("Lang.t 的 key 缺失（界面会显示 key 本身）")
        for x in lit_t[:MAX_DETAIL]:
            print(f"    FAIL {x[0]}:{x[1]}  {x[2]}")
    else:
        print("    PASS")

    sc = check_static_cache()
    print(f"[5] 静态字段缓存译文    {len(sc)}")
    if sc:
        fails.append("static 字段里缓存了译文（切语言不刷新）")
        for x in sc[:MAX_DETAIL]:
            print(f"    FAIL {x[0]}:{x[1]}  {x[2]}")
    else:
        print("    PASS")

    br = []
    for f in hx_files():
        src = hxscan.strip_comments(open(f, encoding="utf-8").read())
        for l in hxscan.scan(src):
            if l.text.strip() in ("）", "）\\n\\n") and not is_wrapped(src, l.start):
                if OPEN_TOR.search(src[max(0, l.start - 200):l.start]):
                    br.append((rel(f), src[:l.start].count("\n") + 1, l.text))
    br = [x for i, x in enumerate(br) if x not in br[:i]]
    print(f"[6] 中英括号不对称      {len(br)}")
    if br:
        fails.append("中英括号不对称")
        for x in br[:MAX_DETAIL]:
            print(f"    FAIL {x[0]}:{x[1]}  {x[2]!r}")
    else:
        print("    PASS")

    cur = collect_cjk()
    base = load_baseline()
    new = {k: v for k, v in cur.items() if base.get(k, 0) < v}
    if args.update_baseline:
        write_baseline(cur)
        print(f"[7] CJK 覆盖率         已写回基线 {len(cur)} 项")
    else:
        print(f"[7] CJK 覆盖率         基线 {len(base)} 项 / 实际 {sum(cur.values())} 处"
              f"（{len(cur)} 个字面量）新增 {len(new)}")
        if new:
            fails.append("出现新的未本地化文案")
            for (p, t), n in list(sorted(new.items()))[:MAX_DETAIL]:
                print(f"    FAIL {p}  {t[:46]!r}  x{n}")
        else:
            print("    PASS")
        unknown = sorted({(p, t) for (p, t) in cur if reason_of(p, t, BEFORE.get((p, t), "")).startswith("?")})
        if unknown:
            fails.append(f"有 {len(unknown)} 条未翻译项没有书面理由")
            for p, t in unknown[:MAX_DETAIL]:
                print(f"    FAIL 未分类 {p}  {t[:40]!r}")
        else:
            print("    全部剩余项均有书面理由 PASS")

    if args.verbose and not fails:
        top = sorted(cur.items(), key=lambda x: -x[1])[:10]
        print("\n剩余最多的未翻译项（均在基线内，属有意保留）：")
        for (p, t), n in top:
            print(f"    {n:5d}  {p}  {t[:40]!r}")

    if fails:
        print(f"\nFAIL（{len(fails)} 项）：" + "；".join(fails))
        return 1
    print("\nPASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())