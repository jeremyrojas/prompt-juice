"""Contact sheet: python3 tools/sheet.py dir out.png [cols] [thumb_width]"""
import sys, glob, os
from PIL import Image, ImageDraw, ImageFont
d, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 3
tw = int(sys.argv[4]) if len(sys.argv) > 4 else 640
files = sorted(glob.glob(os.path.join(d, "t*.png")))
th = tw * 1080 // 1920
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (tw + 8), rows * (th + 30)), (40, 40, 40))
dr = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Bold.otf", 18)
except OSError:
    font = None
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
    x, y = (i % cols) * (tw + 8), (i // cols) * (th + 30)
    sheet.paste(im, (x, y + 26))
    dr.text((x + 4, y + 3), os.path.basename(f)[1:-4] + " s", fill=(255, 255, 255), font=font)
sheet.save(out)
