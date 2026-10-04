#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Haxe 字符串感知扫描器（i18n 校验器的依赖模块，可单独 import）。

为什么不能用正则找字面量：
  1. 多行字符串（Haxe 允许字符串内含真实换行）会被正则拦腰截断 -> 替换后语法错误；
  2. 字符串内的 \\" 转义会被正则误当成定界符 -> 替换落在转义中间，破坏 \\L 之类序列；
  3. 注释里的文字会被当成字面量。

本模块逐字符走一遍源文件，跟踪 in_string / in_comment / quote / escaped，
输出「完整的 Haxe 字符串字面量」列表（含位置、行号、跨行标记、前后是否合法）。
"""
import re

CJK = re.compile(r'[\u4e00-\u9fff]')

# 字符串内出现这些形态就说明它被用作值比较/收集器操作，必须人工确认
VALUE_USE = re.compile(
    r"(?:==|!=)\s*$"                      # xxx == '中文'
    r"|^\s*case\s*"
    r"|\.remove\($|\.contains\($|\.indexOf\($|\.push\($|\.get\($|\.has\($"
)


class Lit:
    __slots__ = ('text', 'start', 'end', 'line', 'quote', 'multiline', 'prefix', 'suffix')

    def __init__(self, text, start, end, line, quote, multiline, prefix, suffix):
        self.text = text
        self.start = start
        self.end = end
        self.line = line
        self.quote = quote
        self.multiline = multiline
        self.prefix = prefix   # 定界符之前的源码片段（用于判断 == 'x' 等）
        self.suffix = suffix   # 定界符之后紧跟的源码片段

    @property
    def has_cjk(self):
        return bool(CJK.search(self.text))

    @property
    def is_value_use(self):
        return bool(VALUE_USE.search(self.prefix)) or self.prefix.rstrip().endswith('(')

    def __repr__(self):
        f = 'M' if self.multiline else ' '
        return f'<{self.line}{f} {self.quote}{self.text[:40]!r}>'


def scan(src):
    """返回 src 中所有完整字符串字面量。"""
    lits = []
    i, n = 0, len(src)
    line = 1
    line_start = 0
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            line_start = i
            continue
        # 注释
        if c == '/' and i + 1 < n:
            if src[i + 1] == '/':
                j = src.find('\n', i)
                i = n if j < 0 else j
                continue
            if src[i + 1] == '*':
                j = src.find('*/', i + 2)
                if j < 0:
                    break
                for k in range(i, j + 2):
                    if src[k] == '\n':
                        line += 1
                i = j + 2
                continue
        # 正则字面量 ~/.../（Haxe 特有）。必须先于字符串处理：
        # 正则里可以合法地含 ' 与 "（如 ~/[.,'"%?!]/），不跳过就会把它们
        # 当成字符串定界符，后面几百行全被误判成一个跨行「字符串」。
        if c == '~' and i + 1 < n and src[i + 1] == '/':
            j = i + 2
            in_class = False
            while j < n:
                ch = src[j]
                if ch == '\\':
                    j += 2
                    continue
                if ch == '\n':
                    line += 1
                    j += 1
                    continue
                if ch == '[':
                    in_class = True
                elif ch == ']':
                    in_class = False
                elif ch == '/' and not in_class:
                    j += 1
                    break
                j += 1
            i = j
            continue
        # 字符串
        if c in '"\'':
            q = c
            j = i + 1
            buf = []
            while j < n:
                ch = src[j]
                if ch == '\\':
                    # 保留转义原文（含下一个字符）
                    if j + 1 < n:
                        buf.append(src[j:j + 2])
                        if src[j + 1] == '\n':
                            line += 1
                        j += 2
                    else:
                        j += 1
                    continue
                if ch == q:
                    break
                if ch == '\n':
                    line += 1
                buf.append(ch)
                j += 1
            end = j + 1 if j < n else j           # 含右定界符
            multiline = '\n' in ''.join(buf)
            text = ''.join(buf)
            # 反转义：只处理 \" \' \\ \n \t，其余原样（用于与语言包比对）
            lits.append(Lit(
                text=text,
                start=i,
                end=end,
                line=src[:i].count('\n') + 1,
                quote=q,
                multiline=multiline,
                prefix=src[max(line_start, i - 40):i],
                suffix=src[end:end + 24],
            ))
            for k in range(i, end):
                if src[k] == '\n':
                    line += 1
            i = end
            continue
        i += 1
    return lits


def cjk_lits(path, skip_files=None):
    """返回某文件中含中文、且不在注释里的字符串字面量。"""
    src = open(path, encoding='utf-8', errors='ignore').read()
    return [l for l in scan(src) if l.has_cjk]


def report(path, limit=None, show_prefix=False):
    ls = cjk_lits(path)
    out = []
    for l in ls:
        if l.multiline:
            out.append(f"  {l.line:5d} M  {l.quote}{l.text[:60]}{l.quote}   <<跨行>>")
        else:
            pre = f"  [{l.prefix.strip()[-22:]}]" if show_prefix and l.prefix.strip() else ''
            out.append(f"  {l.line:5d}    {l.quote}{l.text[:60]}{l.quote}{pre}")
    head = f"##### {path}  ({len(ls)} 个含中文字面量)"
    body = '\n'.join(out[:limit] if limit else out)
    return head + '\n' + body

def strip_comments(t):
    """把字符串外的 // 与 /* */ 注释替换成等长空格（保持长度，便于按偏移切分）。

    实参列表里夹着注释时，不剥会让引号配对错位（曾把 variable 实参读成注释的一部分）。
    """
    out = list(t)
    i, n, q = 0, len(t), None
    while i < n:
        c = t[i]
        if q:
            if c == '\\':
                i += 2
                continue
            if c == q:
                q = None
            i += 1
            continue
        if c in '"\'':
            q = c
            i += 1
            continue
        if c == '/' and i + 1 < n and t[i + 1] == '/':
            while i < n and t[i] != '\n':
                out[i] = ' '
                i += 1
            continue
        if c == '/' and i + 1 < n and t[i + 1] == '*':
            while i < n and not (t[i] == '*' and i + 1 < n and t[i + 1] == '/'):
                if t[i] != '\n':
                    out[i] = ' '
                i += 1
            for _ in range(2):
                if i < n:
                    out[i] = ' '
                    i += 1
            continue
        i += 1
    return ''.join(out)


def split_args(s):
    """按顶层逗号切分实参（尊重嵌套 () [] {} 与字符串）。"""
    out, buf, depth, i, n = [], [], 0, 0, len(s)
    while i < n:
        c = s[i]
        if c in '"\'':
            j = i + 1
            while j < n:
                if s[j] == '\\':
                    j += 2
                    continue
                if s[j] == c:
                    break
                j += 1
            buf.append(s[i:j + 1])
            i = j + 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ',' and depth == 0:
            out.append(''.join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if ''.join(buf).strip():
        out.append(''.join(buf).strip())
    return out


def unescape(tok):
    """Haxe 字符串字面量 token -> Python 字符串；不是字面量则返回 None。"""
    tok = tok.strip()
    if len(tok) >= 2 and tok[0] in '"\'' and tok[-1] == tok[0]:
        inner, out, i = tok[1:-1], [], 0
        while i < len(inner):
            if inner[i] == '\\' and i + 1 < len(inner):
                c = inner[i + 1]
                out.append({'n': '\n', 't': '\t', '\\': '\\', '"': '"', "'": "'"}.get(c, '\\' + c))
                i += 2
                continue
            out.append(inner[i])
            i += 1
        return ''.join(out)
    return None


CJK = re.compile(
    "[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef"   # CJK 符号标点 / 汉字 / 全角
    "\u2018\u2019\u201c\u201d\u2026\u00b7"          # 引号 省略号 间隔号
    "\u2190-\u21ff\u2b00-\u2bff]"                   # 箭头
)
