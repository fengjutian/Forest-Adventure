"""资产键表：管线与运行时的接缝，对应 docs/forest-pipeline-spec.md §4.1。

规格 §4.1 的表格是 24 行，其中 ``pine_0 … pine_4`` 与 ``birch_0 … birch_1`` 是区间，
展开后共 **29 个键**（13 个植被键 + 16 个道具键）。本模块是这张表的唯一真相源。

两种运行时接缝（``seam``）：

- ``mesh_for``  —— ``ChunkedWorld.mesh_for(key)``，13 个植被键。
- ``make_prop`` —— ``PropKit.make_prop(key)``，16 个道具键。

M3-1 时道具键里还有 5 个是 ``direct``（营地装配处硬编码调用 ``PropKit.make_xxx()``，
运行时没有字符串键可查）。M3-2 已把 ``PropKit.make_prop()`` 扩成完整的 16 键注册表，
并把营地装配处的调用点也改成走字符串键——``direct`` 这一类因此消失。
"""

from __future__ import annotations

# 接缝种类
SEAM_MESH_FOR = "mesh_for"
SEAM_MAKE_PROP = "make_prop"

# 资产类别
CATEGORY_VEGETATION = "vegetation"
CATEGORY_PROP = "prop"

#: 已知标签（§3.3）：``sway`` 触发运行时风摆着色器
KNOWN_TAGS: set[str] = {"sway", "authored", "emissive"}

#: glTF 文件名里的 category 段（命名规范见 content-pipeline.md §4.2）。
#: 与 §4.1 的「类型」列一一对应。
GLTF_CATEGORY: dict[str, str] = {
    "pine_0": "tree", "pine_1": "tree", "pine_2": "tree", "pine_3": "tree",
    "pine_4": "tree", "birch_0": "tree", "birch_1": "tree", "snag": "tree",
    "log": "wood", "stump": "wood",
    "rock": "rock",
    "shrub": "shrub",
    "grass": "ground_cover",
    "grass_tuft": "ground_cover",
    "cabin": "building", "supply_shed": "building",
    "cabin_windows": "effect", "lantern_glass": "effect",
    "target": "prop", "signpost": "prop", "tent": "prop",
    "lantern_post": "prop", "woodpile": "prop", "barrel": "prop",
    "crate": "prop", "radio": "prop",
    "campfire_stones": "prop", "campfire_logs": "prop",
    "generator": "prop",
}

#: 合法碰撞代理类型（§3.3 / §4.4）：禁止三角网格碰撞
KNOWN_COLLISIONS: tuple[str, ...] = ("capsule", "box", "none")

# 植被键：(键, 变体)。运行时接缝一律是 ChunkedWorld.mesh_for()。
_VEGETATION_TABLE: tuple[tuple[str, str], ...] = (
    ("pine_0", "pine"),
    ("pine_1", "pine"),
    ("pine_2", "pine"),
    ("pine_3", "pine"),
    ("pine_4", "pine"),
    ("birch_0", "birch"),
    ("birch_1", "birch"),
    ("snag", "snag"),
    ("log", "log"),
    ("stump", "stump"),
    ("rock", "rock"),
    ("shrub", "shrub"),
    ("grass", "grass"),
)

# 道具键：(键, 变体)。接缝一律是 PropKit.make_prop()。
_PROP_TABLE: tuple[tuple[str, str], ...] = (
    ("cabin", "building"),
    ("cabin_windows", "effect"),
    ("supply_shed", "building"),
    ("generator", "prop"),
    ("target", "prop"),
    ("signpost", "prop"),
    ("tent", "prop"),
    ("lantern_post", "prop"),
    ("lantern_glass", "effect"),
    ("woodpile", "prop"),
    ("barrel", "prop"),
    ("crate", "prop"),
    ("radio", "prop"),
    ("campfire_stones", "prop"),
    ("campfire_logs", "prop"),
    ("grass_tuft", "vegetation"),
)


def _build_key_info() -> dict[str, dict]:
    """构造 KEY_INFO：键 -> key / category / seam / variant。"""
    info: dict[str, dict] = {}
    for key, variant in _VEGETATION_TABLE:
        info[key] = {
            "key": key,
            "category": CATEGORY_VEGETATION,
            "seam": SEAM_MESH_FOR,
            "variant": variant,
        }
    for key, variant in _PROP_TABLE:
        info[key] = {
            "key": key,
            "category": CATEGORY_PROP,
            "seam": SEAM_MAKE_PROP,
            "variant": variant,
        }
    # 树类资产带变体序号，方便与 world_chunk.gd 的 PINE_VARIANTS / BIRCH_VARIANTS 对齐
    for index in range(5):
        info[f"pine_{index}"]["variant_index"] = index
    for index in range(2):
        info[f"birch_{index}"]["variant_index"] = index
    return info


#: 每个键的元信息（§4.1）
KEY_INFO: dict[str, dict] = _build_key_info()

#: 全部 29 个键，顺序：先植被 13，后道具 16
ASSET_KEYS: list[str] = list(KEY_INFO.keys())

#: 13 个植被键（运行时接缝 mesh_for）
VEGETATION_KEYS: list[str] = [
    key for key in ASSET_KEYS if KEY_INFO[key]["category"] == CATEGORY_VEGETATION
]

#: 16 个道具键（运行时接缝 make_prop 或 direct）
PROP_KEYS: list[str] = [
    key for key in ASSET_KEYS if KEY_INFO[key]["category"] == CATEGORY_PROP
]


def is_known(key: str) -> bool:
    """键是否在 §4.1 的已知键表内。"""
    return key in KEY_INFO


def seam_of(key: str) -> str | None:
    """返回键的运行时接缝；未知键返回 None。"""
    entry = KEY_INFO.get(key)
    return None if entry is None else entry["seam"]


def keys_by_seam(seam: str) -> list[str]:
    """按接缝筛选键，保持 ASSET_KEYS 的顺序。"""
    return [key for key in ASSET_KEYS if KEY_INFO[key]["seam"] == seam]


def keys_by_category(category: str) -> list[str]:
    """按类别筛选键，保持 ASSET_KEYS 的顺序。"""
    return [key for key in ASSET_KEYS if KEY_INFO[key]["category"] == category]


def asset_name(key: str) -> tuple[str, str]:
    """返回 (name, variant_letter)。

    ``pine_0`` → ``("pine", "a")``、``pine_3`` → ``("pine", "d")``；
    没有序号后缀的键（``rock`` / ``shrub`` / ``cabin``）→ ``("rock", "a")``。
    """
    if key not in KEY_INFO:
        raise KeyError(f"未知资产键：{key}")
    head, _, tail = key.rpartition("_")
    if head and tail.isdigit():
        return head, chr(ord("a") + int(tail))
    return key, "a"


def glb_filename(key: str, lod: int) -> str:
    """按 content-pipeline.md §4.2 的命名规范给出 GLB 文件名。

    例：``pine_0`` 的 LOD0 → ``env_tree_pine_a_lod0.glb``。
    """
    name, variant = asset_name(key)
    category = GLTF_CATEGORY.get(key)
    if category is None:
        raise KeyError(f"资产键 '{key}' 没有 glTF category 映射")
    return f"env_{category}_{name}_{variant}_lod{lod}.glb"
