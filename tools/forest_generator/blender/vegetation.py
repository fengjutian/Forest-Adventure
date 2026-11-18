"""Blender 侧的网格构建与导出，对应 docs/forest-pipeline-spec.md §4.2 / §4.3 / §4.4 / §5.3。

**这里是纯函数**：同样的参数必然建出同样的网格、导出同样的字节。
Blender 的随机数不参与形态生成——形态种子在 Python 侧（``lib/params.py``）已经定死，
Blender 只负责把确定下来的参数变成网格（§5.3）。
"""

from __future__ import annotations

import math

import bmesh
import bpy

__all__ = ["build_pine", "mesh_stats"]


def _ring(bm: bmesh.types.BMesh, radius: float, z: float, sides: int,
          color: tuple, colors: dict) -> list:
    """在高度 z 处放一圈顶点。"""
    verts = []
    for i in range(sides):
        angle = 2.0 * math.pi * i / sides
        vert = bm.verts.new((radius * math.cos(angle), radius * math.sin(angle), z))
        colors[vert] = color
        verts.append(vert)
    return verts


def _frustum(bm: bmesh.types.BMesh, z0: float, z1: float, r0: float, r1: float,
             sides: int, color: tuple, colors: dict) -> tuple:
    """建一个圆台。

    ``r1 == 0`` 时收成锥尖（只用一个顶点，避免退化三角形）。
    """
    lower = _ring(bm, r0, z0, sides, color, colors)
    if r1 <= 0.0:
        apex = bm.verts.new((0.0, 0.0, z1))
        colors[apex] = color
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lower[i], lower[j], apex))
        return lower, [apex]
    upper = _ring(bm, r1, z1, sides, color, colors)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((lower[i], lower[j], upper[j]))
        bm.faces.new((lower[i], upper[j], upper[i]))
    return lower, upper


def _canopy_layout(params: dict) -> list:
    """算出每一层的 (z0, z1, r0, r1, color)。

    规则（唯一约定，Python 侧不参与）：

    - 树冠底 ``canopy_base = trunk_height * 0.55``，与树干下半段重叠；
    - 树梢正好落在 ``height_m``；
    - 层距 ``pitch = canopy_span / (tier_count + canopy_overlap)``，
      每层高 ``pitch * (1 + canopy_overlap)``——
      层高大于层距，相邻层因此**重叠** ``canopy_overlap``，轮廓连续无缝；
    - 半径系数从最下层的 1.0 线性递减到最上层的 0.5；
    - 每层顶部收到本层底半径的 0.24；**最顶层收到 0**，形成树梢。
    """
    height = float(params["height_m"])
    trunk_height = float(params["trunk_height"])
    tier_count = int(params["tier_count"])
    canopy_radius = float(params["canopy_radius"])
    overlap = float(params["canopy_overlap"])
    jitter = list(params.get("tier_jitter") or [])
    needle = tuple(params["needle_color"])
    needle_top = tuple(params["needle_color_top"])

    canopy_base = trunk_height * 0.55
    canopy_span = height - canopy_base
    if canopy_span <= 0.0:
        raise ValueError(
            f"height_m({height}) 必须大于 trunk_height*0.55({canopy_base})，树冠没有空间"
        )
    pitch = canopy_span / (tier_count + overlap)
    tier_height = pitch * (1.0 + overlap)

    layers = []
    for i in range(tier_count):
        z0 = canopy_base + i * pitch
        z1 = z0 + tier_height
        factor = 1.0 if tier_count == 1 else 1.0 - 0.5 * (i / (tier_count - 1))
        local_jitter = float(jitter[i]) if i < len(jitter) else 0.0
        r0 = canopy_radius * factor * (1.0 + local_jitter)
        is_top = i == tier_count - 1
        r1 = 0.0 if is_top else r0 * 0.24
        color = needle_top if is_top else needle
        layers.append((z0, z1, r0, r1, color))
    return layers


def build_pine(params: dict) -> bpy.types.Object:
    """按参数建一棵松树，返回场景里的 Object。

    网格原点位于**树根**（y = 0 是地面），这是 §4.2 的原点约定：
    运行时的风摆着色器用 ``VERTEX.y / sway_height`` 做高度加权，
    原点错了会导致整棵树以腰为轴摆动，或者根部摆动而树冠不动。
    """
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    sides = max(3, int(params["sides"]))
    trunk_color = tuple(params["trunk_color"])
    trunk_radius = float(params["trunk_radius"])
    trunk_height = float(params["trunk_height"])

    mesh = bpy.data.meshes.new(params.get("key", "pine"))
    colors: dict = {}

    bm = bmesh.new()
    # 树干：底半径大、顶半径小，底部封口
    lower, _ = _frustum(
        bm, 0.0, trunk_height, trunk_radius, trunk_radius * 0.62, sides, trunk_color, colors
    )
    bm.faces.new(tuple(reversed(lower)))
    for z0, z1, r0, r1, color in _canopy_layout(params):
        _frustum(bm, z0, z1, r0, r1, sides, color, colors)

    bm.normal_update()
    bm.verts.ensure_lookup_table()
    vertex_colors = [colors.get(v, trunk_color) for v in bm.verts]
    bm.to_mesh(mesh)
    bm.free()

    # 顶点色（GLB 里的 COLOR_0）。domain=POINT，一个颜色对应一个顶点。
    color_attr = mesh.color_attributes.new(name="Col", type="BYTE_COLOR", domain="POINT")
    for index, color in enumerate(vertex_colors):
        color_attr.data[index].color = (color[0], color[1], color[2], 1.0)

    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def mesh_stats(mesh: bpy.types.Mesh) -> dict:
    """网格统计：顶点数、面数、包围盒（Blender 本地 Z-up 坐标系）。"""
    coords = [v.co for v in mesh.vertices]
    if not coords:
        return {"verts": 0, "polys": 0, "tris": 0, "bbox_min": [0, 0, 0], "bbox_max": [0, 0, 0]}
    return {
        "verts": len(mesh.vertices),
        "polys": len(mesh.polygons),
        "tris": sum(max(0, len(poly.vertices) - 2) for poly in mesh.polygons),
        "bbox_min": [min(c[i] for c in coords) for i in range(3)],
        "bbox_max": [max(c[i] for c in coords) for i in range(3)],
    }
