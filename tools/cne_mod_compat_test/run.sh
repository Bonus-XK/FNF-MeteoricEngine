#!/bin/sh
# CNE 模组兼容层 · 算法级实跑测试
#
# 用法：tools/cne_mod_compat_test/run.sh
# 输出：tools/cne_mod_compat_test/out/{chart_convert.log,mod_compat.log}
# 退出码：两个测试都全过 = 0
#
# 做法：把**仓库真实源码**逐字节复制进 /tmp 的临时工程，只把 flixel / lime / backend
# 依赖替换为字段与语义一致的测试替身，再 `haxe --interp` 直接执行真实代码。
# 这样在「没有 CNE 样本 mod、且不启动游戏」的前提下，仍能对转换规则与 zip 暂存做可复核断言。
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tools/cne_mod_compat_test/out"
STUBS="$ROOT/tools/cne_mod_compat_test/stubs"
STAGE="/tmp/cne_mod_compat_test"
# CNE 源码快照（含官方 base 谱面，用于真实数据断言）；可用环境变量覆盖
CNE_SRC="${CNE_SRC:-$HOME/Documents/CodenameEngine-main}"

rm -rf "$STAGE"
mkdir -p "$STAGE/chart/states/editors/content" "$STAGE/mod/cne" "$OUT"

# ---------- A) CNE 谱面 → psych_v1（真实 CneExport.cneToPsych） ----------
cp -R "$STUBS/chart/." "$STAGE/chart/"
cp "$ROOT/source/states/editors/content/CneExport.hx" "$STAGE/chart/states/editors/content/CneExport.hx"
echo "[A] CNE chart → psych_v1 ..."
(cd "$STAGE/chart" && CNE_SRC_ROOT="$CNE_SRC" haxe -cp . -main Test --interp) > "$OUT/chart_convert.log" 2>&1 || true
tail -3 "$OUT/chart_convert.log"

# ---------- B) CNE mod 兼容层（真实 CneModCompat + CneZipStore + ZipReader） ----------
cp -R "$STUBS/mod/." "$STAGE/mod/"
cp "$ROOT/source/cne/CneModCompat.hx" "$ROOT/source/cne/CneZipStore.hx" "$STAGE/mod/cne/"
cp "$ROOT/source/backend/ZipReader.hx" "$STAGE/mod/backend/ZipReader.hx"
echo "[B] CNE mod compat (character/week/chart/audio/zip) ..."
(cd "$STAGE/mod" && CNE_TEST_WORK="$STAGE/mod/" haxe -cp . -main Test2 --interp -D MODS_ALLOWED) > "$OUT/mod_compat.log" 2>&1 || true
tail -3 "$OUT/mod_compat.log"

[ -n "$CNE_SRC" ] && [ -d "$CNE_SRC" ] || { echo "RESULT: FAILED (CNE_SRC not found: $CNE_SRC)"; exit 1; }
FAILA=$(grep -c '^FAIL' "$OUT/chart_convert.log" || true)
FAILB=$(grep -c '^FAIL' "$OUT/mod_compat.log" || true)
PASSA=$(grep -c '^PASS' "$OUT/chart_convert.log" || true)
PASSB=$(grep -c '^PASS' "$OUT/mod_compat.log" || true)
echo "chart_convert: PASS=$PASSA FAIL=$FAILA ; mod_compat: PASS=$PASSB FAIL=$FAILB"
[ "$FAILA" = "0" ] && [ "$FAILB" = "0" ] && [ "$PASSA" -gt 20 ] && [ "$PASSB" -gt 20 ] \
  && echo "RESULT: ALL PASS" || { echo "RESULT: FAILED"; exit 1; }
