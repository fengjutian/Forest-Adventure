"""资产构建编排：SceneSpec → 形态参数 → Blender → GLB → manifest。

对应 docs/forest-pipeline-spec.md §5（确定性）、§6（目录布局）、§7（manifest 格式）。

构建分两段，中间用暂存目录隔开：
1. 所有 GLB 先构建到暂存目录，任何一步失败都不碰上一版有效产物；
2. 全部成功后逐个原子替换进目标目录，**manifest 最后写**——
   这样中途被打断时，manifest 里的 sha256 仍然指向旧文件，
   导入检查器能查出不一致，而不是静默损坏。
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from . import asset_keys, params
from .manifest import build_manifest, sha256_file, write_manifest
from .seed import ALGORITHM_NAME, FORMULA_TEXT, derive_seed

#: 管线版本。产出内容变化时必须提升（content-pipeline.md §9）。
GENERATOR_VERSION = "0.2.0"

#: Blender 的候选位置。环境变量 BLENDER_EXE 优先。
_BLENDER_CANDIDATES = (
    r"D:\Program Files\Blender Foundation\Blender 5.3\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe",
    r"D:\Program Files\Blender Foundation\Blender 4.5\blender.exe",
)

#: Blender 脚本入口
_BUILD_SCRIPT = Path(__file__).resolve().parent.parent / "blender" / "build_asset.py"


class BuildError(RuntimeError):
    """构建失败。"""


def find_blender() -> Path:
    """定位 blender.exe。"""
    env = os.environ.get("BLENDER_EXE")
    if env:
        candidate = Path(env)
        if candidate.exists():
            return candidate
        raise BuildError(f"环境变量 BLENDER_EXE 指向的文件不存在：{candidate}")
    for raw in _BLENDER_CANDIDATES:
        candidate = Path(raw)
        if candidate.exists():
            return candidate
    raise BuildError(
        "找不到 blender.exe。请安装 Blender 5.3 或设置环境变量 BLENDER_EXE。\n"
        + "已尝试：" + ", ".join(_BLENDER_CANDIDATES)
    )


def blender_version(blender: Path) -> str:
    """取 Blender 版本串，形如 ``5.3.0``。"""
    proc = subprocess.run(
        [str(blender), "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    match = re.search(r"Blender\s+(\d+\.\d+(?:\.\d+)?)", proc.stdout or "")
    return match.group(1) if match else "unknown"


def _run_blender(blender: Path, spec_path: Path, glb_path: Path) -> dict:
    """跑一次 Blender 构建，返回它打印的 BUILD_JSON。"""
    proc = subprocess.run(
        [
            str(blender),
            "--background",
            "--factory-startup",
            "--python",
            str(_BUILD_SCRIPT),
            "--",
            str(spec_path),
            str(glb_path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    output = (proc.stdout or "") + (proc.stderr or "")
    for line in output.splitlines():
        if line.startswith("BUILD_JSON:"):
            return json.loads(line[len("BUILD_JSON:") :])
    tail = "\n".join(output.splitlines()[-15:])
    raise BuildError(
        f"Blender 没有输出 BUILD_JSON（退出码 {proc.returncode}）。\n"
        f"命令：{blender} --background --python {_BUILD_SCRIPT} -- {spec_path} {glb_path}\n"
        f"输出尾部：\n{tail}"
    )


def _atomic_copy(src: Path, dst: Path) -> None:
    """原子替换一个文件。"""
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    shutil.copyfile(src, tmp)
    os.replace(tmp, dst)


def build_assets(
    spec: dict,
    keys: list[str],
    blender: Path,
    staging: Path,
    target: Path,
    generated_at: str,
) -> dict:
    """构建指定资产，返回 manifest 字典。

    ``keys`` 为空表示构建所有**已有形态模板**的资产。
    """
    region = spec.get("region", {})
    region_id = region.get("id", "region")
    base_seed = int(spec.get("seed", 0))
    asset_entries = _collect_entries(spec)

    staging.mkdir(parents=True, exist_ok=True)
    meshes_dir = staging / "meshes"
    meshes_dir.mkdir(parents=True, exist_ok=True)

    manifest_assets = []
    seed_report_assets = []

    for key in keys:
        entry = asset_entries.get(key)
        if entry is None:
            raise BuildError(f"SceneSpec 里没有资产 '{key}'")
        info = asset_keys.KEY_INFO[key]
        lods = list(entry.get("lods") or [0])

        files = []
        tris = {}
        bounds = None
        lod0_params = None

        for lod in lods:
            build_spec = params.derive_params(base_seed, key, info, lod)
            if lod == 0:
                lod0_params = build_spec
            build_spec["filename"] = asset_keys.glb_filename(key, lod)

            spec_path = staging / f"{key}_lod{lod}.spec.json"
            spec_path.write_text(
                json.dumps(build_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )

            glb_path = meshes_dir / build_spec["filename"]
            report = _run_blender(blender, spec_path, glb_path)
            if not glb_path.exists():
                raise BuildError(f"Blender 没有产出 GLB：{glb_path}")

            files.append(
                {
                    "lod": lod,
                    "path": f"meshes/{build_spec['filename']}",
                    "sha256": sha256_file(glb_path),
                    "bytes": glb_path.stat().st_size,
                }
            )
            tris[f"lod{lod}"] = int(report.get("tris", 0))
            if lod == 0:
                bounds = {
                    "min": [round(float(v), 4) for v in report.get("bbox_min", [0, 0, 0])],
                    "max": [round(float(v), 4) for v in report.get("bbox_max", [0, 0, 0])],
                }

        manifest_assets.append(
            {
                "key": key,
                "variant": entry.get("variant"),
                "files": files,
                "tris": tris,
                "bounds": bounds,
                "collision": params.collision_from_params(
                    lod0_params or {}, entry.get("collision", "none")
                ),
                "tags": list(entry.get("tags") or []),
                "materials": 0,
                "textures": 0,
            }
        )
        seed_report_assets.append(
            {"key": key, "seed": derive_seed(base_seed, key), "lods": lods}
        )

    manifest = build_manifest(
        spec=spec,
        assets=manifest_assets,
        environment={
            "python": f"{sys.version_info.major}.{sys.version_info.minor}",
            "blender": blender_version(blender),
        },
        generator_version=GENERATOR_VERSION,
        generated_at=generated_at,
    )

    seed_report = {
        "algorithm": ALGORITHM_NAME,
        "formula": FORMULA_TEXT,
        "base_seed": base_seed,
        "assets": seed_report_assets,
    }

    _install(staging, target, manifest, seed_report, region_id)
    return manifest


def _install(staging: Path, target: Path, manifest: dict, seed_report: dict, region_id: str) -> None:
    """把暂存产物装进目标目录：先文件，后 manifest。"""
    meshes_src = staging / "meshes"
    meshes_dst = target / "meshes"
    meshes_dst.mkdir(parents=True, exist_ok=True)
    for src in sorted(meshes_src.glob("*.glb")):
        _atomic_copy(src, meshes_dst / src.name)

    write_manifest(target / "manifest.json", manifest)
    (target / "seed_report.json").write_text(
        json.dumps(seed_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"已安装到 {target}（region_id={region_id}）")


def _collect_entries(spec: dict) -> dict[str, dict]:
    """把 SceneSpec 的 assets 两段拍平成 {key: entry}。"""
    entries: dict[str, dict] = {}
    assets = spec.get("assets", {})
    for group in ("vegetation", "props"):
        for entry in assets.get(group) or []:
            if isinstance(entry, dict) and "key" in entry:
                entries[entry["key"]] = entry
    return entries
