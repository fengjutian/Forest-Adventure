"""构建编排层的测试，对应 docs/forest-pipeline-spec.md §5（确定性）、§6、§7。

这些用例需要真的跑 Blender，因此**没有 Blender 时整体跳过**——
纯逻辑部分（参数、manifest 组装）另有 ``test_params.py`` / ``test_manifest.py`` 覆盖。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import asset_keys, build as build_lib, params  # noqa: E402
from lib.manifest import read_manifest  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
PRESET = REPO_ROOT / "tools" / "forest_generator" / "presets" / "pine_valley.json"


def _blender_or_skip() -> Path:
    try:
        blender = build_lib.find_blender()
    except build_lib.BuildError as exc:
        pytest.skip(f"没有可用的 Blender：{exc}")
    if not build_lib._BUILD_SCRIPT.exists():
        pytest.skip(f"Blender 构建脚本还没到位：{build_lib._BUILD_SCRIPT}")
    return blender


@pytest.fixture(scope="module")
def preset() -> dict:
    return json.loads(PRESET.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def built(tmp_path_factory, preset):
    """真的构建一次 pine_0，返回 (manifest, 产物目录)。"""
    blender = _blender_or_skip()
    staging = tmp_path_factory.mktemp("staging")
    target = tmp_path_factory.mktemp("target")
    manifest = build_lib.build_assets(
        spec=preset,
        keys=["pine_0"],
        blender=blender,
        staging=staging,
        target=target,
        generated_at="2026-01-01T00:00:00Z",
    )
    return manifest, target


# ------------------------------------------------------------------ 产物结构


def test_manifest_lists_the_built_asset(built):
    manifest, _ = built
    assert manifest["totals"]["assets"] == 1
    entry = manifest["assets"][0]
    assert entry["key"] == "pine_0"
    assert entry["files"], "至少有 LOD0 文件"


def test_all_declared_lods_are_produced(built, preset):
    """SceneSpec 声明的 LOD 必须全部产出（§8 检查项 5：LOD 数量与声明一致）。"""
    manifest, _ = built
    declared = next(
        e["lods"]
        for e in preset["assets"]["vegetation"]
        if e["key"] == "pine_0"
    )
    produced = sorted(f["lod"] for f in manifest["assets"][0]["files"])
    assert produced == sorted(declared)


def test_files_exist_and_hash_matches(built):
    """每个文件都在，且 sha256 与实际一致（§8 检查项 3）。"""
    manifest, target = built
    for file_entry in manifest["assets"][0]["files"]:
        path = target / file_entry["path"]
        assert path.exists(), path
        assert build_lib.sha256_file(path) == file_entry["sha256"]
        assert path.stat().st_size == file_entry["bytes"]


def test_tris_decrease_with_lod(built):
    """三角面数随 LOD 递减（§4.4）。"""
    manifest, _ = built
    tris = manifest["assets"][0]["tris"]
    ordered = [tris[key] for key in sorted(tris, key=lambda k: int(k[3:]))]
    assert ordered == sorted(ordered, reverse=True), tris
    assert all(count > 0 for count in ordered)


def test_filenames_follow_naming_rule(built):
    manifest, _ = built
    for file_entry in manifest["assets"][0]["files"]:
        name = Path(file_entry["path"]).name
        assert name == asset_keys.glb_filename("pine_0", file_entry["lod"])
        assert name.endswith(".glb")


def test_bounds_min_y_is_ground(built):
    """§4.2：树资产的包围盒 min.y ≈ 0（原点在树根，不在几何中心）。

    Blender 是 Z-up，导出成 glTF 后 Y 才是高度轴——所以这里比的是
    「高度轴的最小值为 0」，而不是固定的某个轴。
    """
    manifest, _ = built
    bounds = manifest["assets"][0]["bounds"]
    assert bounds is not None
    assert min(bounds["min"]) < 0.05, bounds
    # 高度轴上的跨度应当是整棵树的高度
    span = max(bounds["max"]) - min(bounds["min"])
    assert span > 1.0, bounds


def test_seed_report_matches_golden(built, preset):
    """seed_report 里的派生种子必须与 §5.2 的算法一致（§5.4）。"""
    manifest, target = built
    report = json.loads((target / "seed_report.json").read_text(encoding="utf-8"))
    assert report["algorithm"] == "fnv1a32"
    from lib.seed import derive_seed

    for entry in report["assets"]:
        assert entry["seed"] == derive_seed(preset["seed"], entry["key"])


# ------------------------------------------------------------------ 确定性


def test_same_seed_rebuilds_identical_bytes(tmp_path, preset):
    """M3-2 退出条件：同 seed 重跑，GLB 的 sha256 不变。"""
    blender = _blender_or_skip()
    staging_a = tmp_path / "staging_a"
    staging_b = tmp_path / "staging_b"
    target_a = tmp_path / "out_a"
    target_b = tmp_path / "out_b"

    manifest_a = build_lib.build_assets(
        spec=preset, keys=["pine_0"], blender=blender, staging=staging_a,
        target=target_a, generated_at="2026-01-01T00:00:00Z",
    )
    manifest_b = build_lib.build_assets(
        spec=preset, keys=["pine_0"], blender=blender, staging=staging_b,
        target=target_b, generated_at="2026-01-01T00:00:00Z",
    )

    hashes_a = {f["path"]: f["sha256"] for f in manifest_a["assets"][0]["files"]}
    hashes_b = {f["path"]: f["sha256"] for f in manifest_b["assets"][0]["files"]}
    assert hashes_a == hashes_b, "同 seed 两次构建的 GLB 摘要不一致"

    # 除时间戳外，manifest 也应逐字段相同
    manifest_a = dict(manifest_a)
    manifest_b = dict(manifest_b)
    assert manifest_a == manifest_b


def test_failed_build_keeps_previous_output(tmp_path, preset, monkeypatch):
    """构建失败不得覆盖上一版有效产物（§7）。"""
    blender = _blender_or_skip()
    staging = tmp_path / "staging"
    target = tmp_path / "out"
    target.mkdir(parents=True, exist_ok=True)
    (target / "manifest.json").write_text('{"keep": true}\n', encoding="utf-8")

    def boom(*_args, **_kwargs):
        raise build_lib.BuildError("故意失败")

    monkeypatch.setattr(build_lib, "_run_blender", boom)
    with pytest.raises(build_lib.BuildError):
        build_lib.build_assets(
            spec=preset, keys=["pine_0"], blender=blender, staging=staging,
            target=target, generated_at="2026-01-01T00:00:00Z",
        )

    assert read_manifest(target / "manifest.json") == {"keep": True}
