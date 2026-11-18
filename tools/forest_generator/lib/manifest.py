"""manifest 读写与统计，对应 docs/forest-pipeline-spec.md §7。

约束（§7）：

- ``manifest_version`` 与 ``schema_version`` 都必须记录；
- ``totals`` 必须由实际产物统计得出，不允许手写；
- 写入采用**临时文件 + 原子替换**，失败的任务不得覆盖上一版有效输出。

确定性（§5.3）：``generated_at`` 由调用方传入，库里不调用 ``datetime.now()``。
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any, Iterable

#: manifest 结构版本
MANIFEST_VERSION = "1.0"

#: 写临时文件时的后缀
TMP_SUFFIX = ".tmp"

#: 单次读取 sha256 的块大小
_CHUNK = 1 << 20


def build_manifest(
    spec: dict,
    assets: Iterable[dict],
    environment: dict,
    generator_version: str,
    generated_at: str,
) -> dict:
    """构造 manifest 字典，``totals`` 由实际资产数据统计得出。

    ``assets`` 的每一项含 ``key`` / ``variant`` / ``files``（每项 ``lod`` / ``path`` /
    ``sha256`` / ``bytes``）/ ``tris``（dict，lod 名 → 三角面数）/ ``bounds`` /
    ``collision`` / ``tags``；``materials`` 与 ``textures`` 是可选的每资产计数。
    """
    asset_list = list(assets or [])
    files = 0
    bytes_total = 0
    tris_lod0 = 0
    materials = 0
    textures = 0

    for entry in asset_list:
        if not isinstance(entry, dict):
            continue
        for file_entry in entry.get("files") or []:
            if not isinstance(file_entry, dict):
                continue
            files += 1
            size = file_entry.get("bytes")
            if isinstance(size, int) and not isinstance(size, bool):
                bytes_total += size
        tris = entry.get("tris")
        if isinstance(tris, dict):
            count = tris.get("lod0")
            if isinstance(count, int) and not isinstance(count, bool):
                tris_lod0 += count
        for field in ("materials", "textures"):
            count = entry.get(field)
            if isinstance(count, int) and not isinstance(count, bool):
                if field == "materials":
                    materials += count
                else:
                    textures += count

    region = spec.get("region") if isinstance(spec, dict) else None
    export = spec.get("export") if isinstance(spec, dict) else None
    region_id = region.get("id") if isinstance(region, dict) else None
    material_mode = export.get("material_mode") if isinstance(export, dict) else None

    return {
        "manifest_version": MANIFEST_VERSION,
        "schema_version": spec.get("schema_version") if isinstance(spec, dict) else None,
        "generator_version": generator_version,
        "seed": spec.get("seed") if isinstance(spec, dict) else None,
        "region_id": region_id,
        "material_mode": material_mode,
        "generated_at": generated_at,
        "environment": dict(environment or {}),
        "assets": asset_list,
        "totals": {
            "assets": len(asset_list),
            "files": files,
            "bytes": bytes_total,
            "tris_lod0": tris_lod0,
            "materials": materials,
            "textures": textures,
        },
        "warnings": [],
    }


def write_manifest(path: Path | str, manifest: dict) -> None:
    """原子写入 manifest：先写 ``<path>.tmp``，再 ``os.replace``。

    失败时抛异常并保留上一版有效输出——临时文件只在整份内容写完之后才替换正式文件。
    """
    target = Path(path)
    tmp = target.with_name(target.name + TMP_SUFFIX)
    text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    try:
        with open(tmp, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, target)
    except BaseException:
        try:
            if tmp.exists():
                tmp.unlink()
        except OSError:
            pass
        raise


def read_manifest(path: Path | str) -> dict:
    """读取 manifest。"""
    return json.loads(Path(path).read_text(encoding="utf-8"))


def sha256_file(path: Path | str) -> str:
    """文件的 sha256 十六进制摘要。"""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(_CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()
