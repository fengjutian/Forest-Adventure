"""资产形态参数派生，对应 docs/forest-pipeline-spec.md §5.3。

Blender 的随机数不参与资产形态生成：形态种子在这里定死，
Blender 只负责把确定下来的参数变成网格。

随机数发生器刻意不用标准库 ``random``：它的实现细节可能随版本变化，
而这里是跨工具、跨版本的长期契约。xorshift32 的算法完全写死在这个文件里。
"""

from __future__ import annotations

from .seed import derive_seed

#: xorshift32 的掩码
_MASK32 = 0xFFFFFFFF

#: 退化状态时使用的黄金比例常数（避免 seed 为 0 时序列全零）
_FALLBACK_STATE = 0x9E3779B9


class Rng:
    """确定性伪随机序列（xorshift32）。"""

    def __init__(self, seed: int) -> None:
        self._state = (seed & _MASK32) or _FALLBACK_STATE

    def next_u32(self) -> int:
        """下一个 32 位无符号随机数。"""
        x = self._state
        x ^= (x << 13) & _MASK32
        x ^= x >> 17
        x ^= (x << 5) & _MASK32
        self._state = x & _MASK32
        return self._state

    def unit(self) -> float:
        """[0, 1) 区间的浮点数。"""
        return self.next_u32() / 4294967296.0

    def uniform(self, low: float, high: float) -> float:
        """[low, high) 区间的浮点数。"""
        return low + (high - low) * self.unit()

    def jitter(self, amount: float) -> float:
        """[-amount, amount] 区间的对称扰动。"""
        return (self.unit() * 2.0 - 1.0) * amount


#: 各变体的形态模板。字段含义：
#: - ``height_range``     树高区间（米），对应 SceneSpec 的 height_m
#: - ``canopy_radius_ratio`` 树冠最大半径 / 树高
#: - ``canopy_overlap``   相邻树冠层的竖直重叠比例
#: - ``trunk_height_ratio`` 树干高度 / 树高
#: - ``trunk_radius_ratio`` 树干半径 / 树高
#: - ``color_variation``  颜色乘系数的浮动幅度（乘系数，不往白色混）
#: - ``top_lighten``      最顶层的颜色乘系数
_VARIANT_TEMPLATES: dict[str, dict] = {
    "pine": {
        "sides": 8,
        "tier_count": 3,
        "height_range": (7.5, 12.0),
        "canopy_radius_ratio": 0.235,
        "canopy_overlap": 0.18,
        "trunk_height_ratio": 0.44,
        "trunk_radius_ratio": 0.0215,
        "trunk_color": (0.27, 0.19, 0.14),
        "needle_color": (0.15, 0.29, 0.17),
        "top_lighten": 1.18,
        "color_variation": 0.22,
    },
}


#: LOD 精简规则：第 n 级 LOD 的边数与层数怎么减。
#: 规则写在 Python 侧（确定性契约在这里），Blender 只按给定参数建网格。
_LOD_RULES: dict[int, dict] = {
    0: {"sides_delta": 0, "tier_delta": 0},
    1: {"sides_delta": -3, "tier_delta": 0},
    2: {"sides_delta": -4, "tier_delta": -1},
    3: {"sides_delta": -5, "tier_delta": -2},
}


def _multiply(color: tuple[float, float, float], factor: float) -> list[float]:
    """颜色乘系数。

    一律用乘法而不是往白色插值：``lightened`` 会把饱和度冲掉，
    深棕经一次插值就变成灰砖，渲染出来像塑料。
    """
    return [min(1.0, max(0.0, c * factor)) for c in color]


def variant_of(key: str, asset_info: dict) -> str:
    """取资产的形态模板名。"""
    variant = str(asset_info.get("variant", ""))
    if variant in _VARIANT_TEMPLATES:
        return variant
    # 模板按变体名找；找不到就用键的词干（pine_0 → pine）
    stem = key.rsplit("_", 1)[0] if key.rsplit("_", 1)[-1].isdigit() else key
    if stem in _VARIANT_TEMPLATES:
        return stem
    raise ValueError(f"资产 '{key}' 没有形态模板（已知：{', '.join(sorted(_VARIANT_TEMPLATES))}）")


def derive_params(base_seed: int, key: str, asset_info: dict, lod: int = 0) -> dict:
    """从种子派生某个资产在某个 LOD 上的形态参数。

    返回的字典就是交给 Blender 的 build spec——它不含任何随机性，
    Blender 拿到同样的字典必然建出同样的网格。
    """
    variant = variant_of(key, asset_info)
    template = _VARIANT_TEMPLATES[variant]
    seed = derive_seed(base_seed, key)
    rng = Rng(seed)

    rule = _LOD_RULES.get(lod)
    if rule is None:
        raise ValueError(f"未知 LOD：{lod}")

    height_low, height_high = template["height_range"]
    height = rng.uniform(height_low, height_high)

    sides = max(3, int(template["sides"]) + int(rule["sides_delta"]))
    tier_count = max(1, int(template["tier_count"]) + int(rule["tier_delta"]))

    # 每层的半径微扰先按最大层数派生，再按实际层数截取——层数变化时微扰保持稳定
    base_tiers = int(template["tier_count"])
    jitter = [round(rng.jitter(0.08), 6) for _ in range(base_tiers)]
    tier_jitter = jitter[:tier_count]

    variation = float(template["color_variation"])
    trunk_factor = 1.0 + rng.jitter(variation * 0.5)
    needle_factor = 1.0 + rng.jitter(variation * 0.5)

    trunk_color = _multiply(template["trunk_color"], trunk_factor)
    needle_color = _multiply(template["needle_color"], needle_factor)
    needle_color_top = _multiply(template["needle_color"], needle_factor * float(template["top_lighten"]))

    return {
        "key": key,
        "variant": variant,
        "lod": lod,
        "seed": seed,
        "height_m": round(height, 4),
        "trunk_radius": round(height * float(template["trunk_radius_ratio"]), 4),
        "trunk_height": round(height * float(template["trunk_height_ratio"]), 4),
        "sides": sides,
        "tier_count": tier_count,
        "canopy_radius": round(height * float(template["canopy_radius_ratio"]), 4),
        "canopy_overlap": float(template["canopy_overlap"]),
        "tier_jitter": tier_jitter,
        "trunk_color": trunk_color,
        "needle_color": needle_color,
        "needle_color_top": needle_color_top,
    }


def collision_from_params(params: dict, collision_type: str) -> dict:
    """由形态参数推出碰撞代理的尺寸。

    胶囊的半径取树干半径——树冠不需要碰撞，撞上去的应该是树干。
    """
    if collision_type == "none":
        return {"type": "none"}
    if collision_type == "capsule":
        return {
            "type": "capsule",
            "radius": round(float(params["trunk_radius"]), 4),
            "height": round(float(params["height_m"]), 4),
        }
    if collision_type == "box":
        radius = float(params["canopy_radius"])
        return {
            "type": "box",
            "size": [
                round(radius * 2.0, 4),
                round(float(params["height_m"]), 4),
                round(radius * 2.0, 4),
            ],
        }
    raise ValueError(f"未知碰撞类型：{collision_type}")
