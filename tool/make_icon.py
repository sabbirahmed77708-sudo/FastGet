"""Draws the DROM app icon (original artwork): a download arrow dropping into a tray.
Run:  python3 tool/make_icon.py   ->  assets/icon/icon.png and icon_fg.png"""
from PIL import Image, ImageDraw

S = 2048          # draw big, shrink for smooth edges
OUT = 1024


def symbol(scale=1.0):
    """White arrow + tray on a transparent canvas (coordinates for a 1024 grid)."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = S / 1024.0

    def P(x, y):
        # scale around the centre, then to the big canvas
        return ((512 + (x - 512) * scale) * k, (512 + (y - 512) * scale) * k)

    w = 58 * scale * k
    white = (255, 255, 255, 255)

    # tray (U shape with round ends)
    pts = [P(300, 640), P(300, 735), P(724, 735), P(724, 640)]
    d.line(pts, fill=white, width=int(w), joint="curve")
    for x, y in (pts[0], pts[-1]):
        r = w / 2
        d.ellipse((x - r, y - r, x + r, y + r), fill=white)

    # arrow shaft + head
    x0, y0 = P(482, 262)
    x1, y1 = P(542, 540)
    d.rectangle((x0, y0, x1, y1), fill=white)
    d.polygon([P(366, 500), P(658, 500), P(512, 668)], fill=white)
    return img


def gradient():
    img = Image.new("RGB", (S, S))
    px = img.load()
    c1 = (99, 102, 241)    # indigo
    c2 = (37, 99, 235)     # blue
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2.0 * (S - 1))
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img.convert("RGBA")


full = Image.alpha_composite(gradient(), symbol(1.0)).resize((OUT, OUT), Image.LANCZOS)
full.convert("RGB").save("assets/icon/icon.png")

fg = symbol(0.88).resize((OUT, OUT), Image.LANCZOS)
fg.save("assets/icon/icon_fg.png")
print("icons written")
