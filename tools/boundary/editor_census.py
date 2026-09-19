#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""编辑器耦合测绘（第④大类 ①，只读）

产出：
 ① 主流程 → 编辑器 的**全部引用点**（文件:行号 + 形态：import / 构造 / 类型引用）
 ② 编辑器 → 主流程 的反向依赖按目标类聚合
 ③ **边界 API 候选面** = 主流程真正用到的编辑器类与成员（这就是要包成统一入口的面）
 ④ 改造后预期 import 变化量（可验证数值）
主流程 = source/states/*.hx（不含 editors 子目录）+ source/backend/** + source/objects/**
"""
import os, re, sys, collections
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SRC = os.path.join(REPO, 'source')

def files():
    for dp, _d, fs in os.walk(SRC):
        for f in fs:
            if f.endswith('.hx'):
                yield os.path.join(dp, f)

def is_editor(p):
    return os.sep + 'editors' + os.sep in p

def is_main(p):
    rel = os.path.relpath(p, SRC)
    if rel.startswith('states' + os.sep) and not rel.startswith('states' + os.sep + 'editors'):
        return True
    return rel.startswith('backend' + os.sep) or rel.startswith('objects' + os.sep)

allf = list(files())
# 编辑器类名 → 文件
editor_classes = {}
for p in allf:
    if not is_editor(p): continue
    txt = open(p, encoding='utf-8', errors='replace').read()
    m = re.search(r'^\s*package\s+([\w.]+)\s*;', txt, re.M)
    pkg = m.group(1) if m else ''
    for dm in re.finditer(r'^\s*(?:@:[\w.]+\s+)*(?:class|enum|typedef|abstract)\s+([A-Za-z_]\w*)', txt, re.M):
        editor_classes[dm.group(1)] = (pkg, os.path.relpath(p, REPO))

fwd = []           # (主流程文件, 行号, 形态, 目标)
editor_import_edges = 0
for p in allf:
    if not is_main(p): continue
    rel = os.path.relpath(p, REPO)
    for i, l in enumerate(open(p, encoding='utf-8', errors='replace').read().split('\n'), 1):
        s = l.strip()
        if s.startswith('import ') and 'editors' in s:
            editor_import_edges += 1
            fwd.append((rel, i, 'import', s))
        for cls, (pkg, ep) in editor_classes.items():
            if re.search(r'(?<![\w.])%s\b' % cls, l) and 'import' not in s[:7]:
                fwd.append((rel, i, 'use:' + cls, s[:100]))

# 反向：编辑器 → 主流程
rev = collections.Counter()
main_classes = {}
for p in allf:
    if not is_main(p): continue
    txt = open(p, encoding='utf-8', errors='replace').read()
    m = re.search(r'^\s*package\s+([\w.]+)\s*;', txt, re.M)
    pkg = m.group(1) if m else ''
    for dm in re.finditer(r'^\s*(?:@:[\w.]+\s+)*(?:class|enum|typedef|abstract)\s+([A-Za-z_]\w*)', txt, re.M):
        main_classes[dm.group(1)] = pkg
for p in allf:
    if not is_editor(p): continue
    txt = open(p, encoding='utf-8', errors='replace').read()
    for cls in main_classes:
        c = len(re.findall(r'(?<![\w.])%s\b' % cls, txt))
        if c: rev[cls] += c

print('== ① 主流程 → 编辑器 引用点：%d 条 ==' % len(fwd))
by_file = collections.Counter(x[0] for x in fwd)
for f, n in by_file.most_common(): print('   %-52s %d 条' % (f, n))
print('   其中 import 语句：%d 条' % sum(1 for x in fwd if x[2] == 'import'))
print('== ③ 边界 API 候选面（主流程用到的编辑器类）%d 个 ==' % len(editor_classes))
used = sorted(set(x[2][4:] for x in fwd if x[2].startswith('use:')))
for c in used: print('   %-34s %s' % (c, editor_classes[c][1]))
print('== ② 编辑器 → 主流程 反向依赖 Top10（按引用次数） ==')
for c, n in rev.most_common(10): print('   %-28s %5d 次  (package %s)' % (c, n, main_classes[c]))
print('== ④ 预期变化量 ==')
print('   主流程 import 编辑器类：%d 条 → 改造后目标 0 条' % editor_import_edges)
