#!/bin/bash
# ============================================================
# 构建期 git 信息 → source/backend/GitInfoData.hx（FPS 显示用）
# 供 build-linux.yml / build-ios.yml 调用；内容与 compile-mac.sh 内联块逐字一致
# （不改 compile-mac.sh 本体：mac 构建路径保持零风险）。
# ⚠ 不用 Haxe 宏：Codename Engine 的 GitCommitMacro 走 #if macro + sys.io.Process，
#   但本项目有全局自动导入 source/import.hx（内含 import llua.*），llua 在宏上下文
#   引用 cpp.RawPointer 被 Haxe 禁止 → 只要 import.hx 在，任何宏类都编译失败。
#   故改为脚本生成数据文件。
# 用法: bash ci/refresh-gitinfo.sh
# ============================================================
set -e
cd "$(dirname "$0")/.."

GITDATA="source/backend/GitInfoData.hx"
_git_num=$(git rev-list HEAD --count 2>/dev/null || echo "")
_git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "")
_git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
_git_dirty=$(git status --porcelain 2>/dev/null | head -1)
[ -n "$_git_num" ] || _git_num=0
[ -n "$_git_hash" ] || _git_hash="-"
[ -n "$_git_branch" ] || _git_branch="-"
_git_dirty_flag="false"
[ -n "$_git_dirty" ] && _git_dirty_flag="true"
python3 - "$GITDATA" "$_git_num" "$_git_hash" "$_git_branch" "$_git_dirty_flag" <<'PYEOF'
import re, sys
path, num, h, br, dirty = sys.argv[1:6]
s = open(path, encoding='utf-8').read()
s = re.sub(r'var commitNumber:Int = -?\d+;', 'var commitNumber:Int = %s;' % num, s)
s = re.sub(r'var commitHash:String = "[^"]*";', 'var commitHash:String = "%s";' % h, s)
s = re.sub(r'var branchName:String = "[^"]*";', 'var branchName:String = "%s";' % br, s)
s = re.sub(r'var dirty:Bool = (true|false);', 'var dirty:Bool = %s;' % dirty, s)
open(path, 'w', encoding='utf-8').write(s)
PYEOF
echo "[compile] git: #$_git_num $_git_hash $_git_branch (dirty=$_git_dirty_flag)"
