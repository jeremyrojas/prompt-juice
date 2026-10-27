"""Shared helpers for the PromptJuice logo builds.

Glyph outlines come from the FAMILY font (Fraunces, SIL OFL 1.1), read from the
film's own woff2 files, shaped with HarfBuzz (kerning on), cleaned with
skia-pathops (overlaps removed) and written out as plain SVG paths, so the
SVGs have no font dependency.

Needs: pip install fonttools brotli uharfbuzz skia-pathops
"""
import io
import math
import os

import pathops
import uharfbuzz as hb
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "fonts"))

# Brand palette
GROUND = "#07080b"
WHITE = "#ffffff"
GREEN = "#5FD11F"
GREEN_DK = "#3FA512"
GREEN_LT = "#8BE24E"
AMBER = "#F0A32A"
AMBER_DK = "#D9880F"
AMBER_LT = "#FFC15E"
CLAUDE = "#FF9F0A"
CODEX = "#32D4DE"

# Mascot PNG geometry (776 x 1115, fractions of width / height)
MASCOT_W, MASCOT_H = 776, 1115
MASCOT_ASPECT = MASCOT_W / MASCOT_H
MASCOT_FEET = 1030 / 1115  # where the opaque feet end; below is a soft contact shadow
MASCOT_WIDEST = 700 / 1115


def fmt(v):
    s = f"{v:.1f}"
    if s.endswith(".0"):
        s = s[:-2]
    return "0" if s == "-0" else s


# Font family used for all lettering (file prefix in assets/fonts). The film
# switched from Bricolage Grotesque to Fraunces; both are SIL OFL 1.1.
FAMILY = os.environ.get("PJ_FONT_FAMILY", "Fraunces")


class Font:
    def __init__(self, weight):
        self.weight = weight
        self.tt = TTFont(os.path.join(FONT_DIR, f"{FAMILY}-{weight}.woff2"))
        self.tt.flavor = None
        buf = io.BytesIO()
        self.tt.save(buf)
        self.hbfont = hb.Font(hb.Face(buf.getvalue()))
        self.gs = self.tt.getGlyphSet()
        self.order = self.tt.getGlyphOrder()
        self.upm = self.tt["head"].unitsPerEm
        os2 = self.tt["OS/2"]
        self.cap = os2.sCapHeight
        self.xh = os2.sxHeight

    def shape(self, text, tracking=0):
        """[(char, glyphname, x_units, advance_units)] with kerning applied."""
        buf = hb.Buffer()
        buf.add_str(text)
        buf.guess_segment_properties()
        hb.shape(self.hbfont, buf, {"kern": True, "liga": False})
        out, x = [], 0
        for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
            ch = text[info.cluster]
            out.append((ch, self.order[info.codepoint], x + pos.x_offset, pos.x_advance))
            x += pos.x_advance + tracking
        return out

    def width(self, text, tracking=0):
        g = self.shape(text, tracking)
        return g[-1][2] + g[-1][3]

    def path(self, glyph):
        """Decomposed, overlap-free outline in font units (y-up)."""
        rp = DecomposingRecordingPen(self.gs)
        self.gs[glyph].draw(rp)
        p = pathops.Path()
        rp.replay(p.getPen())
        p.simplify(fix_winding=True)
        return p


def split_contours(path):
    """Return a list of (pathops.Path, bounds) for each contour."""
    res = []
    for c in path.contours:
        p = pathops.Path()
        pen = p.getPen()
        c.draw(pen)
        res.append((p, p.bounds))
    return res


def union(*paths):
    return pathops.op(paths[0], _merge(paths[1:]), pathops.PathOp.UNION) if len(paths) > 1 else paths[0]


def _merge(paths):
    p = pathops.Path()
    for q in paths:
        q.draw(p.getPen())
    p.simplify(fix_winding=True)
    return p


def merge(paths):
    return _merge(paths)


def subtract(a, b):
    return pathops.op(a, b, pathops.PathOp.DIFFERENCE)


def to_d(path, scale, ox, oy):
    """pathops.Path in font units (y-up) -> SVG d in px (y-down), origin at (ox, oy) = baseline."""
    pen = SVGPathPen(None, ntos=fmt)
    path.draw(TransformPen(pen, (scale, 0, 0, -scale, ox, oy)))
    return pen.getCommands()


def path_from_svg_cmds(cmds):
    """Build a pathops.Path (font units, y-up) from a list like
    [('M', x, y), ('C', x1, y1, x2, y2, x, y), ('L', x, y), ('Z',)]"""
    p = pathops.Path()
    for c in cmds:
        op = c[0]
        if op == "M":
            p.moveTo(*c[1:])
        elif op == "L":
            p.lineTo(*c[1:])
        elif op == "C":
            p.cubicTo(*c[1:])
        elif op == "Q":
            p.quadTo(*c[1:])
        elif op == "Z":
            p.close()
    return p


# ---------------------------------------------------------------- droplet
# DropletGeometry.swift: unit square, y-down, clockwise from the tip.
DROP_TIP = (0.5, 0.1208)
DROP_SEGS = [
    ((0.5000, 0.1208), (0.2083, 0.4708), (0.2083, 0.6667)),
    ((0.2083, 0.8292), (0.3375, 0.9333), (0.5000, 0.9333)),
    ((0.6625, 0.9333), (0.7917, 0.8292), (0.7917, 0.6667)),
    ((0.7917, 0.4708), (0.5000, 0.1208), (0.5000, 0.1208)),
]
DROP_TOP, DROP_BOTTOM, DROP_HALFW = 0.1208, 0.9333, 0.7917 - 0.5


def droplet_d(cx, bottom, height):
    """Droplet path (SVG px, y-down) with its bulb bottom at `bottom` and visible height `height`."""
    s = height / (DROP_BOTTOM - DROP_TOP)
    ox, oy = cx - 0.5 * s, bottom - DROP_BOTTOM * s

    def P(pt):
        return f"{fmt(ox + pt[0] * s)} {fmt(oy + pt[1] * s)}"

    d = f"M{P(DROP_TIP)}"
    for c1, c2, e in DROP_SEGS:
        d += f"C{P(c1)} {P(c2)} {P(e)}"
    return d + "Z"


def droplet_units(cx, bottom, height):
    """Droplet as a pathops.Path in font units (y-up); bulb bottom at `bottom`."""
    s = height / (DROP_BOTTOM - DROP_TOP)
    ox, oy = cx - 0.5 * s, bottom + DROP_BOTTOM * s

    def P(pt):
        return (ox + pt[0] * s, oy - pt[1] * s)

    cmds = [("M", *P(DROP_TIP))]
    for c1, c2, e in DROP_SEGS:
        cmds.append(("C", *P(c1), *P(c2), *P(e)))
    cmds.append(("Z",))
    return path_from_svg_cmds(cmds)


def drop_width(height):
    return 2 * DROP_HALFW * height / (DROP_BOTTOM - DROP_TOP)


# ---------------------------------------------------------------- text helpers
def text_d(font, text, size, x, baseline, tracking=0):
    """One combined path d for a run of text (for small secondary lines)."""
    s = size / font.upm
    ds = []
    for ch, g, gx, adv in font.shape(text, tracking):
        p = font.path(g)
        if p.bounds == (0, 0, 0, 0):
            continue
        ds.append(to_d(p, s, x + gx * s, baseline))
    return "".join(ds)


def text_width(font, text, size, tracking=0):
    return font.width(text, tracking) * size / font.upm


def _wave_segments(x0, x1, y, amp, wavelength, phase=1):
    """Cubic half-waves from x0 past x1. phase=+1 starts with a crest (up), -1 with a trough."""
    half = wavelength / 2
    n = int(math.ceil((x1 - x0) / half))
    d, x, sign = "", x0, -phase
    for _ in range(n):
        nx = x + half
        c = y + sign * amp * 4 / 3  # cubic peaks at 3/4 of its control height
        d += f"C{fmt(x + half * 0.36)} {fmt(c)} {fmt(nx - half * 0.36)} {fmt(c)} {fmt(nx)} {fmt(y)}"
        x, sign = nx, -sign
    return d, x


def wave_d(x0, x1, y, amp, wavelength, bottom, phase=1):
    """Closed liquid body with a wavy top at mean height y, filled down to `bottom`."""
    segs, xe = _wave_segments(x0, x1, y, amp, wavelength, phase)
    return f"M{fmt(x0)} {fmt(bottom)}L{fmt(x0)} {fmt(y)}{segs}L{fmt(xe)} {fmt(bottom)}Z"


def wave_line_d(x0, x1, y, amp, wavelength, phase=1):
    segs, _ = _wave_segments(x0, x1, y, amp, wavelength, phase)
    return f"M{fmt(x0)} {fmt(y)}{segs}"
