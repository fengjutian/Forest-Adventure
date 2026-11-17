"""抗锯齿 / 地形密度的放大对比（最近邻放大，看单个像素级的差别）。

用法：python tools/quality_zoom.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "screenshots" / "quality"

# 树冠斜边对天空：最容易看出锯齿的地方
AA_BOX = (300, 300, 420, 360)
# 地面阴影边界：地形网格密度不同时，阴影落在起伏上的边缘会不一样
TERRAIN_BOX = (700, 760, 940, 880)


def strip(tiers, box, out_name, zoom):
    w = (box[2] - box[0]) * zoom
    h = (box[3] - box[1]) * zoom
    canvas = Image.new("RGB", (30 + w * len(tiers), 24 + h), (18, 18, 18))
    draw = ImageDraw.Draw(canvas)
    for i, (tier, view) in enumerate(tiers):
        image = Image.open(SHOTS / f"{tier}_{view}.png").convert("RGB")
        patch = image.crop(box).resize((w, h), Image.NEAREST)
        canvas.paste(patch, (30 + i * w, 24))
        draw.text((30 + i * w + 4, 6), tier, fill=(255, 220, 120))
    out = SHOTS / out_name
    canvas.save(out)
    print(f"wrote {out} {canvas.size}")


if __name__ == "__main__":
    strip([("q0_baseline", "path"), ("q1_msaa4", "path"), ("q3_terrain40", "path")],
          AA_BOX, "zoom_aa.png", zoom=4)
    strip([("q1_msaa4", "path"), ("q2_ssao", "path"), ("q3_terrain40", "path")],
          TERRAIN_BOX, "zoom_terrain.png", zoom=2)
