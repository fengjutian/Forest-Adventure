"""GLB 导出，对应 docs/forest-pipeline-spec.md §4.3（材质契约）与 §4.4（LOD）。

Blender 5.3 的 glTF 导出器参数名和旧版教程不一样：
5.x 用 ``export_vertex_color="ACTIVE"``，没有 ``export_colors``。
导出后 Blender 的 Z-up 会自动转成 glTF 的 Y-up——
于是树在 Godot 里是**站着的**，底面落在 y = 0，正好满足 §4.2 的原点约定。
"""

from __future__ import annotations

from pathlib import Path

import bpy

__all__ = ["export_glb"]


def export_glb(obj: bpy.types.Object, path: Path | str) -> Path:
    """把对象导出成 GLB。

    不导出材质：运行时用 Godot 侧的 ``PropKit.painted_material()`` /
    ``swaying_material()``，它们只读顶点色（``ALBEDO = COLOR.rgb``），
    GLB 里带材质反而会被 Godot 导入器生成多余的 StandardMaterial3D。
    """
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(target),
        export_format="GLB",
        export_apply=True,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_materials="NONE",
    )
    return target
