#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""上游覆盖层台账生成器（第⑤大类 ①，只读）

对 source/{flixel,openfl,lime}/ 下每个覆盖文件，与 haxelib 上游逐文件 diff，产出：
文件 | 上游版本/路径 | 改动区间 | 增/删行 | 首条改动原因（就近注释） | 升级影响评级 | 可复现命令
输出：METEORIC-ARCH-AUDIT-20260918/OVERLAY-LEDGER.md + overlay-ledger.tsv
"""
import os, re, difflib, subprocess, datetime
REPO = '/Users/raidbounce/Documents/FNF-MeteoricEngine-1.0.4'
AUD = '/Users/raidbounce/Documents/METEORIC-ARCH-AUDIT-20260918'
HX = '/usr/local/lib/haxe/lib'
UP = {'flixel': HX + '/flixel/5,2,2/flixel', 'openfl': HX + '/openfl/9,4,1/openfl', 'lime': HX + '/lime/8,3,0/lime'}

def _total_diff(srcdir, updir):
    tot = 0
    for dp, _d, fs in os.walk(srcdir):
        for f in fs:
            if not f.endswith('.hx'): continue
            upf = os.path.join(updir, os.path.relpath(os.path.join(dp, f), srcdir))
            if not os.path.exists(upf): continue
            a = open(upf, encoding='utf-8', errors='replace').read().split('\n')
            b = open(os.path.join(dp, f), encoding='utf-8', errors='replace').read().split('\n')
            tot += sum((i2 - i1) + (j2 - j1) for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b).get_opcodes() if tag != 'equal')
    return tot


def find_root(pkg, srcdir):
    """数据驱动选版：对该包所有 haxelib 版本算总差异，取最小者（避免按字母序选到不匹配的版本）。"""
    base = os.path.join(HX, pkg)
    if not os.path.isdir(base): return None
    best = None
    for v in os.listdir(base):
        d = os.path.join(base, v, pkg)
        if not os.path.isdir(d): continue
        t = _total_diff(srcdir, d)
        if best is None or t < best[2]: best = (v, d, t)
    return best

rows = []
for pkg in ('flixel', 'openfl', 'lime'):
    srcdir = os.path.join(REPO, 'source', pkg)
    if not os.path.isdir(srcdir): continue
    up = find_root(pkg, srcdir)
    for dp, _d, fs in os.walk(srcdir):
        for f in fs:
            if not f.endswith('.hx'): continue
            loc = os.path.join(dp, f)
            rel = os.path.relpath(loc, srcdir)
            upf = os.path.join(up[1], rel) if up else None
            if upf and os.path.exists(upf):
                a = open(upf, encoding='utf-8', errors='replace').read().split('\n')
                b = open(loc, encoding='utf-8', errors='replace').read().split('\n')
                sm = difflib.SequenceMatcher(None, a, b)
                rng, plus, minus, reason = [], 0, 0, ''
                for tag, i1, i2, j1, j2 in sm.get_opcodes():
                    if tag == 'equal': continue
                    rng.append('%d-%d' % (j1 + 1, j2) if j2 > j1 else '%d' % (j1 + 1))
                    plus += j2 - j1; minus += i2 - i1
                    if not reason:
                        for k in range(j1, min(j2, j1 + 4)):
                            t = b[k].strip()
                            if t.startswith('//') or t.startswith('/*'):
                                reason = t[:80]; break
                if not rng: continue
                kind = 'upstream=%s' % up[0]
                cmd = 'diff -u %s %s' % (upf, loc)
            else:
                rng, plus, minus = ['全部'], len(open(loc, encoding='utf-8', errors='replace').read().split('\n')), 0
                reason = '上游无此文件（自造/移植）'
                kind = 'ABSENT(自造)'
                cmd = 'wc -l %s' % loc
            impact = '高' if (plus > 50 or minus > 50 or 'ABSENT' in kind) else ('中' if plus + minus > 10 else '低')
            rows.append({'file': 'source/%s/%s' % (pkg, rel), 'up': kind, 'rng': ','.join(rng[:6]),
                         'plus': plus, 'minus': minus, 'reason': reason, 'impact': impact, 'cmd': cmd})

rows.sort(key=lambda r: (-(r['plus'] + r['minus'])))
with open(os.path.join(AUD, 'OVERLAY-LEDGER.md'), 'w', encoding='utf-8') as fh:
    fh.write('# 上游覆盖层台账（第⑤大类 ①）\n\n> 生成：%s ｜ 上游 haxelib：flixel 5.2.2 / openfl 9.4.1 / lime 8.3.0\n'
             '> 复现：`python3 tools/boundary/overlay_ledger.py`（只读）\n\n' % datetime.date.today())
    fh.write('| 文件 | 上游 | 改动区间(本地行) | +/− | 首条改动原因 | 升级影响 |\n|---|---|---|---|---|---|\n')
    for r in rows:
        fh.write('| `%s` | %s | %s | +%d/−%d | %s | %s |\n' % (r['file'], r['up'], r['rng'], r['plus'], r['minus'], r['reason'] or '（无就近注释）', r['impact']))
with open(os.path.join(AUD, 'overlay-ledger.tsv'), 'w', encoding='utf-8') as fh:
    fh.write('file\tupstream\tchanged_ranges\tplus\tminus\treason\timpact\tdiff_command\n')
    for r in rows:
        fh.write('%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\n' % (r['file'], r['up'], r['rng'], r['plus'], r['minus'], r['reason'], r['impact'], r['cmd']))
print('  台账条目: %d' % len(rows))
for r in rows[:14]:
    print('   %-52s %-22s +%-4d −%-4d 影响%s' % (r['file'], r['up'], r['plus'], r['minus'], r['impact']))
