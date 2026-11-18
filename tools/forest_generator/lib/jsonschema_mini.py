"""JSON Schema 子集校验器（零第三方依赖），对应 docs/forest-pipeline-spec.md §3.2 / §3.3。

只实现本项目用到的关键字子集：

``type``、``const``、``enum``、``required``、``properties``、``additionalProperties``、
``items``、``prefixItems``、``minItems``、``maxItems``、``uniqueItems``、``minimum``、
``maximum``、``exclusiveMinimum``、``exclusiveMaximum``、``minLength``、``maxLength``、
``pattern``、``$ref``（仅 ``#/$defs/<name>``）、``$defs``、``allOf``、``anyOf``、
``oneOf``、``not``；``description`` 与 ``title`` 视为注释忽略。

``$ref`` 的解析基准是**根 schema**，因此内部引用必须写成 ``#/$defs/<name>`` 形式。

用法::

    errors = validate(instance, schema)   # 空列表表示通过
"""

from __future__ import annotations

import re
from typing import Any

#: 本实现支持的关键字（``description`` / ``title`` 视为注释）
SUPPORTED_KEYWORDS: frozenset[str] = frozenset(
    {
        "type",
        "const",
        "enum",
        "required",
        "properties",
        "additionalProperties",
        "items",
        "prefixItems",
        "minItems",
        "maxItems",
        "uniqueItems",
        "minimum",
        "maximum",
        "exclusiveMinimum",
        "exclusiveMaximum",
        "minLength",
        "maxLength",
        "pattern",
        "$ref",
        "$defs",
        "allOf",
        "anyOf",
        "oneOf",
        "not",
        "description",
        "title",
    }
)

_REF_PREFIX = "#/$defs/"


def validate(instance: Any, schema: dict, *, path: str = "", root: dict | None = None) -> list[dict]:
    """按 JSON Schema 子集校验实例。

    返回 ``{"path": ..., "message": ...}`` 列表，空列表表示通过。
    路径是 JSON Pointer 风格，例如 ``/assets/vegetation/0/height_m/1``。
    """
    root_doc = schema if root is None else root
    errors: list[dict] = []
    _validate(instance, schema, path, root_doc, errors)
    return errors


# ------------------------------------------------------------------ 工具函数


def _issue(path: str, message: str) -> dict:
    return {"path": path, "message": message}


def _child(path: str, token: str) -> str:
    """拼接 JSON Pointer 子路径（~ 与 / 需要转义）。"""
    escaped = token.replace("~", "~0").replace("/", "~1")
    return f"{path}/{escaped}"


def _type_name(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def _matches_type(value: Any, expected: str) -> bool:
    """判断值是否满足某个 type 名称（布尔值不算数字）。"""
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    if expected == "integer":
        if isinstance(value, bool):
            return False
        if isinstance(value, int):
            return True
        return isinstance(value, float) and value.is_integer()
    if expected == "number":
        if isinstance(value, bool):
            return False
        return isinstance(value, (int, float))
    # 未知的类型名不判错，交由其他关键字处理
    return True


def _json_equal(left: Any, right: Any) -> bool:
    """JSON 值相等比较：布尔与数字不混淆，容器递归比较。"""
    if isinstance(left, bool) or isinstance(right, bool):
        return isinstance(left, bool) and isinstance(right, bool) and left is right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    if isinstance(left, str) and isinstance(right, str):
        return left == right
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(
            _json_equal(a, b) for a, b in zip(left, right)
        )
    if isinstance(left, dict) and isinstance(right, dict):
        if set(left.keys()) != set(right.keys()):
            return False
        return all(_json_equal(left[key], right[key]) for key in left)
    return False


def _resolve_ref(ref: Any, root: dict) -> dict:
    """解析 ``#/$defs/<name>`` 形式的内部引用。"""
    if not isinstance(ref, str) or not ref.startswith(_REF_PREFIX):
        raise ValueError(f"仅支持 {_REF_PREFIX}<name> 形式的内部引用，收到 {ref!r}")
    name = ref[len(_REF_PREFIX) :]
    defs = root.get("$defs")
    if not isinstance(defs, dict) or name not in defs:
        raise ValueError(f"schema 中不存在 $defs/{name}")
    return defs[name]


# ------------------------------------------------------------------ 校验主体


def _validate(instance: Any, schema: Any, path: str, root: dict, errors: list[dict]) -> None:
    if schema is True or schema is None:
        return
    if schema is False:
        errors.append(_issue(path, "该位置不允许出现任何值"))
        return
    if not isinstance(schema, dict):
        return

    if "$ref" in schema:
        _validate(instance, _resolve_ref(schema["$ref"], root), path, root, errors)

    if "type" in schema:
        expected = schema["type"]
        candidates = expected if isinstance(expected, list) else [expected]
        if not any(_matches_type(instance, item) for item in candidates):
            errors.append(
                _issue(
                    path,
                    f"类型不匹配：期望 {'/'.join(str(c) for c in candidates)}，实际 {_type_name(instance)}",
                )
            )
            return

    if "const" in schema and not _json_equal(instance, schema["const"]):
        errors.append(_issue(path, f"取值必须恒等于 {schema['const']!r}，实际 {instance!r}"))

    if "enum" in schema:
        allowed = schema["enum"]
        if not any(_json_equal(instance, item) for item in allowed):
            errors.append(
                _issue(path, f"取值必须落在枚举 {allowed!r} 内，实际 {instance!r}")
            )

    if isinstance(instance, dict):
        _validate_object(instance, schema, path, root, errors)
    elif isinstance(instance, list):
        _validate_array(instance, schema, path, root, errors)
    elif isinstance(instance, str):
        _validate_string(instance, schema, path, errors)
    elif isinstance(instance, (int, float)) and not isinstance(instance, bool):
        _validate_number(instance, schema, path, errors)

    _validate_combinators(instance, schema, path, root, errors)


def _validate_object(instance: dict, schema: dict, path: str, root: dict, errors: list[dict]) -> None:
    required = schema.get("required")
    if isinstance(required, list):
        for name in required:
            if isinstance(name, str) and name not in instance:
                errors.append(_issue(_child(path, name), f"缺少必需字段 '{name}'"))

    properties = schema.get("properties")
    properties = properties if isinstance(properties, dict) else {}
    additional = schema.get("additionalProperties")

    for name, value in instance.items():
        if name in properties:
            _validate(value, properties[name], _child(path, name), root, errors)
            continue
        if additional is None:
            continue
        if additional is False:
            errors.append(_issue(_child(path, name), f"不允许的附加字段 '{name}'"))
        elif isinstance(additional, dict):
            _validate(value, additional, _child(path, name), root, errors)


def _validate_array(instance: list, schema: dict, path: str, root: dict, errors: list[dict]) -> None:
    prefix_items = schema.get("prefixItems")
    prefix_items = prefix_items if isinstance(prefix_items, list) else None
    items = schema.get("items")

    for index, value in enumerate(instance):
        sub_schema: Any = None
        if prefix_items is not None and index < len(prefix_items):
            sub_schema = prefix_items[index]
        elif items is not None:
            sub_schema = items
        if sub_schema is None:
            continue
        if sub_schema is False:
            errors.append(_issue(_child(path, str(index)), "该位置不允许出现元素"))
            continue
        _validate(value, sub_schema, _child(path, str(index)), root, errors)

    min_items = schema.get("minItems")
    if isinstance(min_items, int) and len(instance) < min_items:
        errors.append(_issue(path, f"数组至少要 {min_items} 项，实际 {len(instance)} 项"))

    max_items = schema.get("maxItems")
    if isinstance(max_items, int) and len(instance) > max_items:
        errors.append(_issue(path, f"数组最多 {max_items} 项，实际 {len(instance)} 项"))

    if schema.get("uniqueItems") is True:
        for index in range(len(instance)):
            for other in range(index + 1, len(instance)):
                if _json_equal(instance[index], instance[other]):
                    errors.append(
                        _issue(
                            _child(path, str(other)),
                            f"元素与下标 {index} 重复（uniqueItems）",
                        )
                    )
                    break


def _validate_string(instance: str, schema: dict, path: str, errors: list[dict]) -> None:
    min_length = schema.get("minLength")
    if isinstance(min_length, int) and len(instance) < min_length:
        errors.append(_issue(path, f"字符串长度至少 {min_length}，实际 {len(instance)}"))

    max_length = schema.get("maxLength")
    if isinstance(max_length, int) and len(instance) > max_length:
        errors.append(_issue(path, f"字符串长度最多 {max_length}，实际 {len(instance)}"))

    pattern = schema.get("pattern")
    if isinstance(pattern, str) and re.search(pattern, instance) is None:
        errors.append(_issue(path, f"不匹配正则 {pattern!r}：{instance!r}"))


def _validate_number(instance: float, schema: dict, path: str, errors: list[dict]) -> None:
    minimum = schema.get("minimum")
    if isinstance(minimum, (int, float)) and not isinstance(minimum, bool):
        if instance < minimum:
            errors.append(_issue(path, f"必须 >= {minimum}，实际 {instance}"))

    maximum = schema.get("maximum")
    if isinstance(maximum, (int, float)) and not isinstance(maximum, bool):
        if instance > maximum:
            errors.append(_issue(path, f"必须 <= {maximum}，实际 {instance}"))

    exclusive_min = schema.get("exclusiveMinimum")
    if isinstance(exclusive_min, (int, float)) and not isinstance(exclusive_min, bool):
        if instance <= exclusive_min:
            errors.append(_issue(path, f"必须 > {exclusive_min}，实际 {instance}"))

    exclusive_max = schema.get("exclusiveMaximum")
    if isinstance(exclusive_max, (int, float)) and not isinstance(exclusive_max, bool):
        if instance >= exclusive_max:
            errors.append(_issue(path, f"必须 < {exclusive_max}，实际 {instance}"))


def _validate_combinators(instance: Any, schema: dict, path: str, root: dict, errors: list[dict]) -> None:
    all_of = schema.get("allOf")
    if isinstance(all_of, list):
        for sub_schema in all_of:
            _validate(instance, sub_schema, path, root, errors)

    any_of = schema.get("anyOf")
    if isinstance(any_of, list):
        matched = False
        for sub_schema in any_of:
            branch_errors: list[dict] = []
            _validate(instance, sub_schema, path, root, branch_errors)
            if not branch_errors:
                matched = True
                break
        if not matched:
            errors.append(_issue(path, "不满足 anyOf 中的任何一个分支"))

    one_of = schema.get("oneOf")
    if isinstance(one_of, list):
        matched = 0
        for sub_schema in one_of:
            branch_errors = []
            _validate(instance, sub_schema, path, root, branch_errors)
            if not branch_errors:
                matched += 1
        if matched != 1:
            errors.append(
                _issue(path, f"oneOf 要求恰好命中 1 个分支，实际命中 {matched} 个")
            )

    not_schema = schema.get("not")
    if not_schema is not None:
        branch_errors = []
        _validate(instance, not_schema, path, root, branch_errors)
        if not branch_errors:
            errors.append(_issue(path, "命中了 not 禁止的形态"))
