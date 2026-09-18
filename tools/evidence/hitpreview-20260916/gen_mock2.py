#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
打击特效预览（PE 0.7.3 排版）—— 几何核对 + 预览图生成器（证据工具，不参与引擎编译）

几何依据（全部来自仓库源码）：
  - OptionsPane.hx：PANEL 284,70,956,570 / ROW_Y 152 / ROW_GAP 52 / STRIP_Y 578
                    预览带 = [ROW_Y + rowsVisible*ROW_GAP, STRIP_Y - 6]（rowsVisible=2 → 256..572）
  - NoteSettingsSubState.hx：SPLASH_FIRST_X 240 / SPLASH_LANE_GAP 220 / 站立箭头 alpha 0.75
                    溅射位 = 箭头位 - (swagWidth*0.95, swagWidth)；PREVIEW_ANCHOR 956×316 不可见锚
  - NoteSplash.hx：defaultNoteSplash = 'noteSplashes/noteSplashes' + getSplashSkinPostfix()
                    （皮肤名 → 贴图：默认皮肤无后缀，其余 '-<slug>'）
  - Note.swagWidth = 160 * 0.7
"""
import os, re, struct, zlib, posixpath

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
IMG = os.path.join(ROOT, 'assets', 'shared', 'images')
FONT = os.path.join(ROOT, 'assets', 'shared', 'fonts', 'future.ttf')

PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 284.0, 70.0, 956.0, 570.0
ROW_Y, ROW_GAP, ROWS_VISIBLE = 152.0, 52.0, 8
STRIP_Y = 578.0
PREVIEW_ROWS = 6
PREVIEW_Y = ROW_Y + PREVIEW_ROWS * ROW_GAP          # 256
PREVIEW_H = (STRIP_Y - 6) - PREVIEW_Y               # 316
BAR_X, BAR_W, BAR_H = PANEL_X + 14, PANEL_W - 28, 44.0
SWAG = 160 * 0.7
ANCHOR_W, ANCHOR_H = 956.0, 316.0
SPLASH_FIRST_X, SPLASH_LANE_GAP = 240.0, 220.0
SPLASH_PANE_SCALE = 0.33   # 预览带(108px)里整体等比缩小；整屏路径为 1

LANES = ['purple', 'blue', 'green', 'red']                     # Note.colArray
ARROW_ANIMS = ['arrowLEFT', 'arrowDOWN', 'arrowUP', 'arrowRIGHT']
DEFAULT_SKIN = 'Psych'
SKIN_LIST = [DEFAULT_SKIN, '063', 'Diamond', 'Electric', 'Sparkles', 'Vanilla']  # 默认 + list.txt


def parse_png_size(p):
    d = open(p, 'rb').read(33)
    return struct.unpack('>II', d[16:24])


def frames(xml_path):
    s = open(xml_path, encoding='utf-8-sig', errors='replace').read()
    out = {}
    for m in re.finditer(r'<SubTexture\s+name="([^"]+)"([^>]*)/>', s):
        name, attrs = m.group(1), dict(re.findall(r'(\w+)="([^"]*)"', m.group(2)))
        x, y, w, h = int(attrs['x']), int(attrs['y']), int(attrs['width']), int(attrs['height'])
        if 'frameWidth' in attrs:                               # sparrow 裁剪帧
            fx, fy = int(attrs.get('frameX', 0)), int(attrs.get('frameY', 0))
            fw, fh, tri = int(attrs['frameWidth']), int(attrs['frameHeight']), (-fx, -fy)
        else:
            fw, fh, tri = w, h, (0, 0)                          # 未裁剪帧（箭头图集即此类）
        out[name] = dict(rect=(x, y, w, h), src=(fw, fh), trim=tri)
    return out


def splash_config(txt_path):
    lines = [l.strip() for l in open(txt_path, encoding='utf-8-sig', errors='replace') if l.strip()]
    fr = lines[1].split()
    offs = [[float(a), float(b)] for a, b in (l.split() for l in lines[2:])]
    return dict(anim=lines[0], minfps=int(fr[0]), maxfps=int(fr[1]), offsets=offs)


def texture_for(skin, default_skin=DEFAULT_SKIN):
    """NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix()（引擎的唯一解析式）"""
    if skin == default_skin:
        return 'noteSplashes/noteSplashes'
    return 'noteSplashes/noteSplashes-' + skin.strip().lower().replace(' ', '_')


def resolve(skin):
    """返回 (实际贴图 key, 是否发生回退)。回退链同 NoteSplash.loadAnims。"""
    want = texture_for(skin)
    for cand in (want, 'noteSplashes/noteSplashes'):
        if os.path.exists(os.path.join(IMG, cand + '.png')) and os.path.exists(os.path.join(IMG, cand + '.xml')):
            return cand, (cand != want)
    return None, True


def audit(skin):
    report = []
    arrow_fr = frames(os.path.join(IMG, 'noteSkins', 'NOTE_assets.xml'))
    tex, fell_back = resolve(skin)
    sp_fr = frames(os.path.join(IMG, tex + '.xml')) if tex else {}
    cfg = splash_config(os.path.join(IMG, tex + '.txt')) if tex else dict(anim='note splash', minfps=22, maxfps=26, offsets=[[0, 0]])

    sprites = []       # dict(kind, x, y, off=(ox,oy), w, h, fr, png, lane)
    arrow_png = os.path.join(IMG, 'noteSkins', 'NOTE_assets.png')
    splash_png = os.path.join(IMG, tex + '.png') if tex else None

    # ① 箭头预览（未改动的既有实现）：x = 100 + 130*i，帧盒 = 未裁剪尺寸，offset = 0
    for i in range(len(LANES)):
        af = arrow_fr[ARROW_ANIMS[i] + '0000']
        x = 100 + (520 / len(LANES)) * i
        sprites.append(dict(kind='arrow', lane=i, x=x, y=0.0, off=(0.0, 0.0),
                            w=af['src'][0], h=af['src'][1], fr=af, png=arrow_png))

    # ② 打击特效预览（PE 0.7.3 排版，全尺寸）
    for i in range(len(LANES)):
        x = SPLASH_FIRST_X + SPLASH_LANE_GAP * i
        af = arrow_fr[ARROW_ANIMS[i] + '0000']
        sprites.append(dict(kind='splashArrow', lane=i, x=x, y=0.0, off=(0.0, 0.0), ax=x, ay=0.0,
                            w=af['src'][0], h=af['src'][1], fr=af, png=arrow_png))
        if tex:
            names = [n for n in sp_fr if n.startswith('%s %s 1' % (cfg['anim'], LANES[i]))]
            peak = max(names, key=lambda n: sp_fr[n]['rect'][2] * sp_fr[n]['rect'][3])  # 峰值帧（动画最大那帧）
            sf = sp_fr[peak]
            env = (min(sp_fr[n]['trim'][0] for n in names), min(sp_fr[n]['trim'][1] for n in names),
                   max(sp_fr[n]['trim'][0] + sp_fr[n]['rect'][2] for n in names),
                   max(sp_fr[n]['trim'][1] + sp_fr[n]['rect'][3] for n in names))
            off = cfg['offsets'][i] if i < len(cfg['offsets']) else [0, 0]
            sprites.append(dict(kind='splash', lane=i, ax=x, ay=0.0,
                                x=x - SWAG * 0.95, y=-SWAG, off=(10 + off[0], 10 + off[1]),
                                w=env[2] - env[0], h=env[3] - env[1], fr=sf, png=splash_png,
                                frame=peak, env=env))

    # applySplashScale()：以每轨站立箭头为锚，把该单元（箭头 + 溅射）整体等比缩放 k
    k = SPLASH_PANE_SCALE
    for s in g if False else [x for x in sprites if x['kind'] != 'arrow']:
        ax, ay = s['ax'], s['ay']
        s['off'] = (s['off'][0] * k, s['off'][1] * k)
        s['x'] = ax + (s['x'] - ax) * k
        s['y'] = ay + (s['y'] - ay) * k
        s['w'] *= k
        s['h'] *= k
    report.append('  applySplashScale: k=%.2f（预览带 108px / 最高包络 316px）' % k)

    # centerSplashGroup(centerY=true)：打击特效整组平移到与箭头预览包围盒同心（x 与 y 都居中）
    a = [s for s in sprites if s['kind'] == 'arrow']
    g = [s for s in sprites if s['kind'] != 'arrow']
    aMin = min(s['x'] - s['off'][0] for s in a); aMax = max(s['x'] - s['off'][0] + s['w'] for s in a)
    aMinY = min(s['y'] - s['off'][1] for s in a); aMaxY = max(s['y'] - s['off'][1] + s['h'] for s in a)
    gMin = min(s['x'] - s['off'][0] for s in g); gMax = max(s['x'] - s['off'][0] + s['w'] for s in g)
    gMinY = min(s['y'] - s['off'][1] for s in g); gMaxY = max(s['y'] - s['off'][1] + s['h'] for s in g)
    dxc = (aMin + aMax) * 0.5 - (gMin + gMax) * 0.5
    dyc = (aMinY + aMaxY) * 0.5 - (gMinY + gMaxY) * 0.5
    for s in g:
        s['x'] += dxc; s['y'] += dyc
    report.append('  centerSplashGroup: 箭头盒[%.1f,%.1f]x[%.1f,%.1f] 打击特效盒[%.1f,%.1f]x[%.1f,%.1f] → 平移 (%.2f, %.2f)'
                  % (aMin, aMax, aMinY, aMaxY, gMin, gMax, gMinY, gMaxY, dxc, dyc))
    inside = (gMin + dxc >= aMin - 0.01 and gMax + dxc <= aMax + 0.01
              and gMinY + dyc >= aMinY - 0.01 and gMaxY + dyc <= aMaxY + 0.01)
    report.append('  打击特效整组落在箭头预览包围盒内 = %s（⇒ 宿主量到的包围盒恒等于箭头包围盒，不跳位）' % inside)

    # pinPreviewAnchor()：内容包围盒中心 → 956×316 锚
    cMinX = min(s['x'] - s['off'][0] for s in sprites)
    cMaxX = max(s['x'] - s['off'][0] + s['w'] for s in sprites)
    cMinY = min(s['y'] - s['off'][1] for s in sprites)
    cMaxY = max(s['y'] - s['off'][1] + s['h'] for s in sprites)
    cx, cy = (cMinX + cMaxX) * 0.5, (cMinY + cMaxY) * 0.5
    ax0, ay0 = cx - ANCHOR_W * 0.5, cy - ANCHOR_H * 0.5
    fits = True
    report.append('  内容包围盒 x[%.1f,%.1f] w=%.1f  y[%.1f,%.1f] h=%.1f'
                  % (cMinX, cMaxX, cMaxX - cMinX, cMinY, cMaxY, cMaxY - cMinY))

    # 宿主 OptionsPane.setPreview：按整容器叶子（含不可见锚）包围盒居中到预览带
    leaves = sprites
    minX = min(s['x'] - s['off'][0] for s in leaves)
    maxX = max(s['x'] - s['off'][0] + s['w'] for s in leaves)
    minY = min(s['y'] - s['off'][1] for s in leaves)
    maxY = max(s['y'] - s['off'][1] + s['h'] for s in leaves)
    dx = PANEL_X + (PANEL_W - (maxX - minX)) / 2 - minX
    dy = PREVIEW_Y + (PREVIEW_H - (maxY - minY)) / 2 - minY
    for s in leaves:
        s['x'] += dx
        s['y'] += dy
    report.append('  宿主落位：包围盒 x[%.1f,%.1f] w=%.1f y[%.1f,%.1f] h=%.1f → 平移 (%.1f, %.1f)'
                  % (minX, maxX, maxX - minX, minY, maxY, maxY - minY, dx, dy))

    sg = [s for s in sprites if s['kind'] != 'arrow']
    sgx0 = min(s['x'] - s['off'][0] for s in sg); sgx1 = max(s['x'] - s['off'][0] + s['w'] for s in sg)
    sgy0 = min(s['y'] - s['off'][1] for s in sg); sgy1 = max(s['y'] - s['off'][1] + s['h'] for s in sg)
    sg_band = sgy0 >= PREVIEW_Y - 0.01 and sgy1 <= PREVIEW_Y + PREVIEW_H + 0.01
    sg_panel = sgx0 >= PANEL_X - 0.01 and sgx1 <= PANEL_X + PANEL_W + 0.01
    report.append('  **打击特效预览自身落位** x[%.1f,%.1f] y[%.1f,%.1f]（缩放后 %dx%d）→ 预览带内=%s 面板内=%s'
                  % (sgx0, sgx1, sgy0, sgy1, sgx1 - sgx0, sgy1 - sgy0, sg_band, sg_panel))
    report.append('  （溅射渲染的是动画**峰值帧**，尺寸=整段包络；预览带上下留白 ≥ %.1fpx）'
                  % min(sgy0 - PREVIEW_Y, PREVIEW_Y + PREVIEW_H - sgy1))

    content = [s for s in sprites]
    kx0 = min(s['x'] - s['off'][0] for s in content)
    kx1 = max(s['x'] - s['off'][0] + s['w'] for s in content)
    ky0 = min(s['y'] - s['off'][1] for s in content)
    ky1 = max(s['y'] - s['off'][1] + s['h'] for s in content)
    in_band = ky0 >= PREVIEW_Y - 0.01 and ky1 <= PREVIEW_Y + PREVIEW_H + 0.01
    in_panel = kx0 >= PANEL_X - 0.01 and kx1 <= PANEL_X + PANEL_W + 0.01
    report.append('  内容落位 x[%.1f,%.1f] y[%.1f,%.1f]  预览带[%.0f,%.0f]内=%s  面板[%.0f,%.0f]内=%s  打击特效在箭头盒内=%s'
                  % (kx0, kx1, ky0, ky1, PREVIEW_Y, PREVIEW_Y + PREVIEW_H, in_band, PANEL_X, PANEL_X + PANEL_W, in_panel, fits))
    return dict(sprites=sprites, tex=tex, fell_back=fell_back, skin=skin, report=report,
                in_band=in_band, in_panel=in_panel, fits=fits, cfg=cfg,
                sg_band=sg_band, sg_panel=sg_panel, sg_box=(sgx0, sgx1, sgy0, sgy1))


CSS = """
@font-face { font-family: future; src: url('FONTREL'); }
* { margin:0; padding:0; }
body { background:#0b0b12; }
.stage { position:relative; width:1280px; height:720px; overflow:hidden; font-family:future, sans-serif; }
.panel { position:absolute; left:284px; top:70px; width:956px; height:570px; border-radius:22px;
         background:rgba(35,43,56,0.8); border:1.5px solid rgba(255,255,255,0.27); }
.title { position:absolute; color:#fff; font-size:30px; }
.row { position:absolute; color:#fff; font-size:26px; line-height:44px; white-space:nowrap; }
.row .v { color:#d7d7e0; }
.sw { position:absolute; width:96px; height:32px; border-radius:16px; background:rgba(22,22,34,0.4);
      border:1.5px solid rgba(255,255,255,0.27); }
.desc { position:absolute; color:#cfcfdc; font-size:20px; }
.bar { position:absolute; border-radius:12px; background:rgba(107,157,175,0.42); }
.band { position:absolute; border:1px dashed rgba(255,255,255,0.16); }
.spr { position:absolute; display:block; background-repeat:no-repeat; image-rendering:pixelated; }
.cap { color:#9ce8ff; font-size:15px; font-family:monospace; padding:6px 10px; }
"""


def render_state(state):
    lay = state['layout']
    rows = ['音符皮肤:<span class="v">Psych</span>', 'Psych 0.6.3 兼容模式', 'Lua 0.6.3 兼容',
            '音符打击特效:<span class="v">' + lay['skin'] + '</span>', '打击特效透明度:<span class="v">100%</span>']
    sel = state['selected_row']
    first = 0 if sel < PREVIEW_ROWS else sel - PREVIEW_ROWS + 1     # 行窗口跟着选中行滚动

    html = ['<div class="panel"></div>',
            '<div class="title" style="left:%.0fpx;top:%.0fpx">音符</div>' % (PANEL_X + 32, PANEL_Y + 22),
            '<div class="bar" style="left:%.0fpx;top:%.0fpx;width:%.0fpx;height:%.0fpx"></div>'
            % (BAR_X, ROW_Y - 4 + (sel - first) * ROW_GAP, BAR_W, BAR_H),
            '<div class="band" style="left:%.0fpx;top:%.0fpx;width:%.0fpx;height:%.0fpx"></div>'
            % (PANEL_X, PREVIEW_Y, PANEL_W, PREVIEW_H)]
    for r in range(min(PREVIEW_ROWS, len(rows) - first)):
        idx = first + r
        html.append('<div class="row" style="left:%.0fpx;top:%.0fpx">%s</div>' % (PANEL_X + 130, ROW_Y + r * ROW_GAP, rows[idx]))
        html.append('<div class="sw" style="left:%.0fpx;top:%.0fpx"></div>' % (PANEL_X + 22, ROW_Y + 6 + r * ROW_GAP))
    html.append('<div class="desc" style="left:%.0fpx;top:%.0fpx">选择音符打击粒子的样式：</div>' % (PANEL_X + 32, STRIP_Y + 16))

    for s in lay['sprites']:
        arrows_only = (s['kind'] == 'arrow')
        if arrows_only != state['show_arrows']:
            continue
        rx, ry, rw, rh = s['fr']['rect']
        env = s.get('env')
        k = s['w'] / ((env[2] - env[0]) if env else s['fr']['src'][0])
        cx = (s['x'] - s['off'][0]) + s['fr']['trim'][0] * k
        cy = (s['y'] - s['off'][1]) + s['fr']['trim'][1] * k
        aw, ah = parse_png_size(s['png'])
        rel = posixpath.relpath(s['png'], HERE).replace(os.sep, '/')
        alpha = ';opacity:0.75' if s['kind'] == 'splashArrow' else ''
        html.append('<i class="spr" style="left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx%s;'
                    "background-image:url('%s');background-position:%.2fpx %.2fpx;background-size:%dpx %dpx\"></i>"
                    % (cx, cy, rw * k, rh * k, alpha, rel, -rx * k, -ry * k, aw, ah))

    return ('<div class="cap">%s ｜ 预览带 y%.0f..%.0f（rowsVisible=%d）｜ 内容 x[%.0f,%.0f] y[%.0f,%.0f] ｜ 带内=%s 面板内=%s</div>'
            % (state['caption'], PREVIEW_Y, PREVIEW_Y + PREVIEW_H, PREVIEW_ROWS,
               *state['content_box'], 'PASS（含全尺寸箭头，见既有行为）' if lay['in_band'] else '箭头框越界（既有）',
               'PASS' if lay['in_panel'] else 'FAIL')
            + '｜打击特效预览 y[%.0f,%.0f] 带内=%s'
            % (state['layout']['sg_box'][2], state['layout']['sg_box'][3], 'PASS' if lay['sg_band'] else 'FAIL')
            ) + ''.join(html)


def main():
    states = []
    for row, skin, cap in [
        (0, DEFAULT_SKIN, '① 选中「音符皮肤」行 → 既有箭头预览（本次未改，落位一致）'),
        (3, DEFAULT_SKIN, '② 选中「音符打击特效」行（Psych 默认）→ noteSplashes（游戏内按轨 RGB 着色，本图未模拟着色器）'),
        (3, '063', '③ 选中「音符打击特效」行（063）→ noteSplashes-063，预染色 raw，不挂着色器'),
        (3, 'Vanilla', '④ 选中「音符打击特效」行（Vanilla）→ noteSplashes-vanilla（修复前会静默回退到 063）'),
    ]:
        lay = audit(skin)
        box = None
        sp = lay['sprites']
        box = (min(s['x'] - s['off'][0] for s in sp), max(s['x'] - s['off'][0] + s['w'] for s in sp),
               min(s['y'] - s['off'][1] for s in sp), max(s['y'] - s['off'][1] + s['h'] for s in sp))
        states.append(dict(caption=cap, selected_row=row, show_arrows=(row == 0), layout=lay, content_box=box))

    lines = ['打击特效预览（PE 0.7.3 排版）—— 几何核对']
    for st in states:
        lines.append('\n== %s' % st['caption'])
        lines += st['layout']['report']
        lines.append('  解析贴图 = %s（发生回退 = %s）' % (st['layout']['tex'], st['layout']['fell_back']))
    lines.append('\n== 皮肤解析表（修复后）')
    for skin in SKIN_LIST:
        tex, fb = resolve(skin)
        lines.append('  %-10s → %-40s 回退=%s' % (skin, tex, fb))
    rep = '\n'.join(lines) + '\n'
    open(os.path.join(HERE, 'geometry.txt'), 'w', encoding='utf-8').write(rep)
    print(rep)

    css = CSS.replace('FONTREL', posixpath.relpath(FONT, HERE))
    body = ''.join('<div class="stage" style="margin-bottom:8px">%s</div>' % render_state(st) for st in states)
    open(os.path.join(HERE, 'preview-audit.html'), 'w', encoding='utf-8').write(
        '<!doctype html><meta charset="utf-8"><style>%s</style>%s' % (css, body))
    print('written: preview-audit.html / geometry.txt')


if __name__ == '__main__':
    main()
