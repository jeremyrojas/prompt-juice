"""Builds logo/option-1.svg, option-2.svg and option-3.svg.

    python3 logo/src/build.py

All lettering is Fraunces (SIL OFL 1.1; set PJ_FONT_FAMILY to change) converted to paths.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pj  # noqa: E402
from pj import fmt  # noqa: E402

OUT = os.path.normpath(os.path.join(pj.HERE, ".."))
W, H, CX = 1920, 1080, 960
WORD = "PromptJuice"
TRACK = -12  # font units per letter: a touch tighter than the 12 pt default spacing

F800 = pj.Font(800)
F600 = pj.Font(600)

MASCOT_HREF = "../assets/img/mascot-green-{v}.png"

STYLE = """
    .pj-anim { transform-box: fill-box; transform-origin: 50% 100%; }
    .pj-pivot { transform-box: view-box; }
    .pj-center { transform-box: fill-box; transform-origin: 50% 50%; }
"""


# ---------------------------------------------------------------- building blocks
def layout(size, left):
    """Positions and outlines for each letter of the wordmark."""
    s = size / F800.upm
    out = []
    for ch, g, x, adv in F800.shape(WORD, TRACK):
        out.append({"ch": ch, "path": F800.path(g), "x": left + x * s, "adv": adv * s, "ux": x})
    return out, s


def word_width(size):
    return F800.width(WORD, TRACK) * size / F800.upm


def split_i(letter):
    """Remove the tittle from the i: returns (stem path, dot bounds in units)."""
    parts = pj.split_contours(letter["path"])
    # Split at just above the x-height, so it works for any font's metrics.
    cut = F800.xh * 1.08
    stem = [p for p, b in parts if b[3] <= cut]
    dot = [b for p, b in parts if b[1] > cut][0]
    return pj.merge(stem), dot


def mascot(variant, x, feet_y, height, extra=""):
    """Mascot image placed so its opaque feet end at feet_y, centred on x."""
    w = height * pj.MASCOT_ASPECT
    top = feet_y - pj.MASCOT_FEET * height
    href = MASCOT_HREF.format(v=variant)
    # pivot = between the feet, where they touch the ground (not the PNG's bottom edge)
    return (f'<g id="mascot" class="pj-pivot"{pivot(x, feet_y)}{extra}>\n'
            f'      <image id="mascot-img" href="{href}" x="{fmt(x - w / 2)}" y="{fmt(top)}" '
            f'width="{fmt(w)}" height="{fmt(height)}" preserveAspectRatio="xMidYMax meet"/>\n'
            f'    </g>'), top, w


def secondary(top, pill_label="Free & open source · MIT"):
    """Closing line "Use it or lose it." (#tagline) and, under it, the small open-source pill (#oss-pill).
    `top` is the cap top of the tagline. Returns (svg, bottom_y)."""
    ts = 48
    use_txt, lose_txt = "Use it or ", "lose it."
    trk = -6
    w_use = pj.text_width(F600, use_txt, ts, trk)
    w_all = pj.text_width(F600, use_txt + lose_txt, ts, trk)
    base = top + F600.cap * ts / F600.upm
    x0 = CX - w_all / 2
    # shape the whole line once so the space and kerning stay true, then split the two runs
    s = ts / F600.upm
    runs = {"use": [], "lose": []}
    for i, (ch, g, gx, adv) in enumerate(F600.shape(use_txt + lose_txt, trk)):
        p = F600.path(g)
        if p.bounds == (0, 0, 0, 0):
            continue
        runs["use" if i < len(use_txt) else "lose"].append(pj.to_d(p, s, x0 + gx * s, base))
    tag = (f'<g id="tagline" class="pj-center">\n'
           f'      <path id="tagline-use" d="{"".join(runs["use"])}" fill="#ffffff" fill-opacity="0.9"/>\n'
           f'      <path id="tagline-lose" d="{"".join(runs["lose"])}" fill="url(#amber-grad)"/>\n'
           f'    </g>')
    amber = (f'    <linearGradient id="amber-grad" gradientUnits="userSpaceOnUse" x1="0" y1="{fmt(top)}" x2="0" y2="{fmt(base)}">\n'
             f'      <stop offset="0" stop-color="{pj.AMBER_LT}"/><stop offset="0.55" stop-color="{pj.AMBER}"/>'
             f'<stop offset="1" stop-color="{pj.AMBER_DK}"/>\n    </linearGradient>')

    # pill
    ps = 21
    tw = pj.text_width(F600, pill_label, ps, 6)
    icon_h, pad_l, pad_r, gap_i = 17, 18, 20, 9
    pill_w = pad_l + pj.drop_width(icon_h) + gap_i + tw + pad_r
    pill_h = 42
    cy = base + 34 + pill_h / 2
    px0 = CX - pill_w / 2
    t_base = cy + 0.5 * F600.cap * ps / F600.upm
    ix = px0 + pad_l + pj.drop_width(icon_h) / 2
    pill = (
        f'<g id="oss-pill" class="pj-center">\n'
        f'      <rect id="oss-pill-bg" x="{fmt(px0)}" y="{fmt(cy - pill_h / 2)}" width="{fmt(pill_w)}" height="{pill_h}" '
        f'rx="{pill_h / 2}" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.15" stroke-width="1.5"/>\n'
        f'      <path id="oss-pill-icon" d="{pj.droplet_d(ix, cy + icon_h * 0.5, icon_h)}" fill="{pj.GREEN}"/>\n'
        f'      <path id="oss-pill-text" d="{pj.text_d(F600, pill_label, ps, ix + pj.drop_width(icon_h) / 2 + gap_i, t_base, 6)}" '
        f'fill="#ffffff" fill-opacity="0.62"/>\n'
        f'    </g>'
    )
    return tag + "\n    " + pill, cy + pill_h / 2, amber


def svg(title, desc, defs, body, bg):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {W} {H}" width="{W}" height="{H}">
  <title>{title}</title>
  <desc>{desc}</desc>
  <style>{STYLE}  </style>
  <defs>
{defs}
  </defs>
  <g id="bg">
    <rect width="{W}" height="{H}" fill="{pj.GROUND}"/>
{bg}
  </g>
  <g id="lockup">
{body}
  </g>
</svg>
"""


def juice_gradient(gid, y_top, y_bot, kind="vertical"):
    return (f'    <linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="0" y1="{fmt(y_top)}" x2="0" y2="{fmt(y_bot)}">\n'
            f'      <stop offset="0" stop-color="{pj.GREEN_LT}"/>\n'
            f'      <stop offset="0.5" stop-color="{pj.GREEN}"/>\n'
            f'      <stop offset="1" stop-color="{pj.GREEN_DK}"/>\n'
            f'    </linearGradient>')


def glow(gid, cx, cy, r, color, opacity, ry=None):
    ry = ry or r
    return (f'    <radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}" '
            f'gradientTransform="translate({fmt(cx)} {fmt(cy)}) scale(1 {fmt(ry / r, )}) translate({fmt(-cx)} {fmt(-cy)})">\n'
            f'      <stop offset="0" stop-color="{color}" stop-opacity="{opacity}"/>\n'
            f'      <stop offset="0.55" stop-color="{color}" stop-opacity="{opacity * 0.35:.3f}"/>\n'
            f'      <stop offset="1" stop-color="{color}" stop-opacity="0"/>\n'
            f'    </radialGradient>')


def vignette():
    return (f'    <radialGradient id="vignette" gradientUnits="userSpaceOnUse" cx="{CX}" cy="540" r="1150">\n'
            f'      <stop offset="0.55" stop-color="#000" stop-opacity="0"/>\n'
            f'      <stop offset="1" stop-color="#000" stop-opacity="0.55"/>\n'
            f'    </radialGradient>')


def pivot(x, y):
    """Explicit transform origin in SVG user units (== CSS px inside the SVG)."""
    return f' style="transform-origin: {fmt(x)}px {fmt(y)}px"'


def letter_g(L, d, indent="      ", extra="", inner_transform=None, baseline=None):
    """One letter. Its transform origin is the letter's centre on the baseline."""
    lid = f"l-{L['ch']}"
    if baseline is not None:
        extra += pivot(L["x"] + L["adv"] / 2, baseline)
    body = f'<path id="gl-{L["ch"]}" d="{d}"/>'
    if inner_transform:
        body = f'<g transform="{inner_transform}">{body}</g>'
    cls = "pj-pivot" if baseline is not None else "pj-anim"
    return f'{indent}<g id="{lid}" class="{cls}"{extra}>{body}</g>'


# ================================================================ OPTION 1: Juice Level
def option1():
    size = 196
    ww = word_width(size)
    left = CX - ww / 2
    letters, s = layout(size, left)
    cap = F800.cap * s

    mh = 392
    top_y = 186
    feet = top_y + pj.MASCOT_FEET * mh
    cap_top = feet + 30
    yb = cap_top + cap
    level = yb - 0.60 * cap  # mean juice line

    prompt, juice, clip = [], [], []
    dot_svg = ""
    for L in letters:
        p = L["path"]
        if L["ch"] == "i":
            p, dot = split_i(L)
            dw = 210  # droplet a touch wider than the old tittle
            dh = dw / pj.drop_width(1)
            dcx = L["x"] + (dot[0] + dot[2]) / 2 * s
            dbot = yb - (dot[1] - 6) * s
            dot_svg = (f'      <g id="droplet-dot" class="pj-anim">'
                       f'<path d="{pj.droplet_d(dcx, dbot, dh * s)}" fill="url(#drop-grad)"/></g>')
            drop_top = dbot - dh * s
        d = pj.to_d(p, s, L["x"], yb)
        if L["ux"] < F800.shape(WORD, TRACK)[6][2]:
            prompt.append(letter_g(L, d, baseline=yb))
        else:
            juice.append(letter_g(L, d, baseline=yb))
            clip.append(f'      <use id="jc-{L["ch"]}" href="#gl-{L["ch"]}"/>')

    jx0 = letters[6]["x"] - 20
    jx1 = letters[-1]["x"] + letters[-1]["adv"] + 20
    body_d = pj.wave_d(jx0 - 240, jx1 + 40, level, 8, 146, yb + 40)
    line_d = pj.wave_line_d(jx0 - 240, jx1 + 40, level, 8, 146)
    bubbles = []
    for (lx, dy, r) in [(7.05, 34, 7), (7.6, 58, 4.5), (9.35, 30, 5.5), (10.3, 56, 4)]:
        i = int(lx)
        bx = letters[i]["x"] + (lx - i) * letters[i]["adv"] + 18
        bubbles.append(f'<circle cx="{fmt(bx)}" cy="{fmt(level + dy)}" r="{r}"/>')

    m_svg, m_top, m_w = mascot("happy", CX, feet, mh)
    row, bottom, amber = secondary(yb + 0.169 * size + 44)

    defs = "\n".join([
        amber,
        juice_gradient("juice-grad", level - 10, yb + 10),
        juice_gradient("drop-grad", drop_top, drop_top + 60),
        glow("glow-mascot", CX, feet - mh * 0.42, 420, pj.GREEN, 0.20, 360),
        glow("glow-floor", CX, yb - cap * 0.4, 760, pj.GREEN, 0.07, 180),
        vignette(),
        '    <clipPath id="juice-clip">',
        *clip,
        "    </clipPath>",
    ])
    bg = ('    <rect id="glow" width="1920" height="1080" fill="url(#glow-mascot)"/>\n'
          '    <rect width="1920" height="1080" fill="url(#glow-floor)"/>\n'
          '    <rect width="1920" height="1080" fill="url(#vignette)"/>')
    body = f"""    {m_svg}
    <g id="wordmark">
      <g id="word-prompt" fill="{pj.WHITE}">
{chr(10).join(prompt)}
      </g>
      <g id="word-juice">
        <!-- empty "glass": the letter shapes, faintly tinted, with a thin rim -->
        <g id="juice-vessel" fill="{pj.GREEN}" fill-opacity="0.17" stroke="{pj.GREEN_LT}" stroke-opacity="0.55" stroke-width="2">
{chr(10).join("  " + j for j in juice)}
        </g>
        <!-- the juice: translate #juice-level on y to fill/drain, slide #juice-wave on x to slosh -->
        <g id="juice-fill" clip-path="url(#juice-clip)">
          <g id="juice-level">
            <g id="juice-wave">
              <path id="juice-body" d="{body_d}" fill="url(#juice-grad)"/>
              <path id="juice-meniscus" d="{line_d}" fill="none" stroke="#D4FF9E" stroke-opacity="0.9" stroke-width="3.5"/>
            </g>
            <g id="juice-bubbles" fill="#ffffff" fill-opacity="0.32">{"".join(bubbles)}</g>
          </g>
        </g>
      </g>
{dot_svg}
    </g>
    {row}"""
    return svg("PromptJuice — Juice Level",
               "End card option 1: mascot above a wordmark whose 'Juice' letters are glasses filled with juice; the i's dot is the app droplet.",
               defs, body, bg)


# ================================================================ OPTION 2: Perch
SQ_X, SQ_Y = 1.012, 0.95

def option2():
    size = 204
    ww = word_width(size)
    left = CX - ww / 2
    letters, s = layout(size, left)
    yb = 712
    shelf = yb - 542 * s * SQ_Y  # top of the squashed m and p (x-height + overshoot)

    mh = 474
    mw = mh * pj.MASCOT_ASPECT
    t = letters[5]
    t_left = t["x"] + 12 * s
    m_left = t_left - 0.789 * mw - 14  # right foot clears the t by 14 px
    mcx = m_left + mw / 2
    m_svg, m_top, _ = mascot("joy", mcx, shelf + 1, mh)

    prompt, juice = [], []
    dot_svg = drip_svg = ""
    J = letters[6]
    for L in letters:
        p = L["path"]
        if L["ch"] == "i":
            p, dot = split_i(L)
            dw = 214
            dh = dw / pj.drop_width(1)
            dcx = L["x"] + (dot[0] + dot[2]) / 2 * s
            dbot = yb - (dot[1] - 4) * s
            dot_svg = (f'        <g id="droplet-dot" class="pj-anim">'
                       f'<path d="{pj.droplet_d(dcx, dbot, dh * s)}"/></g>')
        d = pj.to_d(p, s, L["x"], yb)
        squash = None
        if L["ch"] in "mp":  # the two letters the mascot stands on give a little under its weight
            lcx = L["x"] + L["adv"] / 2
            squash = (f"translate({fmt(lcx)} {fmt(yb)}) scale({SQ_X} {SQ_Y}) translate({fmt(-lcx)} {fmt(-yb)})")
        (prompt if L["ux"] < J["ux"] else juice).append(letter_g(L, d, "        ", inner_transform=squash, baseline=yb))

    # J drip: a tongue of juice hanging from the bowl, plus a falling drop (DropletGeometry, tip up)
    cx = J["x"] + 118 * s
    u = s
    top = yb - 40 * u
    bulb_c = yb + 128 * u
    r = 50 * u
    drip_d = (f"M{fmt(cx - 96 * u)} {fmt(top)}"
              f"C{fmt(cx - 40 * u)} {fmt(yb + 6 * u)} {fmt(cx - 26 * u)} {fmt(yb + 30 * u)} {fmt(cx - 24 * u)} {fmt(yb + 64 * u)}"
              f"C{fmt(cx - 24 * u)} {fmt(yb + 78 * u)} {fmt(cx - r)} {fmt(bulb_c - r * 0.55)} {fmt(cx - r)} {fmt(bulb_c)}"
              f"A{fmt(r)} {fmt(r)} 0 0 0 {fmt(cx + r)} {fmt(bulb_c)}"
              f"C{fmt(cx + r)} {fmt(bulb_c - r * 0.55)} {fmt(cx + 24 * u)} {fmt(yb + 78 * u)} {fmt(cx + 24 * u)} {fmt(yb + 64 * u)}"
              f"C{fmt(cx + 26 * u)} {fmt(yb + 30 * u)} {fmt(cx + 40 * u)} {fmt(yb + 6 * u)} {fmt(cx + 96 * u)} {fmt(top)}Z")
    fall_h = 150 * u
    fall_bot = yb + 390 * u
    drip_svg = (f'        <g id="drip" class="pj-pivot"{pivot(cx, top)}><path id="drip-tongue" d="{drip_d}"/></g>\n'
                f'        <g id="drip-drop" class="pj-anim"><path d="{pj.droplet_d(cx, fall_bot, fall_h)}"/></g>')

    row, bottom, amber = secondary(yb + 390 * s + 30)

    defs = "\n".join([
        amber,
        juice_gradient("juice-grad", yb - 760 * s, yb + 340 * s),
        glow("glow-mascot", mcx, shelf - mh * 0.45, 440, pj.GREEN, 0.20, 380),
        vignette(),
        f'    <radialGradient id="contact" cx="0.5" cy="0.5" r="0.5">'
        f'<stop offset="0" stop-color="#000" stop-opacity="0.55"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>',
    ])
    bg = ('    <rect id="glow" width="1920" height="1080" fill="url(#glow-mascot)"/>\n'
          '    <rect width="1920" height="1080" fill="url(#vignette)"/>')
    body = f"""    <g id="wordmark">
      <g id="word-prompt" fill="{pj.WHITE}">
{chr(10).join(prompt)}
      </g>
      <g id="word-juice" fill="url(#juice-grad)">
{chr(10).join(juice)}
{drip_svg}
{dot_svg}
      </g>
    </g>
    <!-- contact shadow where the mascot sits on the m and p -->
    <ellipse id="mascot-shadow" class="pj-center" cx="{fmt(mcx)}" cy="{fmt(shelf + 2)}" rx="{fmt(mw * 0.30)}" ry="5" opacity="0.5" fill="url(#contact)"/>
    {m_svg}
    {row}"""
    return svg("PromptJuice — Perch",
               "End card option 2: the mascot sits on the lowercase shelf of 'Prompt' between the P and the t; the J drips juice and the i's dot is the app droplet.",
               defs, body, bg)


# ================================================================ OPTION 3: Peek
def option3():
    size = 212
    ww = word_width(size)
    left = CX - ww / 2
    letters, s = layout(size, left)
    yb = 688
    xh_top = yb - 542 * s

    mh = 500
    mcx = CX - 44
    m_svg, m_top, mw = mascot("happy", mcx, yb + 4, mh)

    knock, prompt, juice = [], [], []
    dot_svg = ""
    J = letters[6]
    for L in letters:
        p = L["path"]
        if L["ch"] == "i":
            p, dot = split_i(L)
            dw = 206
            dh = dw / pj.drop_width(1)
            dcx = L["x"] + (dot[0] + dot[2]) / 2 * s
            dbot = yb - (dot[1] - 4) * s
            dot_svg = f'<g id="droplet-dot" class="pj-anim"><path d="{pj.droplet_d(dcx, dbot, dh * s)}"/></g>'
        d = pj.to_d(p, s, L["x"], yb)
        g = letter_g(L, d, "        ", baseline=yb)
        if L["ch"] == "i":
            g = g[:-len("</g>")] + dot_svg + "</g>"  # the droplet rides along with the i
        (prompt if L["ux"] < J["ux"] else juice).append(g)
        knock.append(f'      <use href="#l-{L["ch"]}"/>')

    # capacity gauge woven under the word: crosses the p descender, knocked out by the letters' ground stroke
    gy = yb + 26
    gh = 15
    gx0 = letters[0]["x"] + 69 * s
    gx1 = letters[-1]["x"] + 555 * s
    frac = 0.78
    gf = gx0 + (gx1 - gx0) * frac

    row, bottom, amber = secondary(gy + gh + 38)

    defs = "\n".join([
        amber,
        juice_gradient("juice-grad", yb - 760 * s, yb + 20),
        (f'    <linearGradient id="gauge-grad" gradientUnits="userSpaceOnUse" x1="{fmt(gx0)}" y1="0" x2="{fmt(gf)}" y2="0">\n'
         f'      <stop offset="0" stop-color="{pj.GREEN_DK}"/><stop offset="0.7" stop-color="{pj.GREEN}"/>'
         f'<stop offset="1" stop-color="{pj.GREEN_LT}"/>\n    </linearGradient>'),
        glow("glow-mascot", mcx, xh_top - 120, 400, pj.GREEN, 0.22, 330),
        glow("glow-tip", gf, gy + gh / 2, 44, pj.GREEN_LT, 0.45),
        vignette(),
        f'    <clipPath id="peek-clip"><rect x="0" y="0" width="{W}" height="{fmt(xh_top + 20)}"/></clipPath>',
    ])
    bg = ('    <rect id="glow" width="1920" height="1080" fill="url(#glow-mascot)"/>\n'
          '    <rect width="1920" height="1080" fill="url(#vignette)"/>')
    body = f"""    <!-- the mascot stands behind the letters; #peek-clip hides everything below the x-height line -->
    <g id="mascot-peek" clip-path="url(#peek-clip)">
      {m_svg}
    </g>
    <g id="gauge">
      <rect id="gauge-track" x="{fmt(gx0)}" y="{fmt(gy)}" width="{fmt(gx1 - gx0)}" height="{gh}" rx="{gh / 2}" fill="#ffffff" fill-opacity="0.10"/>
      <rect id="gauge-fill" x="{fmt(gx0)}" y="{fmt(gy)}" width="{fmt(gf - gx0)}" height="{gh}" rx="{gh / 2}" fill="url(#gauge-grad)"/>
      <g id="gauge-tip" class="pj-center"><circle cx="{fmt(gf - gh / 2)}" cy="{fmt(gy + gh / 2)}" r="44" fill="url(#glow-tip)"/><circle cx="{fmt(gf - gh / 2)}" cy="{fmt(gy + gh / 2)}" r="{gh / 2 - 3}" fill="#E9FFD2"/></g>
    </g>
    <!-- ground-coloured outline under every letter: separates the type from the mascot and the gauge.
         These are <use> clones, so they follow any transform set on #l-* -->
    <g id="wordmark-knockout" fill="{pj.GROUND}" stroke="{pj.GROUND}" stroke-width="13" stroke-linejoin="round">
{chr(10).join(knock)}
    </g>
    <g id="wordmark">
      <g id="word-prompt" fill="{pj.WHITE}">
{chr(10).join(prompt)}
      </g>
      <g id="word-juice" fill="url(#juice-grad)">
{chr(10).join(juice)}
      </g>
    </g>
    {row}"""
    return svg("PromptJuice — Peek",
               "End card option 3: oversized wordmark with the mascot peeking over it from behind, and a usage gauge woven through the descenders.",
               defs, body, bg)


if __name__ == "__main__":
    for n, fn in ((1, option1), (2, option2), (3, option3)):
        path = os.path.join(OUT, f"option-{n}.svg")
        with open(path, "w") as f:
            f.write(fn())
        print("wrote", path, os.path.getsize(path), "bytes")
