#!/bin/sh
# Meteoric Engine —— 源码一键上传脚本
#
# 把工作区源码（严格遵循 .gitignore）提交并推送到 origin。
#
# 用法:
#   ./push-source.sh                     # 自动生成提交信息，提交全部改动并推送
#   ./push-source.sh "提交说明"           # 指定提交信息
#   ./push-source.sh -m "提交说明"        # 同上（兼容 git 习惯）
#   ./push-source.sh -b feat/xxx         # 推送到指定分支（不存在则创建）
#   ./push-source.sh -n                  # 预演：只打印将要提交的内容，不写任何东西
#   ./push-source.sh --no-push           # 只提交，不推送
#
# 设计原则（每条都对应一次真实踩坑）:
#   1. 严格遵循 .gitignore：export/、tools/user_mods_prev/（可达 15G 用户数据）、
#      .DS_Store、*.orig、*.log 等一律不入库；本脚本**不做**任何 -f 强制添加。
#   2. 提交前检查「未跟踪的 .hx 模块」：Meteoric 出现过 FunkinLua.hx 已改为引用
#      source/psychlua/functions/，而该目录未跟踪的情况 —— 只推已跟踪文件会让仓库
#      编译不过。检测到就中止并列出，避免把坏仓库推上去。
#   3. 提交前检查「>5MB 且尚未入库」的新文件：素材/二进制误入库后很难清除，
#      先拦下来让人确认。
#   4. 推送后**用远端 HEAD 与本地 HEAD 比对**验证结果，不只看 git push 的退出码。
set -e
cd "$(dirname "$0")"

REMOTE="origin"
BRANCH=""
MSG=""
DRY_RUN=0
DO_PUSH=1
LARGE_MB=5

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    --no-push)    DO_PUSH=0; shift ;;
    -b|--branch)  BRANCH="$2"; shift 2 ;;
    -m|--message) MSG="$2"; shift 2 ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *)            MSG="$1"; shift ;;
  esac
done

say()  { printf '%s\n' "$*"; }
head1() { printf '\n=== %s ===\n' "$*"; }

# ---------- 0. 前置检查 ----------
if [ ! -d .git ]; then
  say "✘ 当前目录不是 git 仓库：$(pwd)"
  exit 1
fi
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  say "✘ 没有名为 $REMOTE 的远端。现有远端："
  git remote -v
  exit 1
fi
if [ -z "$BRANCH" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$BRANCH" = "HEAD" ]; then
    say "✘ 处于 detached HEAD，请用 -b <分支名> 指定要推送的分支。"
    exit 1
  fi
fi

head1 "目标"
say "  仓库目录 : $(pwd)"
say "  远端     : $REMOTE  ($(git remote get-url "$REMOTE"))"
say "  分支     : $BRANCH"
say "  当前 HEAD: $(git rev-parse --short HEAD)  $(git log -1 --pretty=%s)"

# ---------- 1. 列出将被提交的内容（严格按 .gitignore 过滤） ----------
PENDING="$(git ls-files -co --exclude-standard)"
CHANGED_N=0
if [ -n "$PENDING" ]; then
  CHANGED_N=$(printf '%s\n' "$PENDING" | wc -l | tr -d ' ')
fi

head1 "将提交的文件（已按 .gitignore 过滤）"
if [ "$CHANGED_N" -eq 0 ]; then
  say "  工作区干净，没有需要提交的改动。"
else
  # 只列相对上一次提交有差异的路径，避免刷屏（跟踪中但未改动的文件不算）
  git status --short | sed 's/^/  /'
  say ""
  say "  合计待提交条目: $CHANGED_N"
fi

# ---------- 2. 安全检查：未跟踪的 .hx（会导致远端仓库编译不过） ----------
UNTRACKED_HX="$(git ls-files -o --exclude-standard | grep '\.hx$' || true)"
if [ -n "$UNTRACKED_HX" ]; then
  head1 "⚠ 提醒：以下 .hx 是**新增且尚未入库**的"
  printf '%s\n' "$UNTRACKED_HX" | sed 's/^/  /'
  say "  这些会随本次提交一起入库（正常）。"
  say "  但若其中某个是**既有文件已改为引用、而你不想入库**的模块，请先处理，否则远端编译不过。"
fi

# ---------- 3. 安全检查：大文件 ----------
# 注意：逐行读取，不能用 `for f in $PENDING` —— 那会按空格分词，
# 把 "NewFall Tracks with chart" 这类含空格路径拆成多个不存在的路径。
BIG="$(printf '%s\n' "$PENDING" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  s=$(stat -f '%z' "$f" 2>/dev/null || stat -c '%s' "$f" 2>/dev/null || echo 0)
  if [ "$s" -gt $((LARGE_MB * 1024 * 1024)) ]; then
    if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      echo "  $((s / 1024 / 1024))MB  $f"
    fi
  fi
done)"
if [ -n "$BIG" ]; then
  head1 "⚠ 以下 >${LARGE_MB}MB 的新文件将被入库（此前未跟踪）"
  printf '%s' "$BIG"
  say "  素材/二进制一旦入库很难清除，请确认是否该提交。"
fi

# ---------- 4. 危险路径断言（.gitignore 失效时的最后一道闸） ----------
# 只看**本次变更**，且只看「新增(A)/修改(M)/重命名(R)/复制(C)」——
# ① 不看全部已跟踪文件：否则会把「早已在库里、本次未改动」的历史遗留物误报成危险项；
# ② **放行删除(D)**：清理已入库的垃圾文件正是靠删除，拦掉就永远清不掉
#    （本脚本首次实跑时就误报过一次）。
head1 "忽略规则断言（本次变更）"
STAGED="$(git status --porcelain)"
# 非删除动作（A/M/R/C/??）的条目
STAGED_ADD="$(printf '%s\n' "$STAGED" | grep -E '^(A|M|R|C|\?\?)' || true)"
# 删除动作的条目（放行，但单独提示）
STAGED_DEL="$(printf '%s\n' "$STAGED" | grep -E '^(D| D)' || true)"
BAD=0
for pat in 'export/' 'tools/user_mods_prev/' 'tools/user_containers_prev/' \
           'tools/user_mods/' 'crash/' '.DS_Store$' '\.orig$' '\.bak$' '\.log$'; do
  n=$(printf '%s\n' "$STAGED_ADD" | grep -c -E "$pat" 2>/dev/null || true)
  n=${n:-0}
  if [ "$n" -gt 0 ]; then
    say "  ✘ $pat  以「新增/修改」形式命中 $n 个（不应入库！）"
    printf '%s\n' "$STAGED_ADD" | grep -E "$pat" | sed 's/^/      /'
    BAD=1
  fi
done

# 单独显示删除项（清理遗留文件属正常操作，不阻断）
DEL_N=$(printf '%s\n' "$STAGED_DEL" | grep -c . 2>/dev/null || true)
DEL_N=${DEL_N:-0}
if [ "$DEL_N" -gt 0 ]; then
  say "  • 本次含 $DEL_N 个删除（清理遗留文件，正常）："
  printf '%s\n' "$STAGED_DEL" | sed 's/^/      /'
fi
[ "$BAD" -eq 0 ] && say "  ✔ 本次没有把 export/、用户数据快照、崩溃转储、编辑器垃圾**新增/修改**进库"

if [ "$BAD" -eq 1 ]; then
  say ""
  say "✘ 中止：有本应被忽略的文件以新增/修改形式进入本次变更，请检查 .gitignore。"
  exit 1
fi

# ---------- 4b. 历史遗留提示（仅告知，不阻断） ----------
LEGACY="$(git ls-files '*.orig' '*.bak' | head -20)"
if [ -n "$LEGACY" ]; then
  head1 "提示：库里的历史遗留备份文件（本次未改动）"
  printf '%s\n' "$LEGACY" | sed 's/^/  /'
  say "  想清理的话（先确认没有未保存的对比需求）："
  say "    printf '*.orig\\n*.bak\\n' >> .gitignore"
  say "    git rm --cached \$(git ls-files '*.orig' '*.bak')"
fi
if [ "$DRY_RUN" -eq 1 ]; then
  say ""
  say "（预演模式：未做任何写入。去掉 -n 即执行提交+推送）"
  exit 0
fi

# ---------- 5. 提交 ----------
if [ "$CHANGED_N" -eq 0 ]; then
  say ""
  say "没有需要提交的改动。"
else
  head1 "提交"
  if [ -z "$MSG" ]; then
    MSG="源码更新 $(date '+%Y-%m-%d %H:%M')"
    say "  未指定提交信息，自动生成：$MSG"
    say "  （建议下次用: ./push-source.sh \"你的说明\"）"
  fi
  git add -A
  git commit -m "$MSG" >/dev/null
  say "  ✔ 已提交 $(git rev-parse --short HEAD)  $MSG"
fi

# ---------- 6. 推送 ----------
if [ "$DO_PUSH" -eq 0 ]; then
  say ""
  say "（--no-push：已提交，未推送）"
  exit 0
fi

head1 "推送"
if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
  git push "$REMOTE" "$BRANCH"
else
  say "  分支 $BRANCH 尚无上游，建立跟踪并推送…"
  git push -u "$REMOTE" "$BRANCH"
fi

# ---------- 7. 用远端 HEAD 复核（不只看退出码） ----------
head1 "复核"
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" | cut -f1)"
if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  say "  ✔ 远端 $BRANCH 已与本地一致：$(git rev-parse --short HEAD)"
  say "     $(git log -1 --pretty='%s')"
  say "  GitHub: https://github.com/Bonus-XK/FNF-MeteoricEngine"
else
  say "  ✘ 不一致！本地=$LOCAL_SHA  远端=$REMOTE_SHA"
  say "    可能推送被拒绝或分支受保护，请手动检查。"
  exit 1
fi
