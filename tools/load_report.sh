#!/bin/zsh
# 进曲加载时间账：从 /tmp/meteoric_debug.log 提取 LoadingState / PlayState / 图片解码打点，
# 输出分段耗时与总计。纯读日志，不碰游戏。
#
# 用法：tools/load_report.sh [日志路径]   （默认 /tmp/meteoric_debug.log）

LOG="${1:-/tmp/meteoric_debug.log}"
[ -f "$LOG" ] || { echo "日志不存在: $LOG"; exit 1; }

python3 - "$LOG" <<'PY'
import re, sys

log = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()

def grab(pattern):
    """取 (毫秒时间戳, 负载) —— 打点格式 '[LOAD+12345] xxx' / '[IMG+12345] ...'"""
    out = []
    for line in log:
        m = re.search(r'\[(?:LOAD|IMG|PLAY)\+?(\d+)\]\s*(.*)', line)
        if not m:
            m = re.search(r'\[PLAY create\]\s*(\d+)\s*ms', line)
            if m:
                out.append((int(m.group(1)), '__playcreate__'))
            continue
        out.append((int(m.group(1)), m.group(2).strip()))
    return out

pts = grab('')

# --- 分段：相邻打点之间的耗时 ---
print('=== 打点时间线 ===')
prev = None
for ts, what in pts:
    d = '' if prev is None else f'(+{ts-prev}ms)'
    what = re.sub(r'\s+', ' ', what)[:110]
    print(f'{ts:>7}ms {d:>10}  {what}')
    prev = ts

# --- 图片解码单独汇总 ---
img = [(ts, w) for ts, w in pts if w.startswith('decode ')]
if img:
    print('\n=== BitmapData.fromFile 单张耗时 ===')
    total = 0
    for ts, w in img:
        m = re.match(r'decode (\d+)ms (.*?) -> (\d+) left', w)
        if not m:
            continue
        ms, path, left = int(m.group(1)), m.group(2), m.group(3)
        total += ms
        name = path.rsplit('/', 1)[-1]
        print(f'{ms:>6}ms  剩余队列 {left:>2}  {name}')
    print(f'{"合计":>6}ms  {total}ms  共 {len(img)} 张')

# --- 总账：LoadingState.create → PlayState create end ---
def find_ts(pred):
    for ts, w in pts:
        if pred(w):
            return ts
    return None

start = find_ts(lambda w: 'create start' in w)
gcn   = find_ts(lambda w: w.startswith('cachedEventsMakeEvent'))
end   = find_ts(lambda w: w == 'end')

if start and end:
    print(f'\n=== 总账 ===')
    print(f'LoadingState.create 起点 {start}ms')
    print(f'PlayState create 结束 {end}ms')
    print(f'净加载耗时          {end-start}ms  （不含倒计时）')
if gcn:
    print(f'makeEvent           {gcn}ms')
PY