"""SceneSpec 两层校验，对应 docs/forest-pipeline-spec.md §3.2 / §3.3 / §4.1。

第一层（schema 层）用 ``lib/jsonschema_mini.py`` 校验 ``schemas/scene_spec.schema.json``；
第二层（语义层）校验 schema 表达不了的跨字段规则：

1. ``assets.*[].key`` 必须 ∈ ``asset_keys.ASSET_KEYS``；
2. 完整性：``assets.vegetation`` + ``assets.props`` 的键并集恰好等于全部 29 个键；
3. ``height_m[0] < height_m[1]``，且两者都 > 0；
4. ``lods`` 升序、连续、从 0 开始；
5. ``tags`` 元素 ∈ ``asset_keys.KNOWN_TAGS``；
6. ``region.size_m`` 两项均 > 0；
7. ``budget`` 各字段范围合法。

issue 结构：``{"level": "error"|"warning", "path": ..., "message": ...}``。
schema 层的 ``path`` 是 JSON Pointer（``/assets/vegetation/0/height_m/1``），
语义层的 ``path`` 是点号风格（``assets.vegetation[3].height_m``）。
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterator

from . import asset_keys
from .jsonschema_mini import validate as validate_against_schema

#: SceneSpec 的规格版本（§3.3：不兼容变更必须升主版本）
SCHEMA_VERSION = "1.1"

#: schema 文件位置
SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schemas" / "scene_spec.schema.json"

_SCHEMA_CACHE: dict | None = None


def load_schema(path: Path | None = None) -> dict:
    """读取并缓存 SceneSpec JSON Schema。"""
    global _SCHEMA_CACHE
    if path is None:
        if _SCHEMA_CACHE is None:
            _SCHEMA_CACHE = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        return _SCHEMA_CACHE
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_spec(path: Path | str) -> Any:
    """读取 SceneSpec JSON 文件。"""
    return json.loads(Path(path).read_text(encoding="utf-8"))


def validate_spec(spec: Any, schema: dict | None = None) -> list[dict]:
    """两层校验 SceneSpec，返回 issue 列表（level/path/message）。"""
    issues: list[dict] = []
    schema_doc = load_schema() if schema is None else schema
    try:
        schema_errors = validate_against_schema(spec, schema_doc)
    except ValueError as exc:  # schema 自身有问题（例如非法 $ref）
        return [{"level": "error", "path": "", "message": f"schema 无法解析：{exc}"}]
    for error in schema_errors:
        issues.append(
            {"level": "error", "path": error["path"], "message": error["message"]}
        )
    issues.extend(_semantic_issues(spec))
    return issues


def format_issue(issue: dict) -> str:
    """把 issue 格式化成一行可读文本。"""
    return f"[{issue['level']}] {issue['path']}: {issue['message']}"


# ------------------------------------------------------------------ 语义层


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _entries(spec: Any) -> Iterator[tuple[str, int, dict]]:
    """遍历 ``assets.vegetation`` 与 ``assets.props``，产出 (类别, 下标, 条目)。"""
    if not isinstance(spec, dict):
        return
    assets = spec.get("assets")
    if not isinstance(assets, dict):
        return
    for category in ("vegetation", "props"):
        items = assets.get(category)
        if not isinstance(items, list):
            continue
        for index, entry in enumerate(items):
            if isinstance(entry, dict):
                yield category, index, entry


def _semantic_issues(spec: Any) -> list[dict]:
    issues: list[dict] = []
    issues.extend(_check_asset_keys(spec))
    issues.extend(_check_completeness(spec))
    issues.extend(_check_entries(spec))
    issues.extend(_check_region(spec))
    issues.extend(_check_budget(spec))
    issues.extend(_check_world(spec))
    return issues


#: SceneSpec 的资产数组名 → §4.1 的类别名
_CATEGORY_BY_ARRAY = {
    "vegetation": asset_keys.CATEGORY_VEGETATION,
    "props": asset_keys.CATEGORY_PROP,
}


def _check_asset_keys(spec: Any) -> list[dict]:
    """规则 1：键必须在 §4.1 的已知键表内。"""
    issues: list[dict] = []
    for category, index, entry in _entries(spec):
        key = entry.get("key")
        if not isinstance(key, str):
            continue
        if key not in asset_keys.ASSET_KEYS:
            issues.append(
                {
                    "level": "error",
                    "path": f"assets.{category}[{index}].key",
                    "message": f"未知资产键 '{key}'，必须 ∈ §4.1 的 29 个已知键",
                }
            )
            continue
        expected_category = asset_keys.KEY_INFO[key]["category"]
        if expected_category != _CATEGORY_BY_ARRAY[category]:
            issues.append(
                {
                    "level": "warning",
                    "path": f"assets.{category}[{index}].key",
                    "message": (
                        f"键 '{key}' 属于 {expected_category} 类别，却出现在 "
                        f"assets.{category} 中"
                    ),
                }
            )
    return issues


def _check_completeness(spec: Any) -> list[dict]:
    """规则 2：29 个键既不缺也不多，且不重复。"""
    issues: list[dict] = []
    seen: dict[str, str] = {}
    for category, index, entry in _entries(spec):
        key = entry.get("key")
        if not isinstance(key, str):
            continue
        if key in seen:
            issues.append(
                {
                    "level": "error",
                    "path": f"assets.{category}[{index}].key",
                    "message": f"键 '{key}' 重复出现（首次出现在 {seen[key]}）",
                }
            )
            continue
        seen[key] = f"assets.{category}[{index}].key"

    known = set(asset_keys.ASSET_KEYS)
    missing = [key for key in asset_keys.ASSET_KEYS if key not in seen]
    if missing:
        issues.append(
            {
                "level": "error",
                "path": "assets",
                "message": (
                    f"资产清单不完整：缺少 {len(missing)} 个键（{', '.join(missing)}）"
                ),
            }
        )
    unknown = [key for key in seen if key not in known]
    if unknown:
        issues.append(
            {
                "level": "error",
                "path": "assets",
                "message": f"资产清单多出表外键（{', '.join(sorted(unknown))}）",
            }
        )
    return issues


def _check_entries(spec: Any) -> list[dict]:
    """规则 3/4/5：height_m、lods、tags、collision。"""
    issues: list[dict] = []
    for category, index, entry in _entries(spec):
        base = f"assets.{category}[{index}]"
        key = entry.get("key")

        height = entry.get("height_m")
        if isinstance(height, list) and len(height) == 2 and all(_is_number(v) for v in height):
            low, high = height
            if low <= 0:
                issues.append(
                    {
                        "level": "error",
                        "path": f"{base}.height_m[0]",
                        "message": f"高度下界必须 > 0，实际 {low}",
                    }
                )
            if high <= 0:
                issues.append(
                    {
                        "level": "error",
                        "path": f"{base}.height_m[1]",
                        "message": f"高度上界必须 > 0，实际 {high}",
                    }
                )
            if low >= high:
                issues.append(
                    {
                        "level": "error",
                        "path": f"{base}.height_m",
                        "message": f"高度必须满足 min < max，实际 [{low}, {high}]",
                    }
                )

        lods = entry.get("lods")
        if isinstance(lods, list) and lods:
            if not all(_is_int(lod) for lod in lods):
                issues.append(
                    {
                        "level": "error",
                        "path": f"{base}.lods",
                        "message": "LOD 编号必须是整数",
                    }
                )
            else:
                if lods != sorted(lods):
                    issues.append(
                        {
                            "level": "error",
                            "path": f"{base}.lods",
                            "message": f"LOD 必须升序，实际 {lods}",
                        }
                    )
                if lods[0] != 0:
                    issues.append(
                        {
                            "level": "error",
                            "path": f"{base}.lods",
                            "message": f"LOD 必须从 0 开始，实际从 {lods[0]} 开始",
                        }
                    )
                expected = list(range(lods[-1] + 1))
                if lods != expected:
                    issues.append(
                        {
                            "level": "error",
                            "path": f"{base}.lods",
                            "message": f"LOD 必须连续，实际 {lods}（应为 {expected}）",
                        }
                    )

        tags = entry.get("tags")
        if isinstance(tags, list):
            for tag_index, tag in enumerate(tags):
                if not isinstance(tag, str):
                    continue
                if tag not in asset_keys.KNOWN_TAGS:
                    issues.append(
                        {
                            "level": "error",
                            "path": f"{base}.tags[{tag_index}]",
                            "message": (
                                f"未知标签 '{tag}'，已知标签为 "
                                f"{', '.join(sorted(asset_keys.KNOWN_TAGS))}"
                            ),
                        }
                    )

        collision = entry.get("collision")
        if isinstance(collision, str) and collision not in asset_keys.KNOWN_COLLISIONS:
            issues.append(
                {
                    "level": "error",
                    "path": f"{base}.collision",
                    "message": (
                        f"非法碰撞代理类型 '{collision}'，只允许 "
                        f"{', '.join(asset_keys.KNOWN_COLLISIONS)}"
                    ),
                }
            )
    return issues


def _check_region(spec: Any) -> list[dict]:
    """规则 6：region.size_m 两项均 > 0。"""
    issues: list[dict] = []
    if not isinstance(spec, dict):
        return issues
    region = spec.get("region")
    if not isinstance(region, dict):
        return issues
    size = region.get("size_m")
    if isinstance(size, list):
        for index, value in enumerate(size):
            if _is_number(value) and value <= 0:
                issues.append(
                    {
                        "level": "error",
                        "path": f"region.size_m[{index}]",
                        "message": f"区域边长必须 > 0，实际 {value}",
                    }
                )
    return issues


def _check_budget(spec: Any) -> list[dict]:
    """规则 7：budget 各字段范围合法。"""
    issues: list[dict] = []
    if not isinstance(spec, dict):
        return issues
    budget = spec.get("budget")
    if not isinstance(budget, dict):
        return issues
    positive_keys = (
        "max_tris_lod0_per_asset",
        "max_tris_lod1_per_asset",
        "max_materials",
        "max_total_bytes",
    )
    for name in positive_keys:
        value = budget.get(name)
        if _is_int(value) and value <= 0:
            issues.append(
                {
                    "level": "error",
                    "path": f"budget.{name}",
                    "message": f"预算必须 > 0，实际 {value}",
                }
            )
    textures = budget.get("max_textures")
    if _is_int(textures) and textures < 0:
        issues.append(
            {
                "level": "error",
                "path": "budget.max_textures",
                "message": f"纹理预算必须 >= 0，实际 {textures}",
            }
        )
    return issues


def _check_world(spec: Any) -> list[dict]:
    """world 段在 v1 不参与生成（§3.4），这里只确认它存在且是对象。"""
    issues: list[dict] = []
    if not isinstance(spec, dict):
        return issues
    world = spec.get("world")
    if world is None:
        issues.append(
            {
                "level": "error",
                "path": "world",
                "message": "缺少 world 段（v1 不参与生成，但必须存在且结构合法）",
            }
        )
    elif not isinstance(world, dict):
        issues.append(
            {
                "level": "error",
                "path": "world",
                "message": "world 段必须是对象",
            }
        )
    return issues
