"""Blender 构建入口：读 build spec JSON → 建网格 → 导 GLB → 打印统计。

用法::

    blender.exe --background --factory-startup \
        --python tools/forest_generator/blender/build_asset.py -- <build_spec.json> <输出.glb>

stdout 会打印一行 ``BUILD_JSON:`` 开头的 JSON，供 Python 侧解析。

**不用** ``bpy.ops.wm.read_homefile()``：后台模式下它会弹启动画面，
直接删场景对象更干净。**不用** ``bpy.ops.mesh.primitive_*``：启动脚本里它不可靠，
一律用 bmesh。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy

# 让同目录的模块可导入（脚本是以 __main__ 跑的）
sys.path.insert(0, str(Path(__file__).resolve().parent))

from exporter import export_glb  # noqa: E402
from vegetation import build_pine, mesh_stats  # noqa: E402


def _argv() -> list:
    if "--" in sys.argv:
        index = sys.argv.index("--")
        return sys.argv[index + 1 :]
    return []


def main() -> int:
    args = _argv()
    if len(args) < 2:
        print("用法：build_asset.py -- <build_spec.json> <输出.glb>", file=sys.stderr)
        return 2

    spec_path = Path(args[0])
    out_path = Path(args[1])
    params = json.loads(spec_path.read_text(encoding="utf-8"))

    obj = build_pine(params)
    # Blender 5.x 的 Object 没有 .mesh 便捷属性，网格从 .data 取
    mesh = obj.data
    stats = mesh_stats(mesh)
    export_glb(obj, out_path)

    report = {
        "key": params.get("key"),
        "lod": params.get("lod"),
        "filename": params.get("filename"),
        "path": str(out_path),
        "verts": stats["verts"],
        "polys": stats["polys"],
        "tris": stats["tris"],
        "bbox_min": [round(float(v), 6) for v in stats["bbox_min"]],
        "bbox_max": [round(float(v), 6) for v in stats["bbox_max"]],
        "has_vertex_color": len(mesh.color_attributes) > 0,
        "bytes": out_path.stat().st_size if out_path.exists() else 0,
    }
    print("BUILD_JSON:" + json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
