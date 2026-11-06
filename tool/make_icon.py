"""Draws SDM's logo and launcher icons (vector design rendered with Chromium).

  assets/icon/logo.png     logo for About (rounded square)
  assets/icon/icon.png     launcher icon, full square (older Androids)
  assets/icon/icon_fg.png  adaptive icon foreground (the glyph, transparent)
  assets/icon/icon_bg.png  adaptive icon background (the gradient)

Run:  python3 tool/make_icon.py"""
from playwright.sync_api import sync_playwright

DEFS = """
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#4F46E5"/><stop offset=".55" stop-color="#2563EB"/>
    <stop offset="1" stop-color="#06B6D4"/>
  </linearGradient>
  <radialGradient id="glow" cx=".25" cy=".15" r=".8">
    <stop offset="0" stop-color="#fff" stop-opacity=".30"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="arrow" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#DCEBFF"/>
  </linearGradient>
  <filter id="sh" x="-20%" y="-20%" width="140%" height="150%">
    <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#0B1B6B" flood-opacity=".35"/>
  </filter>
</defs>"""

# glyph drawn in a 1024 box, content centred on (512,512)
GLYPH = """
<g filter="url(#sh)">
  <path d="M452 215 H572 V500 H680 L512 690 L344 500 H452 Z" fill="url(#arrow)"
        stroke="url(#arrow)" stroke-width="34" stroke-linejoin="round"/>
  <path d="M262 640 V740 Q262 800 322 800 H702 Q762 800 762 740 V640"
        fill="none" stroke="#fff" stroke-width="46" stroke-linecap="round" stroke-linejoin="round"/>
</g>
<circle cx="512" cy="738" r="0" fill="#fff"/>"""


def svg(body, size=1024):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 1024 1024">{DEFS}{body}</svg>')


BG = '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#glow)"/>'
ROUND = '<clipPath id="r"><rect width="1024" height="1024" rx="232"/></clipPath>'
full = svg(f'{ROUND}<g clip-path="url(#r)">{BG}</g>{GLYPH}')            # About logo
square = svg(f'{BG}<g transform="translate(512 512) scale(1.0) translate(-512 -512)">{GLYPH}</g>')
fg = svg(f'<g transform="translate(512 512) scale(.66) translate(-512 -512)">{GLYPH}</g>')
bg = svg(BG)

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": 1024, "height": 1024})
    for name, doc in [("logo", full), ("icon", square), ("icon_fg", fg), ("icon_bg", bg)]:
        pg.set_content(f'<body style="margin:0;background:transparent">{doc}</body>')
        pg.screenshot(path=f"assets/icon/{name}.png", omit_background=True)
    b.close()
print("icons written")
