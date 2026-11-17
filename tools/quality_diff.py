"""量化各画质档位相对基线的像素差异，避免只凭肉眼判断「看起来差不多」。

用法：python tools/quality_diff.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "screenshots" / "quality"
BASE = "q0_baseline"
TIERS = ["q1_msaa4", "q2_ssao", "q3_terrain40", "q4_terrain48"]


def load(tier: str, view: str) -> np.ndarray:
    return np.asarray(Image.open(SHOTS / f"{tier}_{view}.png").convert("RGB"), dtype=np.int16)


def main() -> None:
    for view in ("camp", "path"):
        base = load(BASE, view)
        print(f"[{view}]")
        for tier in TIERS:
            other = load(tier, view)
            diff = np.abs(base - other).mean(axis=2)
            changed = float((diff > 6).mean() * 100.0)
            print(f"  {tier:16s} mean_abs={diff.mean():5.2f} changed>6={changed:5.2f}%  max={diff.max():3.0f}")


if __name__ == "__main__":
    main()
