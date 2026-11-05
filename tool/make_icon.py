"""Builds the launcher icons from the DROM logo (assets/icon/logo.png).
Run:  python3 tool/make_icon.py  ->  assets/icon/icon.png and icon_fg.png"""
from PIL import Image

BG = (242, 244, 248, 255)  # same as adaptive_icon_background in pubspec.yaml
OUT = 1024

logo = Image.open("assets/icon/logo.png").convert("RGBA")
logo = logo.crop(logo.getchannel("A").getbbox())  # drop the empty margin


def place(canvas, width):
    h = round(logo.height * width / logo.width)
    img = logo.resize((width, h), Image.LANCZOS)
    canvas.alpha_composite(img, ((OUT - width) // 2, (OUT - h) // 2))
    return canvas


# legacy / store icon: logo on a light square
place(Image.new("RGBA", (OUT, OUT), BG), 780).convert("RGB").save("assets/icon/icon.png")

# adaptive icon foreground: transparent, kept inside the safe zone
place(Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0)), 500).save("assets/icon/icon_fg.png")
print("icons written")
