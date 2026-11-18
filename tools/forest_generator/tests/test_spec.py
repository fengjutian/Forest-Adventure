"""SceneSpec 两层校验的单测，对应 docs/forest-pipeline-spec.md §3.2 / §3.3 / §4.1。

合法的 preset 必须 0 error；每一种非法输入都必须报错（M3-1 的硬性退出条件）。
"""

from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import asset_keys  # noqa: E402
from lib.spec import validate_spec  # noqa: E402

#: 仓库根目录（tests → forest_generator → tools → 仓库根）
REPO_ROOT = Path(__file__).resolve().parents[3]
PRESET_PATH = REPO_ROOT / "tools" / "forest_generator" / "presets" / "pine_valley.json"
TERRAIN_FIELD = REPO_ROOT / "game" / "scripts" / "world" / "terrain_field.gd"
WORLD_CHUNK = REPO_ROOT / "game" / "scripts" / "world" / "world_chunk.gd"

PRESET = json.loads(PRESET_PATH.read_text(encoding="utf-8"))


def _spec() -> dict:
    """preset 的深拷贝，用来做破坏性修改。"""
    return copy.deepcopy(PRESET)


def _issues(spec: dict) -> list[dict]:
    return validate_spec(spec)


def _errors(spec: dict) -> list[dict]:
    return [issue for issue in _issues(spec) if issue["level"] == "error"]


def _warnings(spec: dict) -> list[dict]:
    return [issue for issue in _issues(spec) if issue["level"] == "warning"]


def _entry(spec: dict, category: str, key: str) -> dict:
    """按 key 取一个资产条目。"""
    for item in spec["assets"][category]:
        if item["key"] == key:
            return item
    raise KeyError(key)


# ------------------------------------------------------------------ 合法输入


def test_preset_is_valid() -> None:
    """presets/pine_valley.json 必须 0 error。"""
    assert _errors(PRESET) == []


def test_preset_covers_all_29_keys() -> None:
    """植被 13 个 + 道具 16 个，既不缺也不多。"""
    keys = [item["key"] for item in PRESET["assets"]["vegetation"]]
    keys += [item["key"] for item in PRESET["assets"]["props"]]
    assert len(keys) == 29
    assert sorted(keys) == sorted(asset_keys.ASSET_KEYS)
    assert len(set(keys)) == 29


def test_preset_seed_and_region() -> None:
    """preset 的固定身份字段。"""
    assert PRESET["schema_version"] == "1.1"
    assert PRESET["seed"] == 41721
    assert PRESET["region"]["id"] == "pine_valley"
    assert PRESET["region"]["size_m"] == [1024, 1024]


def test_preset_budget_and_export() -> None:
    """preset 的预算与导出配置。"""
    assert PRESET["budget"] == {
        "max_tris_lod0_per_asset": 900,
        "max_tris_lod1_per_asset": 300,
        "max_materials": 24,
        "max_textures": 48,
        "max_total_bytes": 33554432,
    }
    assert PRESET["export"] == {
        "format": "glb",
        "apply_transform": True,
        "material_mode": "vertex_color",
    }


def test_preset_world_matches_runtime_constants() -> None:
    """world 段逐项等于运行时常量（§3.4）。"""
    terrain = TERRAIN_FIELD.read_text(encoding="utf-8")
    chunk = WORLD_CHUNK.read_text(encoding="utf-8")

    def gdscript_float(source: str, pattern: str) -> float:
        match = re.search(pattern, source)
        assert match is not None, pattern
        return float(match.group(1))

    world = PRESET["world"]
    for name in (
        "amplitude",
        "macro_amplitude",
        "detail_amplitude",
        "ridge_center_z",
        "ridge_width",
        "ridge_height",
    ):
        expected = gdscript_float(terrain, rf"var {name}: float = ([-\d.]+)")
        assert world["terrain"][name] == pytest.approx(expected)
    for name, gdscript_name in (
        ("center_x", "creek_center_x"),
        ("half_width", "creek_half_width"),
        ("depth", "creek_depth"),
    ):
        expected = gdscript_float(terrain, rf"var {gdscript_name}: float = ([-\d.]+)")
        assert world["creek"][name] == pytest.approx(expected)
    for name, gdscript_name in (
        ("flat_radius", "camp_flat_radius"),
        ("blend_radius", "camp_blend_radius"),
        ("height", "camp_height"),
    ):
        expected = gdscript_float(terrain, rf"var {gdscript_name}: float = ([-\d.]+)")
        assert world["camp"][name] == pytest.approx(expected)
    for name, constant in (
        ("birch_ratio", "BIRCH_RATIO"),
        ("snag_ratio", "SNAG_RATIO"),
        ("deadwood_ratio", "DEADWOOD_RATIO"),
        ("rock_density", "ROCK_DENSITY"),
        ("shrub_density", "SHRUB_DENSITY"),
        ("ground_cover_density", "GROUND_COVER_DENSITY"),
    ):
        expected = gdscript_float(chunk, rf"const {constant} := ([-\d.]+)")
        assert world["vegetation"][name] == pytest.approx(expected)
    max_density = gdscript_float(chunk, r"vegetation_density\([^,]+, [^,]+, ([-\d.]+)\)")
    assert world["vegetation"]["max_density"] == pytest.approx(max_density)


def test_valid_preset_has_no_warnings() -> None:
    """M3-2 补齐接缝之后，合法 preset 不该再有任何 warning。

    早先这里断言「direct 接缝的 5 个键产出 warning」——接缝补齐后那一类警告消失了。
    """
    assert _errors(PRESET) == []
    assert _warnings(PRESET) == []


# ------------------------------------------------------------------ 非法输入


def test_wrong_schema_version_fails() -> None:
    spec = _spec()
    spec["schema_version"] = "1.0"
    assert _errors(spec)


def test_missing_region_fails() -> None:
    spec = _spec()
    del spec["region"]
    assert _errors(spec)


def test_missing_budget_fails() -> None:
    spec = _spec()
    del spec["budget"]
    assert _errors(spec)


def test_missing_assets_fails() -> None:
    spec = _spec()
    del spec["assets"]
    assert _errors(spec)


@pytest.mark.parametrize("region_id", ["Pine Valley", "1bad", "bad-id"])
def test_bad_region_id_fails(region_id: str) -> None:
    spec = _spec()
    spec["region"]["id"] = region_id
    assert _errors(spec)


def test_zero_size_m_fails() -> None:
    spec = _spec()
    spec["region"]["size_m"] = [0, 1024]
    assert _errors(spec)


def test_negative_size_m_fails() -> None:
    spec = _spec()
    spec["region"]["size_m"] = [1024, -1]
    assert _errors(spec)


def test_negative_seed_fails() -> None:
    spec = _spec()
    spec["seed"] = -1
    assert _errors(spec)


def test_seed_too_large_fails() -> None:
    spec = _spec()
    spec["seed"] = 2**31
    assert _errors(spec)


def test_unknown_asset_key_fails() -> None:
    spec = _spec()
    spec["assets"]["vegetation"][0]["key"] = "mystery_tree"
    errors = _errors(spec)
    assert errors
    assert any("mystery_tree" in issue["message"] for issue in errors)


def test_missing_key_fails() -> None:
    """29 → 28：少一个键必须报完整性错误。"""
    spec = _spec()
    spec["assets"]["props"] = [
        item for item in spec["assets"]["props"] if item["key"] != "barrel"
    ]
    errors = _errors(spec)
    assert errors
    assert any("barrel" in issue["message"] for issue in errors)


def test_duplicate_key_fails() -> None:
    """重复键必须报错。"""
    spec = _spec()
    duplicate = copy.deepcopy(spec["assets"]["props"][0])
    duplicate["variant"] = "building_b"
    spec["assets"]["props"].append(duplicate)
    errors = _errors(spec)
    assert errors
    assert any("重复" in issue["message"] for issue in errors)


def test_reversed_height_m_fails() -> None:
    spec = _spec()
    _entry(spec, "vegetation", "pine_0")["height_m"] = [3.0, 1.0]
    assert _errors(spec)


def test_non_positive_height_m_fails() -> None:
    spec = _spec()
    _entry(spec, "vegetation", "rock")["height_m"] = [0.0, 1.8]
    assert _errors(spec)


def test_non_contiguous_lods_fail() -> None:
    spec = _spec()
    _entry(spec, "vegetation", "pine_0")["lods"] = [0, 2]
    assert _errors(spec)


def test_lods_not_starting_at_zero_fail() -> None:
    spec = _spec()
    _entry(spec, "vegetation", "pine_0")["lods"] = [1, 2]
    assert _errors(spec)


def test_invalid_collision_fails() -> None:
    spec = _spec()
    _entry(spec, "vegetation", "pine_0")["collision"] = "mesh"
    assert _errors(spec)


def test_unknown_tag_fails() -> None:
    spec = _spec()
    _entry(spec, "vegetation", "pine_0")["tags"] = ["glowing"]
    assert _errors(spec)


def test_invalid_material_mode_fails() -> None:
    spec = _spec()
    spec["export"]["material_mode"] = "pbr"
    assert _errors(spec)


def test_non_positive_budget_fails() -> None:
    spec = _spec()
    spec["budget"]["max_tris_lod0_per_asset"] = 0
    assert _errors(spec)


def test_missing_world_field_fails() -> None:
    spec = _spec()
    del spec["world"]["creek"]
    assert _errors(spec)


def test_unknown_top_level_field_fails() -> None:
    spec = _spec()
    spec["surprise"] = 1
    assert _errors(spec)
