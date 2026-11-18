"""资产键表与运行时接缝的单测，对应 docs/forest-pipeline-spec.md §4.1。

除了静态断言，还要**反向解析 Godot 源码**核对：
改了运行时的变体数量而忘了同步管线，测试会直接失败。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import asset_keys  # noqa: E402

#: 仓库根目录（tests → forest_generator → tools → 仓库根）
REPO_ROOT = Path(__file__).resolve().parents[3]
GOLDEN_PATH = REPO_ROOT / "game" / "tests" / "fixtures" / "seed_golden.json"

WORLD_CHUNK = REPO_ROOT / "game" / "scripts" / "world" / "world_chunk.gd"
PROP_KIT = REPO_ROOT / "game" / "scripts" / "world" / "prop_kit.gd"
CHUNKED_WORLD = REPO_ROOT / "game" / "scripts" / "world" / "chunked_world.gd"
CAMP_BUILDER = REPO_ROOT / "game" / "scripts" / "world" / "camp_builder.gd"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    """截取某个函数体：从签名到下一个顶层函数定义之前。"""
    start = source.index(signature)
    rest = source[start:]
    match = re.search(r"\n(?:static )?func ", rest)
    return rest[: match.start()] if match else rest


def test_key_counts() -> None:
    """13 个植被键 + 16 个道具键 = 29 个键。"""
    assert len(asset_keys.ASSET_KEYS) == 29
    assert len(asset_keys.VEGETATION_KEYS) == 13
    assert len(asset_keys.PROP_KEYS) == 16


def test_no_duplicates() -> None:
    """三个列表内部都没有重复键。"""
    assert len(set(asset_keys.ASSET_KEYS)) == 29
    assert len(set(asset_keys.VEGETATION_KEYS)) == 13
    assert len(set(asset_keys.PROP_KEYS)) == 16


def test_union_is_all_keys() -> None:
    """植被与道具的并集恰好是 29 个键，且互不相交。"""
    union = set(asset_keys.VEGETATION_KEYS) | set(asset_keys.PROP_KEYS)
    assert union == set(asset_keys.ASSET_KEYS)
    assert len(union) == 29
    assert not set(asset_keys.VEGETATION_KEYS) & set(asset_keys.PROP_KEYS)


def test_matches_golden_fixture() -> None:
    """与黄金文件里的键表完全一致。"""
    golden = json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))
    assert asset_keys.ASSET_KEYS == golden["asset_keys"]
    assert asset_keys.VEGETATION_KEYS == golden["vegetation_keys"]
    assert asset_keys.PROP_KEYS == golden["prop_keys"]


def test_key_info_entries() -> None:
    """每个键都有 key / category / seam / variant 四个字段。"""
    for key in asset_keys.ASSET_KEYS:
        info = asset_keys.KEY_INFO[key]
        assert info["key"] == key
        assert info["category"] in (asset_keys.CATEGORY_VEGETATION, asset_keys.CATEGORY_PROP)
        assert info["seam"] in (
            asset_keys.SEAM_MESH_FOR,
            asset_keys.SEAM_MAKE_PROP,
        )
        assert isinstance(info["variant"], str) and info["variant"]


def test_known_tags() -> None:
    """§3.3 的已知标签集合。"""
    assert asset_keys.KNOWN_TAGS == {"sway", "authored", "emissive"}


def test_tree_variant_counts_match_world_chunk() -> None:
    """pine_*/birch_* 的数量必须等于 world_chunk.gd 的变体常量。"""
    source = _read(WORLD_CHUNK)
    pine_match = re.search(r"const PINE_VARIANTS := (\d+)", source)
    birch_match = re.search(r"const BIRCH_VARIANTS := (\d+)", source)
    assert pine_match is not None and birch_match is not None
    pine_variants = int(pine_match.group(1))
    birch_variants = int(birch_match.group(1))
    pine_keys = [key for key in asset_keys.VEGETATION_KEYS if key.startswith("pine_")]
    birch_keys = [key for key in asset_keys.VEGETATION_KEYS if key.startswith("birch_")]
    assert len(pine_keys) == pine_variants
    assert len(birch_keys) == birch_variants


def test_make_prop_branches_match_runtime() -> None:
    """PropKit.make_prop() 的 match 分支必须与 make_prop 接缝的键一致。"""
    body = _function_body(_read(PROP_KIT), "static func make_prop(")
    branches = set(re.findall(r'&"([a-z_]+)":', body))
    expected = set(asset_keys.keys_by_seam(asset_keys.SEAM_MAKE_PROP))
    assert branches == expected
    assert len(expected) == 16


def test_mesh_for_branches_match_runtime() -> None:
    """ChunkedWorld 的程序化回退必须覆盖全部植被键。

    ``mesh_for()`` 现在先查管线产出的 GLB，回退逻辑拆到了
    ``_procedural_mesh_for()``——植被键的分支必须都在那里。
    """
    body = _function_body(_read(CHUNKED_WORLD), "func _procedural_mesh_for(")
    for key in ("snag", "log", "stump", "rock", "shrub", "grass"):
        assert f'"{key}"' in body
    # pine_/birch_ 是前缀分支，不是精确匹配
    assert 'key.begins_with("pine_")' in body
    assert 'key.begins_with("birch_")' in body


def test_mesh_for_prefers_generated_assets() -> None:
    """运行时取网格的顺序：先管线产物，再回退 PropKit。"""
    body = _function_body(_read(CHUNKED_WORLD), "func mesh_for(")
    assert "AssetLibrary.mesh_for(key)" in body
    assert "_procedural_mesh_for(key)" in body
    assert body.index("AssetLibrary.mesh_for(key)") < body.index("_procedural_mesh_for(key)")


def test_camp_builder_uses_string_keys_for_props() -> None:
    """营地装配处的道具必须走字符串键，不能再硬编码 PropKit.make_xxx()。

    硬编码调用意味着运行时没有键可查，管线产的 GLB 接不上——
    这正是 §4.1 曾经存在的 ``direct`` 接缝。
    """
    source = _read(CAMP_BUILDER)
    for key in asset_keys.keys_by_seam(asset_keys.SEAM_MAKE_PROP):
        assert f"PropKit.make_{key}()" not in source, f"{key} 不应再硬编码调用"
    # 营地实际用到的道具键必须走字符串键
    for key in ("cabin", "cabin_windows", "supply_shed", "generator", "target",
                "signpost", "tent", "lantern_post", "lantern_glass", "woodpile", "barrel"):
        assert f'PropKit.make_prop(&"{key}")' in source, f"{key} 应当走字符串键"


def test_no_direct_seam_remains() -> None:
    """M3-2 之后不再有「没有字符串键接缝」的键。"""
    assert set(asset_keys.keys_by_seam(asset_keys.SEAM_MESH_FOR)) | set(
        asset_keys.keys_by_seam(asset_keys.SEAM_MAKE_PROP)
    ) == set(asset_keys.ASSET_KEYS)
