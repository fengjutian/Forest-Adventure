"""把画质档位截图按 1:1 裁切拼版，用来判断抗锯齿、环境光遮蔽和地形密度的真实差异。

用法：
    python tools/quality_compare.py
输出：
    build/screenshots/quality/compare_camp.png
    build/screenshots/quality/compare_path.png
    build/screenshots/quality/before_after_camp.png
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "screenshots" / "quality"

TIERS = ["q0_baseline", "q1_msaa4", "q2_ssao", "q3_terrain40", "q4_terrain48"]

# 机位 -> 裁切区域（左, 上, 右, 下），1:1 像素，取最能看出差异的地方
CROPS = {
    "camp": {
        "tree_edge": (700, 300, 960, 446),
        "stone_base": (840, 560, 1100, 706),
        "porch": (250, 430, 510, 576),
    },
    "path": {
        "canopy": (700, 180, 960, 326),
        "ground": (900, 780, 1160, 926),
    },
}

SCALE = 2


def load(tier: str, view: str) -> Image.Image:
    return Image.open(SHOTS / f"{tier}_{view}.png").convert("RGB")


def compose(view: str) -> None:
    regions = CROPS[view]
    w = (regions[list(regions)[0]][2] - regions[list(regions)[0]][0]) * SCALE
    h = (regions[list(regions)[0]][3] - regions[list(regions)[0]][1]) * SCALE
    label_w = 150
    canvas = Image.new("RGB", (label_w + w * len(regions), 24 + h * len(TIERS)), (20, 20, 20))
    draw = ImageDraw.Draw(canvas)

    for col, (name, box) in enumerate(regions.items()):
        x = label_w + col * w
        draw.text((x + 6, 6), name, fill=(235, 235, 235))

    for row, tier in enumerate(TIERS):
        image = load(tier, view)
        y = 24 + row * h
        draw.text((6, y + h // 2 - 6), tier, fill=(235, 235, 235))
        for col, box in enumerate(regions.values()):
            patch = image.crop(box).resize((w, h), Image.NEAREST)
            canvas.paste(patch, (label_w + col * w, y))

    out = SHOTS / f"compare_{view}.png"
    canvas.save(out)
    print(f"wrote {out} {canvas.size}")


def before_after(view: str) -> None:
    """整帧并排：左 = 改动前（q0_baseline），右 = 当前默认（q3_terrain40）。"""
    before, after = load("q0_baseline", view), load("q3_terrain40", view)
    half = (960, 540)
    canvas = Image.new("RGB", (half[0] * 2, 24 + half[1]), (20, 20, 20))
    draw = ImageDraw.Draw(canvas)
    canvas.paste(before.resize(half), (0, 24))
    canvas.paste(after.resize(half), (half[0], 24))
    draw.text((6, 6), "before: MSAA 2x, no AO, 2.0 m terrain", fill=(235, 235, 235))
    draw.text((half[0] + 6, 6), "after: MSAA 4x, SSAO, 1.6 m terrain", fill=(235, 235, 235))
    out = SHOTS / f"before_after_{view}.png"
    canvas.save(out)
    print(f"wrote {out} {canvas.size}")


if __name__ == "__main__":
    for view in CROPS:
        compose(view)
    before_after("camp")
