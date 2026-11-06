"""Builds the launcher icons from the app logo (assets/icon/logo.png).
Run:  python3 tool/make_icon.py
  -> assets/icon/icon.png     (legacy icon: the logo fills the whole square)
  -> assets/icon/icon_bg.png  (adaptive icon background: the logo's own grey)
  -> assets/icon/icon_fg.png  (adaptive icon foreground: the whole logo, sized
                               so launcher masks (circle / squircle) never cut it)
A light blue veil is laid over all three; change VEIL to make it stronger or
weaker (0 = no veil)."""
from PIL import Image

OUT = 1024
BLUE = (110, 170, 255)  # light blue veil
VEIL = 0.20             # 0 = none, 1 = solid blue
# the logo's own background grey, light at the top and darker at the bottom
BG_TOP, BG_BOTTOM = (222, 231, 237), (125, 131, 138)
FG_SCALE = 0.70         # share of the adaptive canvas the logo covers

logo = Image.open("assets/icon/logo.png").convert("RGBA")


def background():
    col = Image.new("RGB", (1, OUT))
    for y in range(OUT):
        t = y / (OUT - 1)
        col.putpixel((0, y), tuple(
            round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return col.resize((OUT, OUT), Image.BILINEAR).convert("RGBA")


def veil(img):
    """Light blue veil over the picture; transparent parts stay transparent."""
    r, g, b, a = img.split()
    out = Image.blend(Image.merge("RGB", (r, g, b)),
                      Image.new("RGB", img.size, BLUE), VEIL).convert("RGBA")
    out.putalpha(a)
    return out


def place(canvas, size):
    """Logo scaled to `size` px wide (keeps its shape), centred on the canvas."""
    h = round(logo.height * size / logo.width)
    img = veil(logo.resize((size, h), Image.LANCZOS))
    canvas.alpha_composite(img, ((OUT - size) // 2, (OUT - h) // 2))
    return canvas


# adaptive background
veil(background()).convert("RGB").save("assets/icon/icon_bg.png")

# adaptive foreground
place(Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0)), round(OUT * FG_SCALE)).save(
    "assets/icon/icon_fg.png")

# legacy icon: logo edge to edge
place(veil(background()), OUT).convert("RGB").save("assets/icon/icon.png")
print("icons written")
