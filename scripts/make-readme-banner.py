#!/usr/bin/env python3
"""README の頭に置く絵（docs/images/banner-light.svg と banner-dark.svg）を作る。

字はすべて輪郭（path）にして埋めるので、見る人の手元の書体に左右されない。
書体は npm の @fontsource/noto-sans-jp と @fontsource/inter（どちらも OFL）。

    npm pack @fontsource/noto-sans-jp @fontsource/inter
    mkdir -p fonts && for f in fontsource-*.tgz; do tar xzf "$f" -C fonts --strip-components=2 package/files; done
    pip install fonttools brotli
    python3 scripts/make-readme-banner.py fonts docs/images
"""
import glob
import os
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

fonts_dir, out_dir = sys.argv[1], sys.argv[2]

_cache = {}


def faces(pattern):
    """woff2 の分け持ち（unicode-range ごとのファイル）をまとめて読む"""
    if pattern not in _cache:
        _cache[pattern] = [TTFont(p) for p in sorted(glob.glob(os.path.join(fonts_dir, pattern)))]
    return _cache[pattern]


def text_path(text, pattern, size, x, y, anchor="start", tracking=0.0):
    """文字列を path の d にする。x, y は基線の位置。幅も返す"""
    pieces = []
    for ch in text:
        for font in faces(pattern):
            name = font.getBestCmap().get(ord(ch))
            if name:
                pieces.append((font, name))
                break
        else:
            raise SystemExit(f"字が見つからない: {ch!r} ({pattern})")
    scale_of = lambda f: size / f["head"].unitsPerEm
    widths = [f["hmtx"][n][0] * scale_of(f) + tracking * size for f, n in pieces]
    total = sum(widths) - (tracking * size if pieces else 0)
    cursor = x - (total / 2 if anchor == "middle" else total if anchor == "end" else 0)
    d = []
    for (font, name), w in zip(pieces, widths):
        s = scale_of(font)
        pen = SVGPathPen(font.getGlyphSet(), ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
        font.getGlyphSet()[name].draw(TransformPen(pen, (s, 0, 0, -s, cursor, y)))
        d.append(pen.getCommands())
        cursor += w
    return " ".join(d), total


def rounded(v):
    return f"{v:.1f}"


# 色は Palette.swift の「朱」の組と同じ。アイコンの板はアプリと同じく、どちらの見た目でも紙のまま
TONES = {
    "light": dict(ground="#F4F2EC", ink="#1E1C19", quiet="#6B675F", rule="#E5E1D7", accent="#C23B12", shadow=0.16),
    "dark": dict(ground="#141311", ink="#EEEAE2", quiet="#A29D93", rule="#34312C", accent="#F0663C", shadow=0.55),
}
ICON = dict(top="#FCFBF8", bottom="#F4F2EC", rule="#E5E1D7", ink="#1E1C19", accent="#C23B12")

W, H = 1280, 400

# アイコン。make-app-icon.swift の 1024 画布の割り付けを、240 四方の板に写す
plate, px, py = 240, 120, 80
radius = plate * 185 / 824
so_d, so_w = text_path("そ", "noto-sans-jp-*-500-normal.woff2", plate * 0.60, 0, 0)
# 字の形の外枠を測って、板の 56%（上から 44%）の高さに真ん中を合わせる
_font = next(f for f in faces("noto-sans-jp-*-500-normal.woff2") if 0x305D in f.getBestCmap())
from fontTools.pens.boundsPen import BoundsPen
bp = BoundsPen(_font.getGlyphSet())
_font.getGlyphSet()[_font.getBestCmap()[0x305D]].draw(bp)
s = plate * 0.60 / _font["head"].unitsPerEm
xmin, ymin, xmax, ymax = (v * s for v in bp.bounds)
glyph_h = ymax - ymin
# 字の形の高さを板の 46% にそろえ直す
size = plate * 0.60 * (plate * 0.46) / glyph_h
s = size / _font["head"].unitsPerEm
xmin, ymin, xmax, ymax = (v * s for v in bp.bounds)
cx, cy = px + plate / 2, py + plate * 0.44
so_x = cx - (xmin + xmax) / 2
so_y = cy + (ymin + ymax) / 2
so_d, _ = text_path("そ", "noto-sans-jp-*-500-normal.woff2", size, so_x, so_y)
glyph_w, glyph_h = xmax - xmin, ymax - ymin
line_w = max(plate * 0.44, glyph_w * 1.1)
line_t = plate * 32 / 824
line_y = cy + glyph_h / 2 + plate * 0.085

# 名前と一行の説明
tx = 432
word_d, word_w = text_path("sokkou", "inter-latin-700-normal.woff2", 104, tx, 184, tracking=-0.02)
kanji_d, kanji_w = text_path("即効", "noto-sans-jp-*-500-normal.woff2", 52, tx + word_w + 28, 184)
tag_d, _ = text_path("SKK の手触りで、打てばそのまま変換される日本語入力", "noto-sans-jp-*-400-normal.woff2", 30, tx, 260)
sub_d, _ = text_path("Japanese input for macOS — SKK feel, converts as you type", "inter-latin-400-normal.woff2", 21, tx, 304)

for mode, t in TONES.items():
    k_x = tx + word_w + 28
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="sokkou（即効） SKK の手触りで、打てばそのまま変換される日本語入力">
  <defs>
    <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{ICON['top']}"/>
      <stop offset="1" stop-color="{ICON['bottom']}"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="{rounded(plate * 10 / 824 * 1.6)}" stdDeviation="{rounded(plate * 18 / 824 * 1.4)}" flood-color="#000" flood-opacity="{t['shadow']}"/>
    </filter>
  </defs>
  <rect width="{W}" height="{H}" rx="28" fill="{t['ground']}"/>
  <rect x="0.5" y="0.5" width="{W - 1}" height="{H - 1}" rx="27.5" fill="none" stroke="{t['rule']}"/>
  <g filter="url(#shadow)">
    <rect x="{px}" y="{py}" width="{plate}" height="{plate}" rx="{rounded(radius)}" fill="url(#paper)"/>
  </g>
  <rect x="{px + 0.6}" y="{py + 0.6}" width="{plate - 1.2}" height="{plate - 1.2}" rx="{rounded(radius - 0.6)}" fill="none" stroke="{ICON['rule']}" stroke-width="1.2"/>
  <path d="{so_d}" fill="{ICON['ink']}"/>
  <rect x="{rounded(cx - line_w / 2)}" y="{rounded(line_y)}" width="{rounded(line_w)}" height="{rounded(line_t)}" rx="{rounded(line_t / 2)}" fill="{ICON['accent']}"/>
  <path d="{word_d}" fill="{t['ink']}"/>
  <path d="{kanji_d}" fill="{t['ink']}"/>
  <!-- 英語の区間は点線、日本語の文節は朱の実線（sokkou の下線と同じ） -->
  <line x1="{tx + 4}" y1="210" x2="{rounded(tx + word_w - 2)}" y2="210" stroke="{t['quiet']}" stroke-width="3" stroke-linecap="round" stroke-dasharray="0.1 10"/>
  <rect x="{rounded(k_x)}" y="207" width="{rounded(kanji_w)}" height="6" rx="3" fill="{t['accent']}"/>
  <path d="{tag_d}" fill="{t['ink']}"/>
  <path d="{sub_d}" fill="{t['quiet']}"/>
</svg>
"""
    path = os.path.join(out_dir, f"banner-{mode}.svg")
    with open(path, "w") as f:
        f.write(svg)
    print(path, len(svg))
