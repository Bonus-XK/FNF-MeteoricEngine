#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PlayState 宿主域「骨架保留 + 片段迁出」迁移器（含等价性证明）

配套 `scope_analyze.py`（作用域分析）。三件事：
  ① `--plan`  列出**严格安全**候选：verdict=mech（零遮蔽、无 private 引用）+ 零外来裸调用
     + 无 `this.`/`super.` + 非 `get_`/`set_` 属性访问器 + 非已有转发器 + 块体函数。
  ② `--apply` 迁出：函数体 → 域模块（`public static function NAME(ps:PlayState, …)`），
     PlayState 原地留**同签名单行转发入口**（`this` 传自身），调用点零改动。
  ③ **等价性证明**（默认开启，失败即不写盘）三条断言：
     A. 新体内**不得残留**任何未加前缀的成员裸引用（防漏加）；
     B. 新旧体除前缀外的裸标识符序列**逐位相同（含名字与类别）**（防过度加前缀 / 误加）；
     C. `ps.` 计数 == 旧体实例成员引用数；`PlayState.` 计数 == 旧体静态成员引用数 + 旧体原有 `PlayState.` 数。

已实测踩到并修掉的坑（写在这里避免复踩）
------------------------------------------
1. `0...strumLineNotes`：用「前面是 `.` 就算已限定」的朴素写法会误判 → **漏加前缀**。
   处置：`_qualified()` 回看 `.` 之前的 token，只有「字母/下划线开头的标识符 + `.`」才算限定；
   `...`（`.` 之前不是标识符）与数字字面量（`0.5`）都不算。
2. 转发入口必须传 `this`，域函数才叫 `ps`；两处同名会静默把宿主当参数传出去。
3. 域函数体要反缩进 + 统一 2 Tab 重排，否则粘进域模块后层级漂。

用法
----
  python3 scope_migrate.py --plan --min-lines 40
  python3 scope_migrate.py --apply --functions repositionHUD --domain backend/CameraHudDomain.hx --dry-run
  python3 scope_migrate.py --apply --functions repositionHUD --domain backend/CameraHudDomain.hx
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('sa', os.path.join(HERE, 'scope_analyze.py'))
sa = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sa)

REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
PS = os.path.join(REPO, 'source', 'states', 'PlayState.hx')


# ---------------------------------------------------------------- 基础工具
def _qualified(s, pos):
    """pos 处的标识符是否被 `member.` 形式限定（排除 `...` 与数字字面量的小数点）。"""
    i = pos - 1
    while i >= 0 and s[i] in ' \t':
        i -= 1
    if i < 0 or s[i] != '.':
        return False
    # 限定形式还包含「索引/调用结果」上的访问：`arr[i].field`、`f().field`、`(expr).field`
    # （实测踩坑：漏判 `unspawnNotes[middleId].strumTime`，生成 `…[middleId].ps.strumTime`）
    if i - 1 >= 0 and s[i - 1] in '])':
        return True
    j = i - 1
    while j >= 0 and (s[j].isalnum() or s[j] == '_'):
        j -= 1
    token = s[j + 1:i]
    if not token or token[0].isdigit():
        return False
    return True


def _is_prefix_token(s, pos, end, name):
    if name not in ('ps', 'PlayState'):
        return False
    j = end
    while j < len(s) and s[j] in ' \t':
        j += 1
    return j < len(s) and s[j] == '.'


def token_classes(masked, members, localsx):
    """裸标识符 → 类别序列。类别：local / member:inst / member:static / kw / foreign / inst-unknown。

    `inst-unknown` = 既非局部/成员、也非关键字，且**小写开头**的裸值（大写视为类/类型引用）。
    这类名字几乎必然是继承来的成员（FlxState/MusicBeatState 的字段），迁到域模块后必须写 `ps.名`。
    """
    out = []
    for mm in re.finditer(r'\b[A-Za-z_]\w*', masked):
        pos, n = mm.start(), mm.group(0)
        if _qualified(masked, pos):
            continue
        if _is_prefix_token(masked, pos, mm.end(), n):
            continue
        # 预处理指令行整体跳过：否则 `#end` 会被当作继承成员改写成 `#ps.end`
        # （实测 typecheck 报 `Unknown token`），`#if/#elseif` 同理
        ls = masked.rfind('\n', 0, pos) + 1
        if masked[ls:pos].strip().startswith('#'):
            continue
        # 结构体字段名（`{alpha: v}` / `{…, startDelay: v}`）不是成员引用，绝不能加前缀。
        # 实测踩坑：tween 选项对象 `{ease:…, startDelay:…}` 被写成 `{ps.ease:…}` → typecheck `Missing ;`。
        j = mm.end()
        while j < len(masked) and masked[j] in ' \t':
            j += 1
        k = pos - 1
        while k >= 0 and masked[k] in ' \t\n':
            k -= 1
        if j < len(masked) and masked[j] == ':' and k >= 0 and masked[k] in '{,':
            out.append((pos, n, 'key'))
            continue
        if n in localsx:
            cls = 'local'
        elif n in members:
            cls = 'member:static' if members[n]['static'] else 'member:inst'
        elif n in sa.KW:
            cls = 'kw'
        elif n[0].islower() and not re.match(r'\s*\(', masked[mm.end():]):
            cls = 'inst-unknown'
        else:
            cls = 'foreign'
        out.append((pos, n, cls))
    return out


def foreign_values(body_masked, members, localsx):
    """体外来**值**引用：小写开头的裸标识符，既非局部/参数、也非成员、也不是调用。

    这类名字几乎必然是**继承来的字段**（如 FlxState.subState）——迁到域模块后本域不可解析，
    必须写成 `ps.subState` 才能访问。工具此前只覆盖「外来调用」，漏了「外来读值」（实测 typecheck
    在 OnlineDomain 报 `Unknown identifier : subState`）。大写开头者视为类/类型引用，域模块可解析。
    """
    out = set()
    for mm in re.finditer(r'\b([a-z_]\w*)\b', body_masked):
        pos, n = mm.start(), mm.group(0)
        if _qualified(body_masked, pos) or n in localsx or n in members or n in sa.KW:
            continue
        if re.match(r'\s*\(', body_masked[mm.end():]):
            continue
        out.add(n)
    return out


def split_function(raw, i):
    masked = sa.mask('\n'.join(raw)).split('\n')
    struct = sa.collapse_preprocessor(masked)
    text = masked[i]
    p = text.find('(')
    j, depth, started = i, 0, False
    while j < len(masked):
        line = masked[j] if j > i else masked[i][p:]
        for ch in line:
            if ch == '(':
                depth += 1
                started = True
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    break
        if started and depth == 0:
            break
        j += 1
    param_close = j

    k, paren, found = i, 0, None
    while k < len(masked) and found is None:
        for c, ch in enumerate(masked[k]):
            if ch in '([':
                paren += 1
            elif ch in ')]':
                paren -= 1
            elif ch == '{' and paren <= 0:
                found = ('block', k, c)
                break
            elif ch == ';' and paren <= 0:
                found = ('expr', k, c)
                break
        k += 1
    style, open_line, open_col = found
    end_line = sa.body_span(struct, i) if style == 'block' else open_line

    sig_all = '\n'.join(masked[i:open_line + 1])
    pq = sig_all[sig_all.find('('):]
    depth, buf = 0, ''
    for ch in pq:
        if ch == '(':
            depth += 1
            if depth == 1:
                continue
        elif ch == ')':
            depth -= 1
            if depth == 0:
                break
        if depth >= 1:
            buf += ch
    params = buf
    tail = masked[param_close]
    tail = tail[tail.find(')') + 1:]
    ret = re.sub(r'^\s*:\s*', '', tail).split('{')[0].strip()

    if style == 'block':
        chunk = '\n'.join(raw[open_line:end_line + 1])
        body = chunk[open_col + 1:]
        body = body[:body.rfind('}')] if '}' in body else body
    else:
        body = raw[open_line][open_col:]
    return {'params': params, 'ret': ret, 'body': body, 'style': style,
            'decl_line': i, 'span_end': end_line,
            'mods': (sa.FN_DECL_RE.match(masked[i]).group(1) or '').strip()}


def split_params(params_text):
    out, depth, buf = [], 0, ''
    for ch in params_text:
        if ch in '(<[{':
            depth += 1
        elif ch in ')>]}':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(buf)
            buf = ''
        else:
            buf += ch
    if buf.strip():
        out.append(buf)
    return out


def param_names(params_text):
    names = []
    for p in split_params(params_text):
        m = re.match(r'\s*\??\s*([A-Za-z_]\w*)', p.strip())
        if m:
            names.append(m.group(1))
    return names


def rewrite(body_raw, members, localsx):
    """成员裸引用加前缀：实例成员与继承成员 → `ps.`，静态成员 → `PlayState.`。"""
    body_masked = sa.mask(body_raw)
    edits = []
    for pos, n, cls in token_classes(body_masked, members, localsx):
        if cls == 'member:inst' or cls == 'inst-unknown':
            edits.append((pos, 'ps.'))
        elif cls == 'member:static':
            edits.append((pos, 'PlayState.'))
    for pos, pre in sorted(edits, key=lambda x: -x[0]):
        body_raw = body_raw[:pos] + pre + body_raw[pos:]
    return body_raw, len(edits)


TYPE_INDEX = None
STD_TYPES = {'Int', 'Float', 'Bool', 'String', 'Void', 'Dynamic', 'Array', 'Map', 'Null', 'Any',
             'UInt', 'Date', 'Math', 'Std', 'StringBuf', 'Class', 'EnumValue', 'Iterable'}


def build_type_index():
    """全仓 source/ 下的 类/枚举/typedef 名 → 模块路径 索引（用于补具体 import）。

    Haxe 模块语义：主类 = `<pkg>.<类名>`；同文件次类 = `<pkg>.<文件名>.<次类名>`
    （实测踩坑：把 `PlayState.hx` 里的次类 GameHUD 当成独立模块会写出 `import states.GameHUD;` → 编译报错）。
    """
    global TYPE_INDEX
    if TYPE_INDEX is not None:
        return TYPE_INDEX
    idx = {}
    root = os.path.join(REPO, 'source')
    for dirpath, _dirs, files in os.walk(root):
        for fn in files:
            if not fn.endswith('.hx'):
                continue
            try:
                head = open(os.path.join(dirpath, fn), encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            m = re.search(r'^\s*package\s+([\w.]+)\s*;', head, re.M)
            pkg = m.group(1) if m else ''
            base = fn[:-3]
            for dm in re.finditer(r'^\s*(?:@:[\w.]+\s+)*(?:final\s+)?'
                                  r'(?:class|enum|typedef|abstract|interface)\s+([A-Za-z_]\w*)', head, re.M):
                nm = dm.group(1)
                path = ('%s.%s' % (pkg, nm)) if nm == base else ('%s.%s.%s' % (pkg, base, nm))
                idx.setdefault(nm, path)
    TYPE_INDEX = idx
    return idx


def needed_imports(dom_src, body_masked, extra_types, dom_pkg):
    """按全仓类型索引，为迁移体用到的类型补具体 import（跳过标准类型/同包/已 import）。"""
    idx = build_type_index()
    have = set(re.findall(r'import\s+([\w.]+)\s*;', dom_src))
    have_names = set(x.split('.')[-1] for x in have)
    wildcards = set(re.findall(r'import\s+([\w.]+)\.\*;', dom_src))
    used = set(m.group(1) for m in re.finditer(r'\b([A-Z]\w*)\b', body_masked)) | set(extra_types)
    out = []
    for t in sorted(used):
        if t in STD_TYPES or t in have_names:
            continue
        pkg = idx.get(t)
        if pkg is None:
            continue
        if pkg == dom_pkg or pkg in wildcards:
            continue
        out.append('import %s;' % pkg)
    return out


def dedent_reindent(body, tabs=2):
    lines = body.split('\n')
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    indents = [len(l) - len(l.lstrip('\t')) for l in lines if l.strip()]
    base = min(indents) if indents else 0
    pre = '\t' * tabs
    return '\n'.join((pre + l[base:]) if l.strip() else '' for l in lines)


def main():
    ap = argparse.ArgumentParser(description='PlayState 宿主域片段迁出器（含等价性证明）')
    ap.add_argument('--plan', action='store_true')
    ap.add_argument('--apply', action='store_true', help='与 --functions 等价（写法兼容）')
    ap.add_argument('--functions', default='')
    ap.add_argument('--domain', default='backend/CameraHudDomain.hx')
    ap.add_argument('--min-lines', type=int, default=30)
    ap.add_argument('--limit', type=int, default=12)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--allow-foreign', action='store_true', help='允许外来裸调用（默认禁止）')
    args = ap.parse_args()

    raw = open(PS, encoding='utf-8').read().split('\n')
    r = sa.scan(PS)
    members, fns = r['members'], r['fns']
    by_name = {f['name']: f for f in fns}
    dom_name = os.path.basename(args.domain)[:-3]

    def block(f):
        return '\n'.join(raw[f['line']:f['line'] + f['span_body'] - 1])

    def is_candidate(f):
        if f['verdict'] != 'mech':
            return False
        if f['unknown_calls'] and not args.allow_foreign:
            return False
        if f['name'].startswith(('get_', 'set_')):
            return False
        b = block(f)
        if re.search(r'(?<![\w.])this\s*\.', b) or re.search(r'(?<![\w.])super\s*\.', b):
            return False
        if 'Domain.' in b:
            return False
        # `#if false / #else / #end` 包裹声明的写法：`#end` 落在「声明行→体右括号」区间内，
        # 跨度替换会连它一起删掉 → 预处理配平断裂（实测 typecheck 报 Unclosed conditional compilation block）。
        if re.search(r'(?m)^\s*#(?:if|else|elseif|end)\b', b.split('{', 1)[0]):
            return False
        # 外来小写裸值不再拒绝：它们是继承成员，改写时会一并加 `ps.`，由 typecheck 复核
        if 'ps' in set(f['locals']) | set(f['params']):
            return False
        return f['span_body'] >= args.min_lines

    if args.plan:
        cand = [f for f in fns if is_candidate(f)]
        print('严格安全候选：%d 个 / %d 行（mech + 零外来裸调用 + 无 this./super. + 非访问器/转发器）'
              % (len(cand), sum(f['span_body'] for f in cand)))
        for f in sorted(cand, key=lambda x: -x['span_body'])[:args.limit]:
            print('  %5d 行 L%-5d %-30s 成员裸引用 %4d' % (f['span_body'], f['line'], f['name'], f['member_uses']))
        return 0

    names = [n for n in args.functions.split(',') if n]
    if not names:
        print('--functions 为空', file=sys.stderr)
        return 2

    dom_path = os.path.join(REPO, 'source', args.domain)
    dom = open(dom_path, encoding='utf-8').read()

    dom_pkg = ''
    _pm = re.search(r'^\s*package\s+([\w.]+)\s*;', dom, re.M)
    if _pm:
        dom_pkg = _pm.group(1)
    dom_fns, forwarders, rows, dom_imports_added = [], [], [], []
    for n in names:
        f = by_name.get(n)
        if f is None or not is_candidate(f):
            print('✘ %s 不在严格安全候选内（verdict=%s，外来裸调用=%d）'
                  % (n, f['verdict'] if f else '?', len(f['unknown_calls']) if f else -1), file=sys.stderr)
            return 2
        sp = split_function(raw, f['line'] - 1)
        if sp['style'] != 'block':
            print('✘ %s 是表达式体，本版不支持' % n, file=sys.stderr)
            return 2
        localsx = set(f['locals']) | set(f['params'])
        old_masked = sa.mask(sp['body'])
        old_seq = token_classes(old_masked, members, localsx)
        old_inst = sum(1 for _, _, c in old_seq if c in ('member:inst', 'inst-unknown'))
        old_stat = sum(1 for _, _, c in old_seq if c == 'member:static')
        old_ps = len(re.findall(r'(?<![\w])PlayState\s*\.', old_masked))

        new_body, npre = rewrite(sp['body'], members, localsx)
        new_masked = sa.mask(new_body)
        new_seq = [(nm, c) for _, nm, c in token_classes(new_masked, members, localsx)]
        old_nonmember = [(nm, c) for _, nm, c in old_seq
                         if not c.startswith('member') and c != 'inst-unknown']
        new_member_left = [(nm, c) for nm, c in new_seq
                           if c.startswith('member') or c == 'inst-unknown']
        got_ps = len(re.findall(r'(?<![\w])ps\s*\.', new_masked))
        got_stat = len(re.findall(r'(?<![\w])PlayState\s*\.', new_masked))

        a = not new_member_left
        b = (new_seq == old_nonmember)
        c = (got_ps == old_inst and got_stat == old_stat + old_ps)
        rows.append((n, f['span_body'], npre, a, b, c, old_inst, old_stat, got_ps, got_stat))
        if not (a and b and c):
            print('✘ 等价性证明失败：%s' % n, file=sys.stderr)
            print('  A 新体残留未加前缀的成员: %s' % new_member_left[:8], file=sys.stderr)
            print('  B 裸序列 old=%s' % old_nonmember[:12], file=sys.stderr)
            print('       new=%s' % new_seq[:12], file=sys.stderr)
            print('  C ps %d/%d   PlayState %d/%d' % (got_ps, old_inst, got_stat, old_stat + old_ps), file=sys.stderr)
            return 3

        head = '\n'.join(raw[f['line'] - 1:sp['decl_line'] + 1])
        head = sp['params']  # 占位，实际判定见下
        if re.search(r'(?m)^\s*#(?:if|else|elseif|end)\b',
                     '\n'.join(raw[f['line'] - 1:]).split('{', 1)[0]):
            print('✘ %s 的声明区含预处理指令，拒绝（#end 会落在迁出跨度内被吞）' % n, file=sys.stderr)
            return 2
        if len(re.findall(r'(?m)^\s*#if\b', sp['body'])) != len(re.findall(r'(?m)^\s*#end\b', sp['body'])):
            print('✘ %s 的体预处理指令不配平，拒绝' % n, file=sys.stderr)
            return 2
        pnames = param_names(sp['params'])
        arglist = ', '.join(pnames)
        if f['static']:
            call = '%s.%s(%s)' % (dom_name, n, arglist)
            dom_sig = 'public static function %s(%s)%s' % (
                n, sp['params'].strip(), (':' + sp['ret']) if sp['ret'] else '')
        else:
            call = '%s.%s(this%s)' % (dom_name, n, (', ' + arglist) if arglist else '')
            dom_sig = 'public static function %s(ps:PlayState%s)%s' % (
                n, (', ' + sp['params'].strip()) if sp['params'].strip() else '',
                (':' + sp['ret']) if sp['ret'] else '')
        body_txt = dedent_reindent(new_body)
        extra_types = set(re.findall(r'\b([A-Z]\w*)\b', sp['params'] + ' ' + sp['ret'] + ' ' + new_body))
        for imp in needed_imports(dom, new_masked, extra_types, dom_pkg):
            if imp not in dom_imports_added:
                dom_imports_added.append(imp)
        dom_fns.append('\t/** 原 PlayState.%s（作用域分析：零遮蔽，%d 处成员引用已限定）。 */\n\t%s\n\t{\n%s\n\t}\n'
                       % (n, npre, dom_sig, body_txt))
        ret_kw = 'return ' if (sp['ret'] and sp['ret'] != 'Void') else ''
        mods = (sp['mods'] + ' ') if sp['mods'] else ''
        forwarders.append((f, sp, '\t%sfunction %s(%s)%s %s%s;' % (
            mods, n, sp['params'].strip(), (':' + sp['ret']) if sp['ret'] else '', ret_kw, call)))

    print('== 等价性证明（A 无漏加 / B 无过度加 / C 前缀计数）==')
    for n, span, npre, a, b, c, oi, os_, gp, gs in rows:
        print('  %-28s %3d 行  加前缀 %3d 处  A:%s B:%s C:%s（ps %d/%d，PlayState %d/%d）'
              % (n, span, npre, 'PASS' if a else 'FAIL', 'PASS' if b else 'FAIL',
                 'PASS' if c else 'FAIL', gp, oi, gs, os_))

    if args.dry_run:
        print('\n== DRY-RUN（不写盘）==')
        for txt in dom_fns:
            print('---- 域模块新增 ----\n' + txt[:900])
        for f, sp, fwd in forwarders:
            print('---- PlayState L%d 替换为 ----\n%s' % (f['line'], fwd))
        return 0

    for f, sp, fwd in sorted(forwarders, key=lambda x: -x[0]['line']):
        raw[f['line'] - 1:sp['span_end'] + 1] = [fwd]
    open(PS, 'w', encoding='utf-8').write('\n'.join(raw))

    dom_out = dom
    if dom_imports_added:
        lines = dom_out.split('\n')
        ins = max(i for i, l in enumerate(lines) if l.startswith('import ') or l.startswith('package '))
        lines[ins + 1:ins + 1] = list(dom_imports_added)
        dom_out = '\n'.join(lines)
        print('  补 import：%s' % ', '.join(dom_imports_added))
    tail = dom_out.rstrip()
    assert tail.endswith('}'), '域模块结尾非 }'
    open(dom_path, 'w', encoding='utf-8').write(
        tail[:-1].rstrip('\n') + '\n\n' + '\n'.join(dom_fns) + '}\n')
    print('\n✔ 已写盘：PlayState 转发入口 %d 个；%s 新增 %d 个域函数'
          % (len(forwarders), args.domain, len(dom_fns)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
