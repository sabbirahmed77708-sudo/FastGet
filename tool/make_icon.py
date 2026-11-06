"""Builds DROM's logo and launcher icons from the supplied artwork
(assets/icon/logo_source.jpg), (full-bleed, no empty margin).

  assets/icon/logo.png     logo for About (rounded corners, transparent outside)
  assets/icon/icon.png     full-bleed launcher icon (older Androids)
  assets/icon/icon_fg.png  adaptive icon foreground
  assets/icon/icon_bg.png  adaptive icon background (the art's own gradient)

Run:  python3 tool/make_icon.py"""
from PIL import Image, ImageDraw

SRC = "assets/icon/logo_source.jpg"

src = Image.open(SRC).convert("RGB")
w, h = src.size
# the folder spans almost the whole width: square it up around the folder so
# it fills the frame edge to edge (a few pixels of the dark backdrop are added
# top and bottom by repeating the picture's own edge rows)
X0, X1 = 38, 1044
side = X1 - X0
top_pad = (side - h) // 2
art = Image.new("RGB", (side, side))
crop = src.crop((X0, 0, X1, h))
art.paste(crop, (0, max(top_pad, 0)))
if top_pad > 0:
    art.paste(crop.crop((0, 0, side, 1)).resize((side, top_pad)), (0, 0))
    art.paste(crop.crop((0, h - 1, side, h)).resize((side, side - h - top_pad)),
              (0, top_pad + h))


def rounded(img, radius_frac=0.058):
    """Same picture with transparent rounded corners."""
    s = 4  # supersample the mask for smooth corners
    W, H = img.size
    mask = Image.new("L", (W * s, H * s), 0)
    r = int(min(W, H) * radius_frac * s)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W * s - 1, H * s - 1), r, fill=255)
    mask = mask.resize((W, H), Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


# About / in-app logo
logo = rounded(art.resize((768, 768), Image.LANCZOS))
logo.save("assets/icon/logo.png")

# full-bleed icon: the picture fills the whole square, nothing white or empty
art.resize((1024, 1024), Image.LANCZOS).save("assets/icon/icon.png")

# adaptive icon: art at ~80%, background = the art's own gradient so it blends
OUT = 1024
fg = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
size = int(OUT * 0.70)
piece = art.resize((size, size), Image.LANCZOS).convert('RGBA')
fg.alpha_composite(piece, ((OUT - size) // 2, (OUT - size) // 2))
fg.save("assets/icon/icon_fg.png")

# gradient from the picture's top edge colour to its bottom edge colour
aw, ah = art.size
top = art.crop((aw // 2 - 40, 4, aw // 2 + 40, 14)).resize((1, 1), Image.BOX).getpixel((0, 0))
bot = art.crop((aw // 2 - 40, ah - 14, aw // 2 + 40, ah - 4)).resize((1, 1), Image.BOX).getpixel((0, 0))
bg = Image.new("RGB", (OUT, OUT))
px = bg.load()
for y in range(OUT):
    t = y / (OUT - 1)
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    for x in range(OUT):
        px[x, y] = c
bg.save("assets/icon/icon_bg.png")
print("icons written; gradient", top, bot)
