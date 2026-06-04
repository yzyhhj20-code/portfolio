#!/usr/bin/env python3
# PixelCam 图标：1-bit 像素相机（白机柔黑底），缩小并居中（L=40 画布 + 留白）
from PIL import Image, ImageDraw
import shutil

PROJ = "/Users/darren.yuan/Desktop/Ai 作品/App/像素相机"
ICONSET = f"{PROJ}/PixelCam/PixelCam/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
L = 40
SCALE = 28
SZ = L * SCALE
OX, OY = 6, 5

BG    = (22, 22, 28, 255)
BODY  = (245, 245, 242, 255)
DARK  = (22, 22, 28, 255)
GLINT = (255, 255, 255, 255)

def camera():
    im = Image.new("RGBA", (L, L), BG)
    d = ImageDraw.Draw(im)
    d.rectangle([6+OX, 6+OY, 12+OX, 10+OY], fill=BODY)
    d.rectangle([18+OX, 7+OY, 21+OX, 9+OY], fill=BODY)
    d.rounded_rectangle([2+OX, 10+OY, 25+OX, 24+OY], radius=3, fill=BODY)
    cx, cy, r = 13+OX, 17+OY, 5
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=DARK)
    for y in range(cy-r, cy+r+1):
        for x in range(cx-r, cx+r+1):
            if (x-cx)**2 + (y-cy)**2 <= (r-1)**2:
                im.putpixel((x, y), BODY if (x + y) % 2 == 0 else DARK)
    im.putpixel((cx-2, cy-2), GLINT)
    im.putpixel((cx-1, cy-2), GLINT)
    return im

big = camera().resize((SZ, SZ), Image.NEAREST)
flat = Image.new("RGB", (SZ, SZ), BG[:3])
flat.paste(big, (0, 0), big)
flat = flat.resize((1024, 1024), Image.NEAREST)
flat.save(f"{PROJ}/PixelCam_icon_1024.png")
shutil.copy(f"{PROJ}/PixelCam_icon_1024.png", ICONSET)

rad = int(1024 * 0.22)
m = Image.new("L", (1024, 1024), 0)
ImageDraw.Draw(m).rounded_rectangle([0, 0, 1023, 1023], radius=rad, fill=255)
prev = flat.convert("RGBA"); prev.putalpha(m)
prev.save(f"{PROJ}/PixelCam_icon_preview.png")
print("OK")
