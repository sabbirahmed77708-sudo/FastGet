"""Builds SDM's logo and launcher icons from the supplied artwork
(assets/icon/logo_source.jpg): ONLY the folder-and-cloud logo, cut out of its
dark backdrop, so no white or other coloured area is left around it.

  assets/icon/logo.png     logo for About (transparent around the logo)
  assets/icon/icon.png     launcher icon, logo filling the square (older Androids)
  assets/icon/icon_fg.png  adaptive icon foreground (the logo)
  assets/icon/icon_bg.png  adaptive icon background (fully transparent)

Run:  python3 tool/make_icon.py"""
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi

SRC = "assets/icon/logo_source.jpg"
src = Image.open(SRC).convert("RGB")
a = np.asarray(src).astype(int)
h, w, _ = a.shape

# backdrop colour per row (outer columns), logo = what differs from it
bgc = np.concatenate([a[:, :10], a[:, -10:]], axis=1).mean(axis=1)
d = np.abs(a - bgc[:, None, :]).max(axis=2)
fg = ndi.binary_opening(d >= 16, iterations=2)
lab, n = ndi.label(fg)
sizes = ndi.sum(fg, lab, range(1, n + 1))
fg = lab == (1 + int(np.argmax(sizes)))
fg = ndi.binary_closing(fg, iterations=4)
for y in range(int(0.40 * h), h):  # folder body: fill each row edge to edge
    r = np.where(fg[y])[0]
    if len(r) > 200:
        fg[y, r.min():r.max() + 1] = True
fg = ndi.binary_fill_holes(fg)
m = Image.fromarray((fg * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(1.0))
m = m.point(lambda v: 0 if v < 100 else (255 if v > 160 else int((v - 100) * 255 / 60)))
logo = src.convert("RGBA")
logo.putalpha(m)
logo = logo.crop(logo.getbbox())
logo = logo.crop((0, 0, logo.width, logo.height - 10))  # soft shadow strip at the foot
logo = logo.crop(logo.getbbox())
print("logo", logo.size)


def on_square(img, size, frac):
    """The logo, centred on a transparent square, `frac` of the width."""
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tw = int(size * frac)
    th = int(tw * img.height / img.width)
    piece = img.resize((tw, th), Image.LANCZOS)
    out.alpha_composite(piece, ((size - tw) // 2, (size - th) // 2))
    return out


logo.resize((768, int(768 * logo.height / logo.width)), Image.LANCZOS).save("assets/icon/logo.png")
on_square(logo, 1024, 0.96).save("assets/icon/icon.png")
on_square(logo, 1024, 0.64).save("assets/icon/icon_fg.png")  # fits the adaptive safe zone
Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)).save("assets/icon/icon_bg.png")
