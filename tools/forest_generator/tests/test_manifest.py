"""manifest 读写与统计的单测，对应 docs/forest-pipeline-spec.md §7。"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import manifest  # noqa: E402

SPEC = {
    "schema_version": "1.1",
    "seed": 41721,
    "region": {"id": "pine_valley"},
    "export": {"material_mode": "vertex_color"},
}

ASSETS = [
    {
        "key": "pine_0",
        "variant": "pine",
        "files": [
            {
                "lod": 0,
                "path": "meshes/env_tree_pine_a_lod0.glb",
                "sha256": "a" * 64,
                "bytes": 51234,
            },
            {
                "lod": 1,
                "path": "meshes/env_tree_pine_a_lod1.glb",
                "sha256": "b" * 64,
                "bytes": 12000,
            },
        ],
        "tris": {"lod0": 412, "lod1": 96, "lod2": 24},
        "bounds": {"min": [-1.2, 0.0, -1.2], "max": [1.2, 9.8, 1.2]},
        "collision": {"type": "capsule", "radius": 0.28, "height": 9.8},
        "tags": ["sway"],
        "materials": 2,
        "textures": 0,
    },
    {
        "key": "rock",
        "variant": "rock",
        "files": [
            {
                "lod": 0,
                "path": "meshes/env_rock_a_lod0.glb",
                "sha256": "c" * 64,
                "bytes": 8000,
            }
        ],
        "tris": {"lod0": 56, "lod1": 18},
        "bounds": {"min": [-0.6, 0.0, -0.6], "max": [0.6, 1.2, 0.6]},
        "collision": {"type": "box"},
        "tags": [],
        "materials": 1,
        "textures": 0,
    },
]


def _build() -> dict:
    return manifest.build_manifest(
        SPEC,
        ASSETS,
        {"python": "3.12.7", "blender": "5.3.0"},
        "0.1.0",
        "2026-11-17T12:00:00Z",
    )


def test_manifest_structure() -> None:
    """manifest 的顶层字段与 §7 一致。"""
    doc = _build()
    assert doc["manifest_version"] == "1.0"
    assert doc["schema_version"] == "1.1"
    assert doc["generator_version"] == "0.1.0"
    assert doc["seed"] == 41721
    assert doc["region_id"] == "pine_valley"
    assert doc["material_mode"] == "vertex_color"
    assert doc["generated_at"] == "2026-11-17T12:00:00Z"
    assert doc["environment"] == {"python": "3.12.7", "blender": "5.3.0"}
    assert doc["assets"] == ASSETS
    assert doc["warnings"] == []


def test_totals_are_computed_from_actual_data() -> None:
    """totals 必须由实际数据统计得出。"""
    totals = _build()["totals"]
    assert totals["assets"] == 2
    assert totals["files"] == 3
    assert totals["bytes"] == 51234 + 12000 + 8000
    assert totals["tris_lod0"] == 412 + 56
    assert totals["materials"] == 2 + 1
    assert totals["textures"] == 0


def test_generated_at_is_not_computed_inside_the_library() -> None:
    """确定性要求：generated_at 由调用方传入（§5.3），库里不读时钟。"""
    doc = _build()
    assert doc["generated_at"] == "2026-11-17T12:00:00Z"
    source = Path(manifest.__file__).read_text(encoding="utf-8")
    assert "import datetime" not in source
    assert "from datetime" not in source
    assert "time.time" not in source


def test_write_and_read_roundtrip(tmp_path: Path) -> None:
    """写入后再读回来内容一致。"""
    path = tmp_path / "manifest.json"
    doc = _build()
    manifest.write_manifest(path, doc)
    assert manifest.read_manifest(path) == doc


def test_write_leaves_no_tmp_file(tmp_path: Path) -> None:
    """原子写入不留 .tmp 残留。"""
    path = tmp_path / "manifest.json"
    manifest.write_manifest(path, _build())
    assert path.exists()
    assert not (tmp_path / "manifest.json.tmp").exists()
    assert list(tmp_path.iterdir()) == [path]


def test_failed_write_keeps_previous_output(tmp_path: Path, monkeypatch) -> None:
    """写入失败不得破坏上一版有效输出，且不留下 .tmp。"""
    path = tmp_path / "manifest.json"
    good = _build()
    manifest.write_manifest(path, good)
    before = path.read_bytes()

    def boom(*args, **kwargs):
        raise OSError("模拟写入失败")

    monkeypatch.setattr(manifest.os, "replace", boom)
    broken = _build()
    broken["generator_version"] = "0.2.0"
    with pytest.raises(OSError):
        manifest.write_manifest(path, broken)

    assert path.read_bytes() == before
    assert manifest.read_manifest(path) == good
    assert not (tmp_path / "manifest.json.tmp").exists()


def test_unserializable_manifest_keeps_previous_output(tmp_path: Path) -> None:
    """内容不可序列化时也不能破坏上一版有效输出。"""
    path = tmp_path / "manifest.json"
    manifest.write_manifest(path, _build())
    before = path.read_bytes()

    broken = _build()
    broken["assets"] = [{"key": "broken", "files": {1, 2}}]
    with pytest.raises(TypeError):
        manifest.write_manifest(path, broken)

    assert path.read_bytes() == before
    assert not (tmp_path / "manifest.json.tmp").exists()


def test_sha256_file(tmp_path: Path) -> None:
    """sha256 与标准库一致。"""
    path = tmp_path / "mesh.glb"
    payload = b"forest-adventure" * 1000
    path.write_bytes(payload)
    assert manifest.sha256_file(path) == hashlib.sha256(payload).hexdigest()


def test_manifest_json_is_utf8(tmp_path: Path) -> None:
    """manifest 以 UTF-8 写出，中文不转义。"""
    path = tmp_path / "manifest.json"
    doc = _build()
    doc["warnings"] = ["松树需要更多三角面"]
    manifest.write_manifest(path, doc)
    raw = path.read_bytes()
    assert "松树需要更多三角面" in raw.decode("utf-8")
    assert b"\\u" not in raw
    assert json.loads(raw.decode("utf-8"))["warnings"] == ["松树需要更多三角面"]
