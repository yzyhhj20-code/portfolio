#!/usr/bin/env python3
# PixelCam logo：1-bit 像素画相机（硬边方块 + 镜头抖动纹理），呼应 BitCam 像素感。
from PIL import Image, ImageDraw, ImageFont

PROJ = "/Users/darren.yuan/Desktop/Ai 作品/App/像素相机"
L = 28
SCALE = 40
SZ = L * SCALE

def draw_camera(fg, bg, dither_dark, dither_light, bg_img=None):
    im = Image.new("RGBA", (L, L), bg if bg_img is None else (0, 0, 0, 0))
    if bg_img is not None:
        im.paste(bg_img, (0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([3, 11, 24, 24], radius=2, fill=fg)
    d.rectangle([6, 7, 11, 11], fill=fg)
    d.rectangle([14, 8, 16, 11], fill=fg)
    d.rectangle([19, 7, 22, 9], fill=fg)
    cx, cy, r = 13, 17, 6
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=bg if bg_img is None else dither_light)
    d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=fg, width=1)
    for y in range(cy-r, cy+r+1):
        for x in range(cx-r, cx+r+1):
            if (x-cx)**2 + (y-cy)**2 <= (r-1)**2:
                im.putpixel((x, y), dither_light if (x + y) % 2 == 0 else dither_dark)
    return im

def dither_gradient(c_dark, c_light):
    bayer = [[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]
    im = Image.new("RGBA", (L, L))
    for y in range(L):
        for x in range(L):
            t = (x + y) / (2*(L-1))
            level = int(t * 16)
            on = level > bayer[y % 4][x % 4]
            im.putpixel((x, y), c_light if on else c_dark)
    return im

BLACK = (20, 20, 24, 255)
WHITE = (244, 244, 240, 255)

variants = {
    "1_BW":   draw_camera(BLACK, WHITE, BLACK, WHITE),
    "2_INV":  draw_camera(WHITE, BLACK, BLACK, WHITE),
    "3_DITH": draw_camera(WHITE, None, BLACK, (210,210,210,255),
                          bg_img=dither_gradient((28,30,52,255), (90,120,255,255))),
}

def upscale(im):
    return im.resize((SZ, SZ), Image.NEAREST)

for name, im in variants.items():
    flat = Image.new("RGB", (SZ, SZ), (255, 255, 255))
    big = upscale(im)
    flat.paste(big, (0, 0), big)
    flat.save(f"{PROJ}/pix_{name}_1024.png")

cell, pad = 360, 40
W = pad + (cell + pad) * 3
H = pad * 2 + cell + 60
sheet = Image.new("RGB", (W, H), (238, 238, 240))
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 40)
except Exception:
    font = ImageFont.load_default()
labels = ["1 BW", "2 INV", "3 DITHER"]
for i, (name, im) in enumerate(variants.items()):
    x = pad + i * (cell + pad); y = pad
    big = upscale(im)
    rad = int(SZ * 0.22)
    m = Image.new("L", (SZ, SZ), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, SZ-1, SZ-1], radius=rad, fill=255)
    prev = Image.new("RGBA", (SZ, SZ), (255,255,255,255)); prev.paste(big, (0,0), big)
    prev.putalpha(m)
    small = prev.resize((cell, cell), Image.LANCZOS)
    sheet.paste(small, (x, y), small)
    ImageDraw.Draw(sheet).text((x+10, y+cell+12), labels[i], font=font, fill=(40,40,50))
sheet.save(f"{PROJ}/PixelCam_concepts.png")
print("OK")
