#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PlayState 作用域与迁移可行性分析器（C 组追加小类「作用域分析工具」交付物）

只读源码，不修改任何引擎文件。

产出
----
① **成员表**：PlayState 类级 `var/final` 与 `function`，带 static / private 标记。
② **真遮蔽**：函数内局部变量或参数名 == 成员名（变量或方法）——这些位置**不能**机械加宿主前缀。
③ **迁移可行性分级**（逐函数）：
   - `mech`      零遮蔽 且 不引用 private 实例成员 → 可机械改写（成员裸引用统一加 `<host>.`）
   - `accessor`  零遮蔽 但引用 private 成员 → 需先加访问器/改可见性（或走 `@:access`）
   - `manual`    有遮蔽 → 必须人工逐处甄别
④ **与上一轮口径的定量对照**：上一轮「遮蔽计数」来自 /tmp/c4recon.py 的启发式
   （fields = 类区间内任何 `var X`，含函数体内局部与字段声明 → `len(fields ∩ body_locals)` 实际
   数的是「局部变量 + 参数」，甚至在 `releaseSongChartDom` 这种「短函数 + 后续 222 行字段声明」
   区间上数的是**字段声明自身**）。`--compare` 会在同一条 commit 的文件上把两种口径并排打出。

两个已实测的坑（都已在实现里处理）
--------------------------------
A. **预处理分支破坏花括号配对**：`#if C ... { #else ... { #end` 在原始文本里是「两个 `{` 一个 `}`」，
   朴素计数会让函数体延伸到文件尾（实测把 `generateChartNotes` 算成 4964 行；基线里
   `releaseSongChartDom` 也会被算错）。处置：花括号配对走**配置感知结构文本**（每个条件组只保留
   一个分支；字面量 `#if false` 取其 `#else` 分支）；遮蔽/引用分析仍用**全分支**文本（保守）。
B. **单引号插值** `'${...}'` 内是代码：保长掩码必须把 `${}` 当代码处理，否则引号错配。

已知局限（如实声明）
------------------
- 遮蔽按**名字级**判定，不做块级生命周期分析 → 保守（同名的不同作用域也会被计为遮蔽）。
- 未覆盖：`switch` 枚举模式绑定、父类/继承成员、宏生成成员、`using` 扩展静态、`Type.createInstance` 式反射。
- 行数两套口径并列出：`span_legacy`（声明行 → 下一个函数声明行，上一轮口径）与 `span_body`（声明行 → 匹配右花括号）。
"""
import argparse
import os
import re
import sys
import tempfile

KW = {
    'var', 'final', 'function', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default',
    'break', 'continue', 'return', 'try', 'catch', 'throw', 'new', 'this', 'super', 'null', 'true',
    'false', 'in', 'is', 'cast', 'trace', 'class', 'interface', 'enum', 'typedef', 'package',
    'import', 'using', 'extends', 'implements', 'public', 'private', 'static', 'inline', 'override',
    'dynamic', 'macro', 'extern', 'abstract', 'from', 'to', 'operator', 'get', 'set',
    'never', 'untyped', 'with', 'Void', 'Int', 'Float', 'Bool', 'String', 'Dynamic',
}

FIELD_DECL_RE = re.compile(
    r'^\t((?:@:[\w.]+\s+)*(?:(?:public|private|static|inline|override|dynamic|final)\s+)*)'
    r'(?:var|final)\s+([A-Za-z_]\w*)')
FN_DECL_RE = re.compile(
    r'^\t((?:@:[\w.]+\s+)*(?:(?:public|private|static|inline|override|dynamic|final)\s+)*)'
    r'function\s+([A-Za-z_]\w*)')


# ---------------------------------------------------------------- 保长掩码
def mask(src):
    """剥离注释/字符串/正则内容，保留换行与长度；单引号内 ${...} 视为代码。"""
    out = list(src)

    def blank(a, b):
        for k in range(a, min(b, len(out))):
            if out[k] != '\n':
                out[k] = ' '

    def scan_dquote(i, n):
        i += 1
        while i < n:
            if src[i] == '\\':
                blank(i, i + 2)
                i += 2
                continue
            if src[i] == '"':
                return i + 1
            blank(i, i + 1)
            i += 1
        return i

    def scan_squote(i, n):
        i += 1
        while i < n:
            if src[i] == '\\':
                blank(i, i + 2)
                i += 2
                continue
            if src[i] == '$' and i + 1 < n and src[i + 1] == '{':
                i += 2
                depth = 1
                while i < n and depth > 0:
                    c = src[i]
                    if c == '{':
                        depth += 1
                    elif c == '}':
                        depth -= 1
                        if depth == 0:
                            i += 1
                            break
                    elif c == '"':
                        i = scan_dquote(i, n)
                        continue
                    elif c == "'":
                        i = scan_squote(i, n)
                        continue
                    elif c == '/' and i + 1 < n and src[i + 1] == '/':
                        j = src.find('\n', i)
                        j = n if j < 0 else j
                        blank(i, j)
                        i = j
                        continue
                    i += 1
                continue
            if src[i] == '$' and i + 1 < n and (src[i + 1].isalpha() or src[i + 1] == '_'):
                i += 2
                while i < n and (src[i].isalnum() or src[i] == '_'):
                    i += 1
                continue
            if src[i] == "'":
                return i + 1
            blank(i, i + 1)
            i += 1
        return i

    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            blank(i, j)
            i = j
        elif c == '"':
            i = scan_dquote(i, n)
        elif c == "'":
            i = scan_squote(i, n)
        elif c == '~' and i + 1 < n and src[i + 1] == '/':
            i += 2
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == '/':
                    i += 1
                    break
                blank(i, i + 1)
                i += 1
        else:
            i += 1
    return ''.join(out)


def collapse_preprocessor(masked_lines):
    """每个条件组只保留一个分支：`#if false` 取其 `#else`，其余取 `#if` 分支。"""
    out = list(masked_lines)
    stack = []
    for i, line in enumerate(masked_lines):
        m = re.match(r'#(if|elseif|else|end)\b(.*)', line.strip())
        if m:
            kw, rest = m.group(1), m.group(2).strip()
            parent = stack[-1]['kept'] if stack else True
            if kw == 'if':
                keep_if = (rest != 'false')
                stack.append({'parent': parent, 'keep_if': keep_if,
                              'kept': parent and keep_if, 'used_fallback': False})
            elif kw in ('elseif', 'else'):
                if stack:
                    fr = stack[-1]
                    take = (not fr['keep_if']) and (not fr['used_fallback'])
                    fr['kept'] = fr['parent'] and take
                    if take:
                        fr['used_fallback'] = True
            elif kw == 'end':
                if stack:
                    stack.pop()
            continue
        if stack and not stack[-1]['kept']:
            out[i] = ''
    return out


def class_bounds(lines, cls, stop_at):
    start = None
    for i, l in enumerate(lines):
        if re.match(r'\s*class\s+%s\b' % re.escape(cls), l):
            start = i
            break
    if start is None:
        raise SystemExit('找不到 class %s' % cls)
    end = len(lines)
    if stop_at:
        for i in range(start + 1, len(lines)):
            if re.match(r'\s*class\s+%s\b' % re.escape(stop_at), lines[i]):
                end = i
                break
    return start, end


def parse_param_names(sig_text):
    p = sig_text.find('(')
    if p < 0:
        return []
    depth, buf, parts = 0, '', []
    for ch in sig_text[p:]:
        if ch == '(':
            depth += 1
            if depth == 1:
                continue
        elif ch == ')':
            depth -= 1
            if depth == 0:
                parts.append(buf)
                break
        if depth >= 1:
            buf += ch
    names = []
    for part in (parts[0].split(',') if parts else []):
        m = re.match(r'\s*\??\s*([A-Za-z_]\w*)\s*(?::|$)', part.strip())
        if m:
            names.append(m.group(1))
    return names


def body_span(struct_lines, fn_idx):
    """返回函数体结束行索引。

    支持两种体形态：
      · 块体   `function f():Void` 换行 `{ ... }`  → 花括号配对
      · 表达式体 `static function get_x():Bool` 换行 `return ...;`  → 到该语句的分号
    （实测坑：只做花括号配对时，表达式体函数会扫到下一个函数的 `{`，
      把中间的字段声明块整段吞进「函数体」，并让字段声明被误判为局部变量。）
    """
    paren = 0
    for i in range(fn_idx, len(struct_lines)):
        for ch in struct_lines[i]:
            if ch in '([':
                paren += 1
            elif ch in ')]':
                paren -= 1
            elif ch == '{' and paren <= 0:
                depth, started = 0, False
                for k in range(i, len(struct_lines)):
                    for c2 in struct_lines[k]:
                        if c2 == '{':
                            depth += 1
                            started = True
                        elif c2 == '}':
                            depth -= 1
                            if started and depth == 0:
                                return k
                return len(struct_lines) - 1
            elif ch == ';' and paren <= 0:
                return i
    return len(struct_lines) - 1


def legacy_count(raw_lines, s, e, body_text, sig_line):
    """上一轮口径（/tmp/c4recon.py）的忠实复现。"""
    fields_legacy = set()
    for l in raw_lines[s:e]:
        for m in re.finditer(r'\bvar\s+([A-Za-z0-9_]+)', l):
            fields_legacy.add(m.group(1))
    F = {x for x in fields_legacy if re.search(r'(?<![\w.])%s\b' % re.escape(x), body_text)}
    loc = set(re.findall(r'\bvar\s+([A-Za-z0-9_]+)', body_text))
    loc |= set(re.findall(r'([A-Za-z0-9_]+)\s*:', sig_line.split('function', 1)[-1]))
    return len(F & loc)


def scan(path, cls='PlayState', stop_at='GameHUD'):
    raw = open(path, encoding='utf-8').read().split('\n')
    masked = mask('\n'.join(raw)).split('\n')
    struct = collapse_preprocessor(masked)
    s, e = class_bounds(raw, cls, stop_at)

    members = {}
    for i in range(s, e):
        m = FIELD_DECL_RE.match(struct[i])
        if m:
            mods = m.group(1)
            members.setdefault(m.group(2), {'kind': 'var', 'static': 'static' in mods,
                                            'private': 'private' in mods, 'line': i + 1})
        m = FN_DECL_RE.match(struct[i])
        if m:
            mods = m.group(1)
            members.setdefault(m.group(2), {'kind': 'func', 'static': 'static' in mods,
                                            'private': 'private' in mods, 'line': i + 1})

    # 清单走配置感知文本：`#if false / #else / #end` 只保留生效分支（避免同名函数被数两次）
    fn_idx = [i for i in range(s, e) if FN_DECL_RE.match(struct[i])]
    fns = []
    for k, i in enumerate(fn_idx):
        m = FN_DECL_RE.match(struct[i])
        fname = m.group(2)
        fend = body_span(struct, i)
        nxt = fn_idx[k + 1] if k + 1 < len(fn_idx) else e
        sig = masked[i]
        if masked[i].count('(') > masked[i].count(')'):
            sig = sig + ' ' + ' '.join(masked[i + 1:i + 3])
        # 函数体不含声明行（否则「函数名 + (」会被误计成本函数自调用）
        body_lines = masked[i + 1:fend + 1]
        body = '\n'.join(body_lines)

        params = parse_param_names(sig)
        locals_ = []
        local_lines = {}
        for off, bl in enumerate(body_lines):
            abs_line = i + 2 + off
            for mm in re.finditer(r'(?<![\w.])(?:var|final)\s+([A-Za-z_]\w*)', bl):
                locals_.append(mm.group(1))
                local_lines.setdefault(mm.group(1), abs_line)
            for mm in re.finditer(r'\bfor\s*\(\s*([A-Za-z_]\w*)\s+in\b', bl):
                locals_.append(mm.group(1))
                local_lines.setdefault(mm.group(1), abs_line)
            for mm in re.finditer(r'\bcatch\s*\(\s*([A-Za-z_]\w*)', bl):
                locals_.append(mm.group(1))
                local_lines.setdefault(mm.group(1), abs_line)
            # 箭头函数参数：`(a, b) -> …` 与单参 `a -> …`（核实员反例指出的漏报面）
            for mm in re.finditer(r'\(([^()]*)\)\s*->', bl):
                for part in mm.group(1).split(','):
                    pm = re.match(r'\s*\??\s*([A-Za-z_]\w*)', part)
                    if pm:
                        locals_.append(pm.group(1))
                        local_lines.setdefault(pm.group(1), abs_line)
            for mm in re.finditer(r'(?<![\w.])([A-Za-z_]\w*)\s*->', bl):
                locals_.append(mm.group(1))
                local_lines.setdefault(mm.group(1), abs_line)
            for mm in re.finditer(r'\bfunction\s+([A-Za-z_]\w*)\s*\(', bl):
                locals_.append(mm.group(1))
                local_lines.setdefault(mm.group(1), abs_line)
            for mm in re.finditer(r'\bfunction\s*\(([^)]*)\)', bl):
                for part in mm.group(1).split(','):
                    pm = re.match(r'\s*\??\s*([A-Za-z_]\w*)', part)
                    if pm:
                        locals_.append(pm.group(1))
                        local_lines.setdefault(pm.group(1), abs_line)

        names = set(params) | set(locals_)
        shadows = sorted(n for n in names if n in members)
        shadow_uses = {n: len(re.findall(r'(?<![\w.])%s\b' % re.escape(n), body)) for n in shadows}

        uses_var = {'pub_static': 0, 'priv_static': 0, 'pub_inst': 0, 'priv_inst': 0}
        uses_call = {'pub_static': 0, 'priv_static': 0, 'pub_inst': 0, 'priv_inst': 0}
        priv_names = set()
        for mm in re.finditer(r'(?<![\w.])([A-Za-z_]\w*)', body):
            t = mm.group(1)
            mem = members.get(t)
            if not mem:
                continue
            is_call = bool(re.match(r'\s*\(', body[mm.end():]))
            key = ('priv_' if mem['private'] else 'pub_') + ('static' if mem['static'] else 'inst')
            if mem['kind'] == 'func':
                if is_call:
                    uses_call[key] += 1
                    if mem['private']:
                        priv_names.add(t)
            else:
                uses_var[key] += 1
                if mem['private']:
                    priv_names.add(t)

        # 未在本类声明的裸调用（继承方法如 add()/openSubState()/switchState()、或工具函数）
        # —— 迁出时必须显式限定（`ps.`/`MusicBeatState.`/`Paths.`…），是真实的迁移风险项。
        unknown_calls = {}
        for mm in re.finditer(r'(?<![\w.])([a-z_]\w*)\s*\(', body):
            t = mm.group(1)
            if t in KW or t in members or t in names:
                continue
            unknown_calls[t] = unknown_calls.get(t, 0) + 1

        priv_uses = (sum(v for k, v in uses_var.items() if k.startswith('priv'))
                     + sum(v for k, v in uses_call.items() if k.startswith('priv')))
        verdict = 'manual' if shadows else ('accessor' if priv_uses else 'mech')

        fns.append({
            'name': fname, 'line': i + 1, 'static': 'static' in m.group(1),
            'span_body': fend - i + 1, 'span_legacy': nxt - i,
            'params': params, 'locals': locals_,
            'shadows': shadows, 'shadow_uses': shadow_uses,
            'shadow_local_line': {n: local_lines.get(n) for n in shadows},
            'member_box': {n: members[n]['line'] for n in shadows},
            'uses_var': uses_var, 'uses_call': uses_call, 'unknown_calls': unknown_calls,
            'member_uses': sum(uses_var.values()) + sum(uses_call.values()),
            'priv_uses': priv_uses, 'priv_names': sorted(priv_names),
            'verdict': verdict,
            'legacy': legacy_count(raw, s, e, '\n'.join(raw[i:nxt]), raw[i]),
        })
    return {'path': path, 'lines_total': len(raw) - 1, 'members': members, 'fns': fns,
            'class_start': s + 1, 'class_end': e}


# ---------------------------------------------------------------- 对照用例
def selftest():
    sample = '''class Demo
{
\tvar hp:Int = 0;
\tvar score:Int = 0;
\tprivate var secret:Int = 1;

\tpublic function noShadow():Void
\t{
\t\tscore = score + 1;
\t\thp = score;
\t}

\tpublic function withShadow():Void
\t{
\t\tvar score:Int = 3;
\t\thp = score;
\t}

\tpublic function paramShadow(score:Int):Void
\t{
\t\thp = score;
\t}

\tpublic function branchy(a:Bool):Void
\t{
\t\t#if mobile
\t\tif (a) {
\t\t#else
\t\tif (!a) {
\t\t#end
\t\t\thp = 1;
\t\t}
\t\tscore = 2;
\t}

\tpublic function usesPrivate():Void
\t{
\t\tsecret = 5;
\t\thp = secret;
\t}

\tpublic function callSelf():Void
\t{
\t\tnoShadow();
\t}
}
'''
    fd, p = tempfile.mkstemp(suffix='.hx')
    os.write(fd, sample.encode('utf-8'))
    os.close(fd)
    r = scan(p, cls='Demo', stop_at=None)
    os.unlink(p)
    f = {x['name']: x for x in r['fns']}
    checks = {
        'shadows.noShadow': f['noShadow']['shadows'] == [],
        'shadows.withShadow': f['withShadow']['shadows'] == ['score'],
        'shadows.paramShadow': f['paramShadow']['shadows'] == ['score'],
        'shadows.branchy': f['branchy']['shadows'] == [],
        'span.noShadow=5': f['noShadow']['span_body'] == 5,
        'span.branchy=11(预处理分支未撑爆)': f['branchy']['span_body'] == 11,
        'verdict.mech(noShadow)': f['noShadow']['verdict'] == 'mech',
        'verdict.manual(withShadow)': f['withShadow']['verdict'] == 'manual',
        'verdict.accessor(usesPrivate)': f['usesPrivate']['verdict'] == 'accessor',
        'uses.private_secret=2': f['usesPrivate']['uses_var']['priv_inst'] == 2,
        'uses.call(noShadow)=1': f['callSelf']['uses_call']['pub_inst'] == 1,
        'members.priv(secret)': r['members']['secret']['private'] is True,
    }
    ok = all(checks.values())
    print('selftest: %s' % ('PASS' if ok else 'FAIL'))
    for k, v in checks.items():
        print('   %-42s %s' % (k, 'ok' if v else 'FAIL'))
    return 0 if ok else 1


# ---------------------------------------------------------------- 主流程
def main():
    ap = argparse.ArgumentParser(description='PlayState 作用域与迁移可行性分析器（只读）')
    ap.add_argument('--file', default=None)
    ap.add_argument('--selftest', action='store_true')
    ap.add_argument('--tsv', default=None)
    ap.add_argument('--top', type=int, default=12)
    ap.add_argument('--shadow-detail', action='store_true', help='逐条打印真遮蔽明细')
    ap.add_argument('--compare', default='releaseSongChartDom,noteSpawn,popUpScore,create,update')
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    path = args.file or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     '..', '..', 'source', 'states', 'PlayState.hx')
    path = os.path.abspath(path)
    r = scan(path)
    fns = r['fns']
    mem = r['members']
    mv = [m for m in mem.values() if m['kind'] == 'var']
    mf = [m for m in mem.values() if m['kind'] == 'func']
    mech = [f for f in fns if f['verdict'] == 'mech']
    acc = [f for f in fns if f['verdict'] == 'accessor']
    man = [f for f in fns if f['verdict'] == 'manual']

    print('== ① 输入与规模 ==')
    print('  文件             : %s' % path)
    print('  总行数           : %d（class PlayState 区间 L%d-L%d）' % (r['lines_total'], r['class_start'], r['class_end']))
    print('  类级成员         : %d（var %d / function %d）' % (len(mem), len(mv), len(mf)))
    print('    其中 private   : var %d / function %d'
          % (sum(1 for m in mv if m['private']), sum(1 for m in mf if m['private'])))
    print('    其中 static    : var %d / function %d'
          % (sum(1 for m in mv if m['static']), sum(1 for m in mf if m['static'])))
    print('  类级函数体行数   : %d（逐函数 span_body 合计；span_legacy 合计 %d）'
          % (sum(f['span_body'] for f in fns), sum(f['span_legacy'] for f in fns)))

    print()
    print('== ② 真遮蔽（局部/参数名 == 成员名，变量或方法）==')
    print('  有遮蔽函数 : %2d 个 / %5d 行 → verdict=manual' % (len(man), sum(f['span_body'] for f in man)))
    print('  零遮蔽函数 : %2d 个 / %5d 行' % (len(mech) + len(acc), sum(f['span_body'] for f in mech + acc)))
    print('      ├ mech（零遮蔽 + 无 private 引用）: %2d 个 / %5d 行，成员裸引用 %d 处'
          % (len(mech), sum(f['span_body'] for f in mech), sum(f['member_uses'] for f in mech)))
    print('      └ accessor（零遮蔽 + 引用 private）: %2d 个 / %5d 行，其中 private 引用 %d 处'
          % (len(acc), sum(f['span_body'] for f in acc), sum(f['priv_uses'] for f in acc)))
    with_unknown = [f for f in fns if f['unknown_calls']]
    print('  含「未在本类声明的裸调用」的函数: %d 个（迁出时须显式限定；见 ④ 的风险列）'
          % len(with_unknown))

    if man:
        print()
        print('== ③ 真遮蔽明细（manual 面，全部 %d 个）==' % len(man))
        for f in sorted(man, key=lambda x: -x['span_body']):
            det = ', '.join('%s(局部L%s/成员L%s,用%d)'
                            % (n, f['shadow_local_line'][n], f['member_box'][n], f['shadow_uses'][n])
                            for n in f['shadows'][:6])
            more = '' if len(f['shadows']) <= 6 else ' …共%d名' % len(f['shadows'])
            print('  %5d 行 L%-5d %-28s 遮蔽 %d 名: %s%s'
                  % (f['span_body'], f['line'], f['name'], len(f['shadows']), det, more))

    print()
    print('== ④ mech 面（可机械迁移，按行数降序前 %d）==' % args.top)
    for f in sorted(mech, key=lambda x: -x['span_body'])[:args.top]:
        print('  %5d 行 L%-5d %-28s 成员裸引用 %4d 处（var %d / call %d）｜外来裸调用 %2d 种 %3d 处%s'
              % (f['span_body'], f['line'], f['name'], f['member_uses'],
                 sum(f['uses_var'].values()), sum(f['uses_call'].values()),
                 len(f['unknown_calls']), sum(f['unknown_calls'].values()),
                 ('  ' + ','.join(list(f['unknown_calls'])[:4])) if f['unknown_calls'] else ''))

    print()
    print('== ⑤ accessor 面（需先开访问口，按 private 引用降序前 %d）==' % args.top)
    for f in sorted(acc, key=lambda x: -x['priv_uses'])[:args.top]:
        print('  %5d 行 L%-5d %-28s private 引用 %3d 处: %s'
              % (f['span_body'], f['line'], f['name'], f['priv_uses'], ','.join(f['priv_names'][:6])))

    targets = [t for t in (args.compare or '').split(',') if t]
    if targets:
        print()
        print('== ⑥ 与上一轮口径对照（legacy = /tmp/c4recon.py 忠实复现）==')
        print('  %-24s %11s %11s %8s %9s' % ('函数', 'span_legacy', 'legacy 计数', '真遮蔽', 'span_body'))
        for t in targets:
            for f in fns:
                if f['name'] == t:
                    print('  %-24s %11d %11d %8d %9d'
                          % (t, f['span_legacy'], f['legacy'], len(f['shadows']), f['span_body']))
                    break
    if args.tsv:
        with open(args.tsv, 'w', encoding='utf-8') as fh:
            fh.write('function\tline\tspan_body\tspan_legacy\tverdict\tstatic\tparams\tlocals\tshadows\t'
                     'shadow_names\tmember_uses\tpriv_uses\tpriv_names\tlegacy\t'
                     'unknown_call_kinds\tunknown_call_uses\tunknown_call_names\n')
            for f in fns:
                fh.write('%s\t%d\t%d\t%d\t%s\t%s\t%d\t%d\t%d\t%s\t%d\t%d\t%s\t%d\t%d\t%d\t%s\n' % (
                    f['name'], f['line'], f['span_body'], f['span_legacy'], f['verdict'],
                    'Y' if f['static'] else 'N', len(f['params']), len(f['locals']),
                    len(f['shadows']), ','.join(f['shadows']), f['member_uses'],
                    f['priv_uses'], ','.join(f['priv_names']), f['legacy'],
                    len(f['unknown_calls']), sum(f['unknown_calls'].values()),
                    ','.join(f['unknown_calls'])))
        print('\nTSV 已写入: %s' % args.tsv)
    return 0


if __name__ == '__main__':
    sys.exit(main())
