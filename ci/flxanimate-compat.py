#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
flxanimate 4.0.0（haxelib 服务器版）兼容补丁：把 Haxe 4.3 语法降级为 4.2.5。
CI 使用 Haxe 4.2.5（与本机一致）；haxelib 服务器上的 4.0.0 已更新为 ??/$nullCoalesce 语法，
4.2.5 解析报 "Unexpected ?"。用法：python3 ci/flxanimate-compat.py
"""
import os, subprocess, sys

def haxelib_path(lib):
    out = subprocess.check_output(["haxelib", "path", lib], text=True).splitlines()
    for line in out:
        p = line.strip()
        if p and os.path.isdir(p):
            return p
    return None

def patch_file(path, pairs):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for old, new in pairs:
        if old in src:
            src = src.replace(old, new)
            print("patched:", os.path.basename(path), "->", old.strip()[:50])
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)

base = haxelib_path("flxanimate")
if not base:
    print("flxanimate not found")
    sys.exit(1)

patch_file(os.path.join(base, "flxanimate", "animate", "FlxElement.hx"), [
    ("element.SI.FF ?? 0;", "element.SI.FF == null ? 0 : element.SI.FF;"),
])

patch_file(os.path.join(base, "flxanimate", "data", "MacroAnimationData.hx"), [
    ("normalize", "normalize"),  # placeholder (real pairs below)
])
patch_file(os.path.join(base, "flxanimate", "data", "MacroAnimationData.hx"), [
    ("nullCoalesce = macro $nullCoalesce ?? obj.$thing;",
     "nullCoalesce = macro (($nullCoalesce) == null ? obj.$thing : ($nullCoalesce));"),
])

print("flxanimate Haxe 4.2.5 compat done:", base)
