"""资产形态参数派生的测试，对应 docs/forest-pipeline-spec.md §4.1 / §5.3。

形态参数是管线与 Blender 之间的契约：同样的种子必须给出同样的参数，
不同 LOD 必须给出逐步简化的几何，颜色必须用乘系数（保住色相）。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import asset_keys, params  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
PRESET = REPO_ROOT / "tools" / "forest_generator" / "presets" / "pine_valley.json"


@pytest.fixture(scope="module")
def preset() -> dict:
    return json.loads(PRESET.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def pine_info() -> dict:
    return asset_keys.KEY_INFO["pine_0"]


# ------------------------------------------------------------------ 确定性


def test_same_seed_same_params(pine_info):
    a = params.derive_params(41721, "pine_0", pine_info, 0)
    b = params.derive_params(41721, "pine_0", pine_info, 0)
    assert a == b


def test_different_seed_different_params(pine_info):
    a = params.derive_params(41721, "pine_0", pine_info, 0)
    b = params.derive_params(41722, "pine_0", pine_info, 0)
    assert a != b


def test_params_contain_no_float_noise(pine_info):
    """参数必须是可 JSON 往返的有限值，不能有 NaN / Inf。"""
    p = params.derive_params(41721, "pine_0", pine_info, 0)
    json.dumps(p, allow_nan=False)  # allow_nan=False 会在出现 NaN/Inf 时抛错


def test_unknown_variant_raises(pine_info):
    with pytest.raises(ValueError):
        params.derive_params(41721, "mystery", {"variant": "mystery"}, 0)


# ------------------------------------------------------------------ LOD 规则


def test_lod_reduces_sides_and_tiers(pine_info):
    lod0 = params.derive_params(41721, "pine_0", pine_info, 0)
    lod1 = params.derive_params(41721, "pine_0", pine_info, 1)
    lod2 = params.derive_params(41721, "pine_0", pine_info, 2)
    assert lod0["sides"] > lod1["sides"] > lod2["sides"]
    assert lod0["tier_count"] >= lod1["tier_count"] > lod2["tier_count"]
    assert lod2["sides"] >= 3
    assert lod2["tier_count"] >= 1


def test_lod_keeps_shape_identical(pine_info):
    """LOD 只减面不改形：高度、冠幅、颜色在各级 LOD 之间必须一致。"""
    lod0 = params.derive_params(41721, "pine_0", pine_info, 0)
    lod2 = params.derive_params(41721, "pine_0", pine_info, 2)
    for field in ("height_m", "canopy_radius", "trunk_radius", "trunk_height",
                  "canopy_overlap", "trunk_color", "needle_color", "needle_color_top"):
        assert lod0[field] == lod2[field], field


def test_lod_jitter_is_prefix_stable(pine_info):
    """层数变少时保留的微扰必须是原序列的前缀，不能重新抽。"""
    lod0 = params.derive_params(41721, "pine_0", pine_info, 0)
    lod2 = params.derive_params(41721, "pine_0", pine_info, 2)
    assert lod2["tier_jitter"] == lod0["tier_jitter"][: len(lod2["tier_jitter"])]


def test_unknown_lod_raises(pine_info):
    with pytest.raises(ValueError):
        params.derive_params(41721, "pine_0", pine_info, 9)


# ------------------------------------------------------------------ 尺寸区间


def test_height_within_specified_range(preset, pine_info):
    entry = preset["assets"]["vegetation"][0]
    assert entry["key"] == "pine_0"
    low, high = entry["height_m"]
    for lod in (0, 1, 2):
        p = params.derive_params(preset["seed"], "pine_0", pine_info, lod)
        assert low <= p["height_m"] <= high


def test_all_pine_variants_differ(preset):
    """5 个松树变体的形态必须互不相同，否则林子里全是同一棵树。"""
    shapes = set()
    for index in range(5):
        key = f"pine_{index}"
        p = params.derive_params(preset["seed"], key, asset_keys.KEY_INFO[key], 0)
        shapes.add((p["height_m"], p["canopy_radius"], tuple(p["needle_color"])))
    assert len(shapes) == 5


# ------------------------------------------------------------------ 颜色契约


def test_colors_use_multiplier_not_lerp_to_white(pine_info):
    """颜色必须是基色乘系数：不能出现"往白色插值"式的分量抬升。

    ``lightened()`` 会把饱和度冲掉——深棕经一次插值就变成灰砖，
    渲染出来像塑料。乘系数保色相。
    """
    base_trunk = (0.27, 0.19, 0.14)
    base_needle = (0.15, 0.29, 0.17)
    for base_seed in (0, 1, 41721, 20261117, 4294967295):
        p = params.derive_params(base_seed, "pine_0", pine_info, 0)
        trunk = p["trunk_color"]
        needle = p["needle_color"]
        # 三个分量必须同比例缩放（比例一致 = 纯乘法）
        ratios = [t / b for t, b in zip(trunk, base_trunk)]
        assert max(ratios) - min(ratios) < 1e-6, (base_seed, trunk, ratios)
        ratios = [n / b for n, b in zip(needle, base_needle)]
        assert max(ratios) - min(ratios) < 1e-6, (base_seed, needle, ratios)
        # 乘系数幅度受控，不会把颜色冲白
        assert all(0.0 <= c <= 1.0 for c in trunk + needle)


def test_top_layer_is_brighter_than_middle(pine_info):
    p = params.derive_params(41721, "pine_0", pine_info, 0)
    assert sum(p["needle_color_top"]) > sum(p["needle_color"])


# ------------------------------------------------------------------ 文件命名


def test_glb_filename_follows_naming_rule():
    """命名规范见 content-pipeline.md §4.2：env_<category>_<name>_<variant>_lod<N>。"""
    assert asset_keys.glb_filename("pine_0", 0) == "env_tree_pine_a_lod0.glb"
    assert asset_keys.glb_filename("pine_4", 2) == "env_tree_pine_e_lod2.glb"
    assert asset_keys.glb_filename("birch_1", 0) == "env_tree_birch_b_lod0.glb"
    assert asset_keys.glb_filename("rock", 0) == "env_rock_rock_a_lod0.glb"
    assert asset_keys.glb_filename("cabin", 1) == "env_building_cabin_a_lod1.glb"


def test_every_key_has_a_gltf_category():
    for key in asset_keys.ASSET_KEYS:
        assert key in asset_keys.GLTF_CATEGORY, key
        assert asset_keys.glb_filename(key, 0).endswith("_lod0.glb")


def test_asset_name_splits_index():
    assert asset_keys.asset_name("pine_3") == ("pine", "d")
    assert asset_keys.asset_name("rock") == ("rock", "a")


# ------------------------------------------------------------------ 碰撞代理


def test_collision_proxy_types(pine_info):
    p = params.derive_params(41721, "pine_0", pine_info, 0)
    capsule = params.collision_from_params(p, "capsule")
    assert capsule["type"] == "capsule"
    assert capsule["radius"] == pytest.approx(p["trunk_radius"])
    assert capsule["height"] == pytest.approx(p["height_m"])

    assert params.collision_from_params(p, "none") == {"type": "none"}

    box = params.collision_from_params(p, "box")
    assert box["type"] == "box"
    assert len(box["size"]) == 3

    with pytest.raises(ValueError):
        params.collision_from_params(p, "mesh")
