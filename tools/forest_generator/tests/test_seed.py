"""种子派生一致性单测，对应 docs/forest-pipeline-spec.md §5.2。

黄金向量在 ``game/tests/fixtures/seed_golden.json``，由第三份独立实现算出。
Python 侧与 GDScript 侧各自复现它（不是互相比对，见 §5.2 的说明）。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import asset_keys, seed  # noqa: E402

#: 仓库根目录（tests → forest_generator → tools → 仓库根）
REPO_ROOT = Path(__file__).resolve().parents[3]
GOLDEN_PATH = REPO_ROOT / "game" / "tests" / "fixtures" / "seed_golden.json"
SEED_UTIL_PATH = REPO_ROOT / "game" / "scripts" / "core" / "seed_util.gd"

GOLDEN = json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))

_VECTOR_IDS = [f"vector-{index}" for index in range(len(GOLDEN["vectors"]))]
_EDGE_IDS = [f"edge-{index}" for index in range(len(GOLDEN["edge_cases"]))]


def test_golden_shape() -> None:
    """黄金文件的结构：174 条向量 + 6 条边界用例。"""
    assert GOLDEN["algorithm"] == "fnv1a32"
    assert len(GOLDEN["vectors"]) == 174
    assert len(GOLDEN["edge_cases"]) == 6
    assert len(GOLDEN["asset_keys"]) == 29
    assert GOLDEN["base_seeds"] == list(seed.BASE_SEEDS)


@pytest.mark.parametrize("vector", GOLDEN["vectors"], ids=_VECTOR_IDS)
def test_golden_vectors(vector: dict) -> None:
    """逐条复现黄金向量。"""
    assert seed.derive_seed(vector["base_seed"], vector["key"]) == vector["seed"]


@pytest.mark.parametrize("case", GOLDEN["edge_cases"], ids=_EDGE_IDS)
def test_golden_edge_cases(case: dict) -> None:
    """逐条复现边界用例（空串、非 ASCII、超长键、结尾换行）。"""
    assert seed.derive_seed(case["base_seed"], case["key"]) == case["seed"]


def test_key_is_derived_from_utf8_bytes() -> None:
    """键必须严格按 UTF-8 字节参与运算，而不是按字符码位。"""
    key = "岩"
    utf8_seed = seed.derive_seed(41721, key)
    # 按码位（而不是 UTF-8 字节）参与运算会得到不同的结果
    by_codepoint = 41721 & seed.MASK32
    for value in (ord(char) for char in key):
        by_codepoint = ((by_codepoint ^ value) * seed.FNV_PRIME) & seed.MASK32
    assert by_codepoint % seed.MODULUS + 1 != utf8_seed
    # 逐字节展开 UTF-8 编码后应与直接调用一致
    manual = 41721 & seed.MASK32
    for byte in key.encode("utf-8"):
        manual = ((manual ^ byte) * seed.FNV_PRIME) & seed.MASK32
    assert manual % seed.MODULUS + 1 == utf8_seed


def test_empty_key_is_base_seed_plus_one() -> None:
    """空串不参与运算，结果是 base_seed + 1（base_seed 已在范围内时）。"""
    assert seed.derive_seed(41721, "") == 41722


def test_result_range() -> None:
    """结果恒落在 [1, 2147483647]。"""
    for base in (0, 1, 41721, 2147483647, 4294967295):
        for key in ("", "pine_0", "岩", "a" * 200):
            value = seed.derive_seed(base, key)
            assert 1 <= value <= seed.MODULUS


def test_base_seed_is_masked_to_32_bits() -> None:
    """base_seed 先按 32 位无符号截断。"""
    assert seed.derive_seed(2**32 + 41721, "pine_0") == seed.derive_seed(41721, "pine_0")
    assert seed.derive_seed(-1, "pine_0") == seed.derive_seed(0xFFFFFFFF, "pine_0")


def test_derive_seeds_covers_all_keys() -> None:
    """批量派生覆盖全部 29 个键。"""
    seeds = seed.derive_seeds(41721, asset_keys.ASSET_KEYS)
    assert list(seeds) == asset_keys.ASSET_KEYS
    assert seeds["pine_0"] == 1615208297


def test_rebuilt_golden_document_matches_fixture() -> None:
    """Python 侧重建的黄金文档与仓库里的 fixture 完全一致。"""
    assert seed.build_golden_document() == GOLDEN
    assert seed.golden_bytes() == GOLDEN_PATH.read_bytes()


def test_gdscript_side_uses_the_same_constants() -> None:
    """GDScript 参考实现与 Python 侧的常量一致（只读核对，不修改该文件）。"""
    source = SEED_UTIL_PATH.read_text(encoding="utf-8")
    assert re.search(r"FNV_OFFSET\s*:=\s*16777619", source)
    assert re.search(r"MASK\s*:=\s*0xFFFFFFFF", source)
    assert re.search(r"MOD\s*:=\s*2147483647", source)
    assert "to_utf8_buffer()" in source
