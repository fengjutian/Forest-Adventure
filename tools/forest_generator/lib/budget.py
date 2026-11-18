"""预算检查，对应 docs/forest-pipeline-spec.md §3.3（超预算即失败，不静默截断）。

输入是 SceneSpec 的 ``budget`` 段与一批资产统计；输出是结构化 issue 列表。
超预算是 **error**：规格 §3.3 明确"超预算即失败，不静默截断"，不允许悄悄截掉 LOD 或材质。
"""

from __future__ import annotations

from typing import Any, Iterable

#: LOD 编号在统计字典里的键名
LOD_KEYS = ("lod0", "lod1", "lod2", "lod3")


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _issue(path: str, message: str) -> dict:
    return {"level": "error", "path": path, "message": message}


def check_budget(budget: dict, asset_stats: Iterable[dict]) -> list[dict]:
    """按 budget 段检查一批资产统计，超预算返回 error 级 issue。"""
    issues: list[dict] = []
    if not isinstance(budget, dict):
        return [_issue("budget", "budget 段缺失或格式错误")]

    for name in (
        "max_tris_lod0_per_asset",
        "max_tris_lod1_per_asset",
        "max_materials",
        "max_textures",
        "max_total_bytes",
    ):
        if name not in budget:
            issues.append(_issue(f"budget.{name}", f"budget 段缺少字段 '{name}'"))

    max_tris_lod0 = budget.get("max_tris_lod0_per_asset")
    max_tris_lod1 = budget.get("max_tris_lod1_per_asset")
    max_materials = budget.get("max_materials")
    max_textures = budget.get("max_textures")
    max_total_bytes = budget.get("max_total_bytes")

    total_materials = 0
    total_textures = 0
    total_bytes = 0

    for index, stat in enumerate(asset_stats or []):
        if not isinstance(stat, dict):
            continue
        key = stat.get("key") if isinstance(stat.get("key"), str) else f"#{index}"
        path = f"assets[{key}]"

        tris = stat.get("tris")
        tris = tris if isinstance(tris, dict) else {}
        lod0 = tris.get("lod0")
        if _is_int(lod0) and _is_int(max_tris_lod0) and lod0 > max_tris_lod0:
            issues.append(
                _issue(
                    f"{path}.tris.lod0",
                    f"LOD0 三角面 {lod0} 超过单资产预算 {max_tris_lod0}",
                )
            )
        lod1 = tris.get("lod1")
        if _is_int(lod1) and _is_int(max_tris_lod1) and lod1 > max_tris_lod1:
            issues.append(
                _issue(
                    f"{path}.tris.lod1",
                    f"LOD1 三角面 {lod1} 超过单资产预算 {max_tris_lod1}",
                )
            )

        materials = stat.get("materials")
        if _is_int(materials):
            total_materials += materials
        textures = stat.get("textures")
        if _is_int(textures):
            total_textures += textures
        size = stat.get("bytes")
        if _is_int(size):
            total_bytes += size

    if _is_int(max_materials) and total_materials > max_materials:
        issues.append(
            _issue(
                "budget.max_materials",
                f"材质总数 {total_materials} 超过预算 {max_materials}",
            )
        )
    if _is_int(max_textures) and total_textures > max_textures:
        issues.append(
            _issue(
                "budget.max_textures",
                f"纹理总数 {total_textures} 超过预算 {max_textures}",
            )
        )
    if _is_int(max_total_bytes) and total_bytes > max_total_bytes:
        issues.append(
            _issue(
                "budget.max_total_bytes",
                f"产物体积 {total_bytes} 字节超过预算 {max_total_bytes}",
            )
        )
    return issues
