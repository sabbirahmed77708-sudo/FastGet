"""Builds the launcher icons from the DROM logo (assets/icon/logo.png).
Run:  python3 tool/make_icon.py
  -> assets/icon/icon.png     (legacy/store icon, full square, no white margin)
  -> assets/icon/icon_bg.png  (adaptive icon background: grey gradient)
  -> assets/icon/icon_fg.png  (adaptive icon foreground: the folder, big)"""
from PIL import Image

OUT = 1024
TOP, BOTTOM = 218, 146  # grey gradient that matches the folder body

logo = Image.open("assets/icon/logo.png").convert("RGBA")
logo = logo.crop(logo.getchannel("A").getbbox())  # drop the empty margin


def gradient():
    col = Image.new("RGBA", (1, OUT))
    for y in range(OUT):
        v = round(TOP + (BOTTOM - TOP) * y / (OUT - 1))
        col.putpixel((0, y), (v, v, v, 255))
    return col.resize((OUT, OUT), Image.BILINEAR)


def place(canvas, width):
    h = round(logo.height * width / logo.width)
    img = logo.resize((width, h), Image.LANCZOS)
    canvas.alpha_composite(img, ((OUT - width) // 2, (OUT - h) // 2))
    return canvas


# adaptive background: plain grey gradient, no white
gradient().convert("RGB").save("assets/icon/icon_bg.png")

# adaptive foreground: folder fills the whole visible (masked) area
place(Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0)), 668).save(
    "assets/icon/icon_fg.png")

# legacy / store icon: same picture on the gradient, edge to edge
place(gradient(), 940).convert("RGB").save("assets/icon/icon.png")
print("icons written")
