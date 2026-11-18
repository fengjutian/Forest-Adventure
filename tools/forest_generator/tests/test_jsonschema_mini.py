"""JSON Schema 子集校验器自身的单测，并与标准库 ``jsonschema`` 交叉验证。

交叉验证的规则：同一批用例喂给两个实现，**结论必须一致**（同一个输入，
一个报 error 另一个也必须报 error；error 条数可以不同）。
``jsonschema`` 不可用时该部分自动跳过，其余用例仍然必须通过。
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import jsonschema_mini  # noqa: E402

try:  # pragma: no cover - 取决于本机是否装了标准库
    import jsonschema
except ImportError:  # pragma: no cover
    jsonschema = None


#: (用例名, 实例, schema, 是否应当通过)
CASES: list[tuple[str, object, dict, bool]] = [
    ("object_ok", {"a": 1}, {"type": "object"}, True),
    ("type_mismatch", {"a": "x"}, {"type": "object", "properties": {"a": {"type": "integer"}}}, False),
    ("required_missing", {}, {"type": "object", "required": ["a"]}, False),
    ("required_present", {"a": 1}, {"type": "object", "required": ["a"]}, True),
    ("const_ok", {"v": "1.1"}, {"properties": {"v": {"const": "1.1"}}}, True),
    ("const_bad", {"v": "1.0"}, {"properties": {"v": {"const": "1.1"}}}, False),
    ("enum_ok", {"v": "glb"}, {"properties": {"v": {"enum": ["glb", "fbx"]}}}, True),
    ("enum_bad", {"v": "obj"}, {"properties": {"v": {"enum": ["glb", "fbx"]}}}, False),
    (
        "additional_properties_rejected",
        {"a": 1, "b": 2},
        {"properties": {"a": {}}, "additionalProperties": False},
        False,
    ),
    ("additional_properties_allowed", {"a": 1, "b": 2}, {"properties": {"a": {}}}, True),
    ("items_type_error", [1, "x"], {"type": "array", "items": {"type": "integer"}}, False),
    ("items_ok", [1, 2], {"type": "array", "items": {"type": "integer"}}, True),
    (
        "prefix_items_ok",
        [1, "x"],
        {"type": "array", "prefixItems": [{"type": "integer"}, {"type": "string"}]},
        True,
    ),
    (
        "prefix_items_error",
        [1, 2],
        {"type": "array", "prefixItems": [{"type": "integer"}, {"type": "string"}]},
        False,
    ),
    ("min_items_error", [1], {"type": "array", "minItems": 2}, False),
    ("max_items_error", [1, 2, 3], {"type": "array", "maxItems": 2}, False),
    ("unique_items_error", [1, 1], {"type": "array", "uniqueItems": True}, False),
    ("unique_items_ok", [1, 2], {"type": "array", "uniqueItems": True}, True),
    ("minimum_error", 5, {"type": "integer", "minimum": 10}, False),
    ("maximum_error", 50, {"type": "integer", "maximum": 10}, False),
    ("exclusive_minimum_error", 10, {"type": "integer", "exclusiveMinimum": 10}, False),
    ("exclusive_maximum_error", 10, {"type": "integer", "exclusiveMaximum": 10}, False),
    ("min_length_error", "ab", {"type": "string", "minLength": 3}, False),
    ("max_length_error", "abcd", {"type": "string", "maxLength": 3}, False),
    ("pattern_ok", "pine_valley", {"type": "string", "pattern": "^[a-z][a-z0-9_]*$"}, True),
    ("pattern_error", "Pine Valley", {"type": "string", "pattern": "^[a-z][a-z0-9_]*$"}, False),
    ("integer_accepts_integral_float", 1.0, {"type": "integer"}, True),
    ("boolean_is_not_number", True, {"type": "number"}, False),
    (
        "ref_ok",
        {"a": 1},
        {
            "type": "object",
            "properties": {"a": {"$ref": "#/$defs/pos_int"}},
            "$defs": {"pos_int": {"type": "integer", "minimum": 0}},
        },
        True,
    ),
    (
        "ref_error",
        {"a": -1},
        {
            "type": "object",
            "properties": {"a": {"$ref": "#/$defs/pos_int"}},
            "$defs": {"pos_int": {"type": "integer", "minimum": 0}},
        },
        False,
    ),
    ("all_of_ok", 5, {"allOf": [{"type": "integer"}, {"minimum": 1}]}, True),
    ("all_of_error", 0, {"allOf": [{"type": "integer"}, {"minimum": 1}]}, False),
    ("any_of_ok", "a", {"anyOf": [{"type": "string"}, {"type": "integer"}]}, True),
    ("any_of_error", [], {"anyOf": [{"type": "string"}, {"type": "integer"}]}, False),
    ("one_of_ok", 1, {"oneOf": [{"type": "integer"}, {"type": "string"}]}, True),
    (
        "one_of_error",
        5,
        {"oneOf": [{"type": "integer", "minimum": 0}, {"type": "integer", "maximum": 10}]},
        False,
    ),
    ("not_error", 1, {"not": {"type": "integer"}}, False),
    ("not_ok", "x", {"not": {"type": "integer"}}, True),
]

CASE_IDS = [case[0] for case in CASES]


# ------------------------------------------------------------------ 自身行为


@pytest.mark.parametrize("name,instance,schema,expect_valid", CASES, ids=CASE_IDS)
def test_validate_conclusion(name, instance, schema, expect_valid) -> None:
    """每条用例的结论必须符合预期。"""
    errors = jsonschema_mini.validate(instance, schema)
    assert (not errors) == expect_valid, f"{name}: {errors}"


def test_error_paths_are_json_pointers() -> None:
    """错误路径是 JSON Pointer 风格。"""
    schema = {
        "type": "object",
        "properties": {
            "assets": {
                "type": "object",
                "properties": {
                    "vegetation": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {"height_m": {"type": "array", "minItems": 3}},
                        },
                    }
                },
            }
        },
    }
    instance = {"assets": {"vegetation": [{"height_m": [1.0, 2.0]}]}}
    errors = jsonschema_mini.validate(instance, schema)
    assert errors
    assert errors[0]["path"] == "/assets/vegetation/0/height_m"


def test_missing_field_path_points_at_the_field() -> None:
    """缺字段时路径指向字段本身。"""
    errors = jsonschema_mini.validate({}, {"type": "object", "required": ["seed"]})
    assert errors
    assert errors[0]["path"] == "/seed"


def test_root_path_is_empty_string() -> None:
    """根级错误的路径是空字符串（JSON Pointer 的根）。"""
    errors = jsonschema_mini.validate("x", {"type": "object"})
    assert errors
    assert errors[0]["path"] == ""


def test_unsupported_ref_raises() -> None:
    """只支持 #/$defs/<name> 形式的内部引用。"""
    with pytest.raises(ValueError):
        jsonschema_mini.validate({}, {"$ref": "#/definitions/thing"})


def test_scene_spec_schema_is_supported() -> None:
    """本项目的 schema 只用了子集内的关键字。"""
    schema_path = Path(__file__).resolve().parents[1] / "schemas" / "scene_spec.schema.json"
    import json

    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    used: set[str] = set()

    def walk(node) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("properties", "$defs"):
                    # 这些键下面挂的是 schema，键名本身不是关键字
                    for sub in value.values():
                        walk(sub)
                    continue
                used.add(key)
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(schema)
    unknown = used - jsonschema_mini.SUPPORTED_KEYWORDS - {"$schema", "$id"}
    assert unknown == set(), f"schema 用到了子集外的关键字：{sorted(unknown)}"


# ------------------------------------------------------------------ 交叉验证


@pytest.mark.skipif(jsonschema is None, reason="未安装 jsonschema，跳过交叉验证")
@pytest.mark.parametrize("name,instance,schema,expect_valid", CASES, ids=CASE_IDS)
def test_cross_validate_with_jsonschema(name, instance, schema, expect_valid) -> None:
    """与标准库交叉验证：结论（有/无 error）必须一致。"""
    validator = jsonschema.Draft202012Validator(schema)
    standard_ok = validator.is_valid(instance)
    mini_ok = not jsonschema_mini.validate(instance, schema)
    assert standard_ok == mini_ok, f"{name}: 标准库={standard_ok}，子集实现={mini_ok}"
    assert mini_ok == expect_valid, name


@pytest.mark.skipif(jsonschema is None, reason="未安装 jsonschema，跳过交叉验证")
def test_cross_validate_scene_spec_schema() -> None:
    """拿真实的 SceneSpec schema 与 preset 做交叉验证。"""
    import json

    root = Path(__file__).resolve().parents[1]
    schema = json.loads((root / "schemas" / "scene_spec.schema.json").read_text(encoding="utf-8"))
    preset = json.loads((root / "presets" / "pine_valley.json").read_text(encoding="utf-8"))

    validator = jsonschema.Draft202012Validator(schema)
    assert validator.is_valid(preset)
    assert not jsonschema_mini.validate(preset, schema)

    broken = json.loads(json.dumps(preset))
    broken["region"]["id"] = "Pine Valley"
    assert not validator.is_valid(broken)
    assert jsonschema_mini.validate(broken, schema)
