"""Build mascot expression and colour variants from the repo's mascot artwork.

The original art is never redrawn: amber is a hue remap of the same pixels, and
the expressions only repaint the eyes and mouth (body underneath is inpainted
from its own surrounding pixels).

    python3 tools/make_mascot_variants.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/img/mascot.png"
OUT = ROOT / "assets/img"

# Feature boxes measured from the dark connected components of the artwork.
LEFT_EYE = (409, 662, 506, 786)
RIGHT_EYE = (733, 661, 833, 786)
MOUTH = (551, 759, 689, 814)
INK = (24, 25, 20)
SS = 4  # supersampling for drawn strokes


def load():
    return np.array(Image.open(SRC).convert("RGBA")).astype(np.float64)


def inpaint(img, mask, iterations=900):
    """Harmonic fill: masked pixels relax towards their neighbours' colour."""
    out = img.copy()
    ys, xs = np.where(mask)
    y0, y1 = max(ys.min() - 8, 0), ys.max() + 9
    x0, x1 = max(xs.min() - 8, 0), xs.max() + 9
    crop = out[y0:y1, x0:x1, :3]
    m = mask[y0:y1, x0:x1]
    crop[m] = crop[~m].mean(axis=0)
    for _ in range(iterations):
        blurred = ndimage.uniform_filter(crop, size=(3, 3, 1))
        crop[m] = blurred[m]
    out[y0:y1, x0:x1, :3] = crop
    return out


def feature_mask(img, box, grow=7):
    x0, y0, x1, y1 = box
    dark = img[..., :3].max(-1) < 110
    m = np.zeros(dark.shape, bool)
    m[y0 - 4:y1 + 5, x0 - 4:x1 + 5] = dark[y0 - 4:y1 + 5, x0 - 4:x1 + 5]
    # Fill the eye's own highlight so nothing of the old eye survives.
    m = ndimage.binary_fill_holes(ndimage.binary_closing(m, iterations=6))
    return ndimage.binary_dilation(m, iterations=grow)


def draw_strokes(img, strokes):
    """strokes: list of (kind, args, width) drawn in INK, antialiased."""
    h, w = img.shape[:2]
    layer = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(layer)
    for kind, args, width in strokes:
        if kind == "arc":
            (cx, cy, rx, ry, a0, a1) = args
            # PIL strokes inside the box; grow it so the centreline sits on (rx, ry).
            hw = width / 2
            d.arc([(cx - rx - hw) * SS, (cy - ry - hw) * SS, (cx + rx + hw) * SS, (cy + ry + hw) * SS], a0, a1, fill=255, width=int(width * SS))
            # Round caps.
            for ang in (a0, a1):
                r = np.deg2rad(ang)
                px, py = cx + rx * np.cos(r), cy + ry * np.sin(r)
                d.ellipse([(px - width / 2) * SS, (py - width / 2) * SS, (px + width / 2) * SS, (py + width / 2) * SS], fill=255)
        elif kind == "ellipse":
            (cx, cy, rx, ry) = args
            d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255)
    cov = np.array(layer.resize((w, h), Image.LANCZOS)).astype(np.float64)[..., None] / 255
    img[..., :3] = img[..., :3] * (1 - cov) + np.array(INK) * cov
    return img


def eye_highlights(img, centers, r=9):
    h, w = img.shape[:2]
    layer = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(layer)
    for cx, cy in centers:
        d.ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=255)
    cov = np.array(layer.resize((w, h), Image.LANCZOS)).astype(np.float64)[..., None] / 255
    img[..., :3] = img[..., :3] * (1 - cov) + 255 * cov
    return img


def to_amber(img):
    """Rotate the green body to PromptJuice amber (#F0A32A), keeping shading."""
    rgb = img[..., :3] / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    v = mx
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    # Green-ness: how much G leads the other channels.
    g_lead = np.clip((rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])) * 4, 0, 1)
    weight = np.clip(s * 1.6, 0, 1) * g_lead
    amber = np.array([0.941, 0.639, 0.165])
    amber_hi = np.array([1.0, 0.86, 0.52])
    # Map value to an amber ramp: shadows deepen, highlights warm toward cream.
    lum = np.clip(v / 0.86, 0, 1.25)[..., None]
    ramp = np.where(lum < 1, amber * (0.35 + 0.65 * lum), amber + (amber_hi - amber) * np.clip(lum - 1, 0, 1) * 3)
    out = rgb * (1 - weight[..., None]) + np.clip(ramp, 0, 1) * weight[..., None]
    img = img.copy()
    img[..., :3] = out * 255
    return img


# Crop to the character (feet at the bottom edge) so the film can anchor on the ground.
CROP = (241, 100, 1017, 1215)


def save(img, name):
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA").crop(CROP)
    im.save(OUT / name, optimize=True)


def main():
    base = load()
    eyes = feature_mask(base, LEFT_EYE, grow=24) | feature_mask(base, RIGHT_EYE, grow=24)
    mouth = feature_mask(base, MOUTH, grow=16)
    lcx, rcx, ecy = 457, 783, 724

    # Blink: flat, slightly curved lids.
    blink = inpaint(base, eyes)
    blink = draw_strokes(blink, [
        ("arc", (lcx, ecy + 4, 44, 12, 15, 165), 15),
        ("arc", (rcx, ecy + 4, 44, 12, 15, 165), 15),
    ])

    # Joy: ^ ^ eyes and a bigger smile.
    joy = inpaint(base, eyes | mouth)
    joy = draw_strokes(joy, [
        ("arc", (lcx, ecy + 18, 40, 34, 200, 340), 17),
        ("arc", (rcx, ecy + 18, 40, 34, 200, 340), 17),
        ("arc", (620, 758, 70, 46, 20, 160), 17),
    ])

    # Alert: wide eyes and a small round mouth.
    alert = inpaint(base, eyes | mouth)
    alert = draw_strokes(alert, [
        ("ellipse", (lcx, ecy - 4, 56, 68), 0),
        ("ellipse", (rcx, ecy - 4, 56, 68), 0),
        ("ellipse", (620, 798, 30, 36), 0),
    ])
    alert = eye_highlights(alert, [(lcx + 16, ecy - 30), (rcx + 16, ecy - 30)], r=13)

    variants = {"happy": base, "blink": blink, "joy": joy, "alert": alert}
    for name, img in variants.items():
        save(img, f"mascot-green-{name}.png")
        save(to_amber(img), f"mascot-amber-{name}.png")


if __name__ == "__main__":
    main()
