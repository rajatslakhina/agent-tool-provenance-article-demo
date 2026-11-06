# Composes three real Simulator screenshots side by side for the article and README.
import sys
from PIL import Image, ImageDraw, ImageFont
names = ["replay-auto-update", "replay-digest-lockfile", "replay-canary"]
labels = ["Auto-update", "Digest lockfile", "Canary + integrity check"]
ims = [Image.open(f"Demo/Screenshots/{n}.png").convert("RGB") for n in names]
s = 0.42
w, h = int(ims[0].width * s), int(ims[0].height * s)
pad, top = 36, 70
out = Image.new("RGB", (pad + 3 * (w + pad), h + top + pad), "#f6f8fa")
d = ImageDraw.Draw(out)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
except OSError:
    font = ImageFont.load_default()
for i, im in enumerate(ims):
    x = pad + i * (w + pad)
    d.text((x, 22), labels[i], fill="#1f2328", font=font)
    out.paste(im.resize((w, h)), (x, top))
out.save("docs/simulator.png")
