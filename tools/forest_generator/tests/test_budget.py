"""预算检查的单测，对应 docs/forest-pipeline-spec.md §3.3。

超预算是 error：规格 §3.3 明确"超预算即失败，不静默截断"。
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.budget import check_budget  # noqa: E402

BUDGET = {
    "max_tris_lod0_per_asset": 900,
    "max_tris_lod1_per_asset": 300,
    "max_materials": 24,
    "max_textures": 48,
    "max_total_bytes": 33554432,
}


def _stat(key: str, lod0: int = 100, lod1: int = 40, materials: int = 1, textures: int = 0,
          size: int = 1024) -> dict:
    return {
        "key": key,
        "tris": {"lod0": lod0, "lod1": lod1},
        "materials": materials,
        "textures": textures,
        "bytes": size,
    }


def test_within_budget_has_no_issue() -> None:
    """预算内的资产统计不产出 issue。"""
    stats = [_stat(f"key_{index}") for index in range(10)]
    assert check_budget(BUDGET, stats) == []


def test_lod0_over_budget_is_error() -> None:
    """单资产 LOD0 三角面超预算。"""
    issues = check_budget(BUDGET, [_stat("pine_0", lod0=901)])
    assert issues
    assert issues[0]["level"] == "error"
    assert "lod0" in issues[0]["path"]


def test_lod1_over_budget_is_error() -> None:
    """单资产 LOD1 三角面超预算。"""
    issues = check_budget(BUDGET, [_stat("pine_0", lod1=301)])
    assert issues
    assert "lod1" in issues[0]["path"]


def test_materials_over_budget_is_error() -> None:
    """材质总数超预算。"""
    stats = [_stat(f"key_{index}", materials=5) for index in range(6)]
    issues = check_budget(BUDGET, stats)
    assert issues
    assert any("max_materials" in issue["path"] for issue in issues)


def test_textures_over_budget_is_error() -> None:
    """纹理总数超预算。"""
    stats = [_stat(f"key_{index}", textures=25) for index in range(3)]
    issues = check_budget(BUDGET, stats)
    assert issues
    assert any("max_textures" in issue["path"] for issue in issues)


def test_total_bytes_over_budget_is_error() -> None:
    """产物体积超预算。"""
    stats = [_stat("pine_0", size=33554433)]
    issues = check_budget(BUDGET, stats)
    assert issues
    assert any("max_total_bytes" in issue["path"] for issue in issues)


def test_exact_budget_is_allowed() -> None:
    """刚好等于预算不算超预算。"""
    stats = [_stat("pine_0", lod0=900, lod1=300, materials=24, textures=48, size=33554432)]
    assert check_budget(BUDGET, stats) == []


def test_missing_budget_is_error() -> None:
    """budget 缺失时给出明确的 error。"""
    issues = check_budget({}, [_stat("pine_0")])
    assert issues
    assert issues[0]["level"] == "error"
