"""种子派生（FNV-1a 32 位），对应 docs/forest-pipeline-spec.md §5.2。

算法（与 GDScript 侧一一对应）::

    seed = base_seed AND 0xFFFFFFFF
    for each byte b in utf8(key):
        seed = (seed XOR b) * 16777619 AND 0xFFFFFFFF
    seed = (seed MOD 2147483647) + 1

Python 侧每一步都用 ``& 0xFFFFFFFF`` 截断，因此与 GDScript 的 64 位有符号乘法结果一致。
黄金向量见 ``game/tests/fixtures/seed_golden.json``，由独立的第三方实现算出，Python 与
GDScript 两侧共用——``main.py --check-golden`` 用它做自检。
"""

from __future__ import annotations

import json
from typing import Iterable

from . import asset_keys

#: FNV-1a 32 位质数
FNV_PRIME = 16777619
#: 32 位掩码
MASK32 = 0xFFFFFFFF
#: 最终取模的模数（2**31 - 1）
MODULUS = 2147483647

#: 黄金文件记录的算法名
ALGORITHM_NAME = "fnv1a32"
#: 黄金文件记录的公式文本
FORMULA_TEXT = "seed=(seed^b)*16777619 & 0xFFFFFFFF; return (seed%2147483647)+1"

#: 黄金向量使用的基准种子
BASE_SEEDS: tuple[int, ...] = (41721, 20261117, 0, 1, 2147483647, 4294967295)

#: 黄金向量使用的边界用例：(基准种子, 键, 备注)
EDGE_CASES: tuple[tuple[int, str, str], ...] = (
    (41721, "", "empty key"),
    (41721, "岩", "non-ascii"),
    (41721, "pine_0", "normal"),
    (41721, "a" * 200, "long key"),
    (41721, "pine/0", "slash"),
    (41721, "pine_0\n", "trailing newline"),
)


def derive_seed(base_seed: int, key: str) -> int:
    """按 §5.2 从基准种子派生某个资产键的形态种子。

    ``key`` 严格按 UTF-8 字节参与运算：空串与非 ASCII 是重点边界。
    """
    seed = base_seed & MASK32
    for byte in key.encode("utf-8"):
        seed = ((seed ^ byte) * FNV_PRIME) & MASK32
    return (seed % MODULUS) + 1


def derive_seeds(base_seed: int, keys: Iterable[str]) -> dict[str, int]:
    """批量派生种子，保持传入顺序。"""
    return {key: derive_seed(base_seed, key) for key in keys}


def build_golden_document() -> dict:
    """重建黄金向量文档，结构与 ``game/tests/fixtures/seed_golden.json`` 完全一致。"""
    vectors = [
        {"base_seed": base, "key": key, "seed": derive_seed(base, key)}
        for base in BASE_SEEDS
        for key in asset_keys.ASSET_KEYS
    ]
    edge_cases = [
        {"base_seed": base, "key": key, "note": note, "seed": derive_seed(base, key)}
        for base, key, note in EDGE_CASES
    ]
    return {
        "algorithm": ALGORITHM_NAME,
        "formula": FORMULA_TEXT,
        "asset_keys": list(asset_keys.ASSET_KEYS),
        "vegetation_keys": list(asset_keys.VEGETATION_KEYS),
        "prop_keys": list(asset_keys.PROP_KEYS),
        "base_seeds": list(BASE_SEEDS),
        "vectors": vectors,
        "edge_cases": edge_cases,
    }


def golden_json_text(document: dict | None = None) -> str:
    """黄金向量的文本形式（LF 行尾，末尾一个换行）。"""
    doc = build_golden_document() if document is None else document
    return json.dumps(doc, ensure_ascii=False, indent=2) + "\n"


def golden_bytes(document: dict | None = None) -> bytes:
    """黄金向量文件的字节形式。

    仓库里的 fixture 是 CRLF 行尾（Windows checkout，``core.autocrlf=true``），
    这里显式按 CRLF 编码，保证 ``--emit-golden`` 产出的文件与既有 fixture 逐字节一致。
    """
    return golden_json_text(document).replace("\n", "\r\n").encode("utf-8")
