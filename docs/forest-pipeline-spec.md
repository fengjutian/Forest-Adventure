# 森林生成管线规格（M3）

- 文档版本：V1.0
- 适用阶段：M3 程序化森林管线 → M4 内容替换
- 权威范围：SceneSpec 结构、资产契约、确定性契约、manifest 格式、Godot 导入检查规则
- 非权威范围：命名与 PBR 细节以 [`content-pipeline.md`](./content-pipeline.md) §4 为准；性能预算以 [`technical-design.md`](./technical-design.md) §5.4 为准；本文与两者冲突时以本文为准

---

## 1. 为什么需要这份文档

`technical-design.md` §6 与 `content-pipeline.md` §3 描述的是一条 **Blender 生成整场景、Godot 导入 GLB** 的管线。
但在这两份文档写下的同时，运行时已经长出了一套自己的世界生成系统，并且它已经跑通：

| 运行时事实 | 位置 |
|---|---|
| 全局高度真相 `TerrainField.height_at(x, z)` | `game/scripts/world/terrain_field.gd` |
| 区块流式加载、生成预算、种子派生 | `game/scripts/world/chunked_world.gd` |
| 区块网格、凹多边形碰撞、全局格点撒植被 | `game/scripts/world/world_chunk.gd` |
| 程序化网格与材质库 | `game/scripts/world/prop_kit.gd` |

两套系统都声称要"生成地形与植被"，**如果照原文实施，会出现两个高度真相、两套撒点逻辑**。
本文先裁决职责边界，再给出管线规格。

---

## 2. D1：职责边界（决策）

### 2.1 裁决

| 关注点 | 归属 | 落地位置 |
|---|---|---|
| 地形高度真相 | **运行时** | `TerrainField.height_at()` |
| 区块流式加载、生成预算、卸载 | **运行时** | `ChunkedWorld` |
| 植被撒点：在哪、哪种、多少 | **运行时** | `WorldChunk.build_vegetation()` |
| 资产网格：长什么样 | **Blender 管线** | `tools/forest_generator/` → `game/assets/generated/` |
| 材质、LOD、碰撞代理 | **Blender 管线** | 同上 |
| 稳定对象 ID、任务绑定、存档 | **Godot** | `EventBus` / `GameState` |
| manifest、校验值、预算统计 | **Blender 产出**，Godot 校验 | §7 / §8 |

一句话：**管线生产"资产"，运行时生产"世界"。**

### 2.2 理由

1. **无缝性已经是结构性保证，不是靠缝合补救的。**
   相邻区块在边界顶点上采样同一个 `height_at()`，世界坐标相同则高度必然相同，结构上不可能裂开。
   换成 Blender 烘焙地形，就必须另做一套"全局高度图采样器"来支撑玩家贴地、敌人落地和撒点，
   而 `TerrainField` 里已经调好的营地平整、溪谷下切、脊线门控三段逻辑会全部失效。
   单人开发下，这是**用一次高风险重写换一个离线烘焙速度**。

2. **撒点必须实时查询地形。**
   `WorldChunk` 的撒点规则同时用到坡度、密度噪声、溪谷距离、主路径距离和营地半径。
   这些量只有在地形生成时才知道，搬到 Blender 意味着运行时拿不到同等信息，
   只能把结果烘成一张点位表——而那样一来"改密度"就要重新烘焙全图。

3. **M3 真正要解决的是资产生产，不是场景烘焙。**
   M4 的交付物写得很清楚：「灰盒替换为正式或中等精度资产」。
   `PropKit` 里那些用基础几何体拼出来的低多边形树和石头，就是 M3 要替换的对象。
   让管线专注产资产，M3 的产出在 M4 可以直接交付。

4. **符合项目既定的策略。**
   `development-plan.md` §1 要求「先验证可玩性，再扩展世界，再提高内容生产效率」，
   §6 的风险应对写的是「锁定 P0，减少敌人和系统种类」。
   保留已经跑通的世界生成、把新增复杂度限制在"资产"这一个边界内，符合这两条。

### 2.3 被否决的替代方案

| 方案 | 否决理由 |
|---|---|
| **A. Blender 生成地形分块 GLB，Godot 导入** | 需要重写 `TerrainField` 为 heightmap 采样器，丢掉全部参数化调优；已验证的跨块无缝与确定性保证需要重新做一遍；单人开发风险过高 |
| **B. Blender 生成整个场景（含撒点）** | 运行时与管线各有一份撒点逻辑，必然随时间漂移；与存档的"改动区块"稀疏模型冲突（`GameState.chunk_modifications` 只能表达运行时改动，无法表达烘焙点位） |
| **C. Blender 出地形 GLB，Godot 仍用 `TerrainField` 查询** | 产生两个不一致的地形：一个决定看到什么，一个决定踩在哪。属于最坏情况 |

### 2.4 需要签字

D1 是本管线最大的架构决策。**在 M3-1 动工前需要项目负责人确认。**
若否决 D1，则方案 A 需要一份独立的迁移设计（heightmap 采样器、`TerrainField` 参数化回归、存档兼容），
工作量约为本文档其余部分的三倍。

---

## 3. SceneSpec

### 3.1 分层结构

```text
SceneSpec
├── schema_version   规格版本
├── seed             世界种子（决定资产形态）
├── region           区域身份与规模
├── world            世界外观参数  ← v1 不参与生成，v2 预留
├── assets           资产生产清单    ← v1 的主体
├── budget           资源预算
└── export           导出配置
```

### 3.2 完整结构（schema_version 1.1）

```json
{
  "schema_version": "1.1",
  "seed": 41721,
  "region": {
    "id": "pine_valley",
    "size_m": [1024, 1024],
    "style": "realistic",
    "season": "late_summer"
  },
  "world": {
    "terrain": {
      "amplitude": 7.0,
      "macro_amplitude": 26.0,
      "detail_amplitude": 1.4,
      "ridge_center_z": -340.0,
      "ridge_width": 140.0,
      "ridge_height": 50.0
    },
    "creek": {
      "center_x": 11.0,
      "half_width": 2.4,
      "depth": -1.15
    },
    "camp": {
      "flat_radius": 15.0,
      "blend_radius": 24.0,
      "height": 0.0
    },
    "vegetation": {
      "max_density": 0.72,
      "birch_ratio": 0.22,
      "snag_ratio": 0.07,
      "deadwood_ratio": 0.012,
      "rock_density": 0.16,
      "shrub_density": 0.30,
      "ground_cover_density": 0.50
    }
  },
  "assets": {
    "vegetation": [
      {
        "key": "pine_0",
        "variant": "pine",
        "lods": [0, 1, 2],
        "collision": "capsule",
        "height_m": [7.5, 12.0],
        "tags": ["sway"]
      },
      {
        "key": "rock",
        "variant": "rock",
        "lods": [0, 1],
        "collision": "box",
        "height_m": [0.6, 1.8],
        "tags": []
      }
    ],
    "props": [
      {
        "key": "cabin",
        "variant": "building",
        "lods": [0, 1, 2, 3],
        "collision": "box",
        "height_m": [3.0, 3.6],
        "tags": ["authored"]
      }
    ]
  },
  "budget": {
    "max_tris_lod0_per_asset": 900,
    "max_tris_lod1_per_asset": 300,
    "max_materials": 24,
    "max_textures": 48,
    "max_total_bytes": 33554432
  },
  "export": {
    "format": "glb",
    "apply_transform": true,
    "material_mode": "vertex_color"
  }
}
```

### 3.3 字段说明与约束

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `schema_version` | string | `"1.1"` | 不兼容变更必须升主版本 |
| `seed` | int | 0 ≤ s < 2³¹ | 决定所有资产形态 |
| `region.id` | string | `^[a-z][a-z0-9_]*$` | 同时用作产物目录名 |
| `region.size_m` | [number, number] | 均为正 | 区域边长（米） |
| `assets.*[].key` | string | 见 §4.1 | **必须与运行时 `mesh_for()` 的键完全一致** |
| `assets.*[].lods` | int[] | 升序、连续、从 0 开始 | LOD 编号集合 |
| `assets.*[].collision` | enum | `capsule` \| `box` \| `none` | 禁止三角网格碰撞 |
| `assets.*[].height_m` | [number, number] | min < max，均 > 0 | 用于边界检查与摆放缩放 |
| `assets.*[].tags` | string[] | 已知标签：`sway` `authored` `emissive` | `sway` 触发运行时风摆着色器 |
| `budget.max_tris_lod0_per_asset` | int | > 0 | 超预算即失败，不静默截断 |
| `export.material_mode` | enum | `vertex_color` | v1 仅支持该值 |

### 3.4 `world` 段在 v1 不参与生成

`world` 段的参数**逐项对应 `TerrainField` 与 `WorldChunk` 里的现有常量**
（见 `terrain_field.gd` 的 `amplitude` / `macro_amplitude` / `ridge_*` / `creek_*` / `camp_*`，
以及 `world_chunk.gd` 的 `BIRCH_RATIO` / `SNAG_RATIO` / `ROCK_DENSITY` 等）。

它当前的作用是**世界外观基准**：让管线产出的资产与运行时世界的地貌、密度、比例对齐。
v1 的管线**不读取**这一段去生成任何东西。

接入运行时的时点定为 v2：届时 `TerrainField` 改为从 `scene_spec.json` 加载参数，
并补一条回归测试保证「加载后的高度场与硬编码常量逐点一致」。
**在 v2 之前，`world` 段的所有数值改动不产生任何运行时效果**——这一点必须写进工具提示，避免误以为改了参数就能改地形。

---

## 4. 资产契约

### 4.1 资产键（接缝）

运行时通过 `ChunkedWorld.mesh_for(key)`（`chunked_world.gd`）按字符串键取网格。
**这个键就是管线与运行时的接缝**，键名不一致 = 运行时拿不到资产。

管线必须生产的键，以及它们在运行时的用途：

| 键 | 类型 | 变体 | 运行时用途 | 撒点占比 |
|---|---|---|---|---|
| `pine_0` … `pine_4` | 树 | 5 | 松树乔木 | 与桦树合计 100% |
| `birch_0` … `birch_1` | 树 | 2 | 桦树乔木 | 22% |
| `snag` | 树 | 1 | 枯立木 | 7% |
| `log` | 木 | 1 | 倒木 | 1.2% |
| `stump` | 木 | 1 | 树桩 | 1.2% |
| `rock` | 岩石 | 1 | 岩石 | 16% |
| `shrub` | 灌木 | 1 | 灌木 | 30% |
| `grass` | 地被 | 1 | 草丛 | 50% |
| `cabin` | 建筑 | 1 | 营地木屋 | 营地装配 |
| `cabin_windows` | 特效 | 1 | 窗内暖光（自发光） | 营地装配 |
| `supply_shed` | 建筑 | 1 | 物资棚 | 营地装配 |
| `generator` | 道具 | 1 | 发电机 | 营地装配 |
| `target` | 道具 | 1 | 训练靶 | 靶场 |
| `signpost` | 道具 | 1 | 路牌 | 营地装配 |
| `tent` | 道具 | 1 | 帐篷 | 营地装配 |
| `lantern_post` | 道具 | 1 | 灯柱 | 营地装配 |
| `lantern_glass` | 特效 | 1 | 灯柱玻璃（自发光） | 营地装配 |
| `woodpile` | 道具 | 1 | 柴堆 | 营地装配 |
| `barrel` | 道具 | 1 | 木桶 | 营地装配 |
| `crate` | 道具 | 1 | 物资箱 | 可交互物 |
| `radio` | 道具 | 1 | 无线电 | 可交互物 |
| `campfire_stones` | 道具 | 1 | 营火石圈 | 可交互物 |
| `campfire_logs` | 道具 | 1 | 营火柴 | 可交互物 |
| `grass_tuft` | 植被 | 1 | 拾取物视觉 | 掉落物 |

**清单外的键一律不生产。** 运行时 `mesh_for()` 对未知键只打一条 `GameLog.warn`，
不会崩——这类问题必须在导入检查阶段就被拦住（§8 检查项 2）。

角色与第一人称视图模型（`wolf_body`、`wolf_leg`、`arrow`、`bow_frame`、`bow_string`、
`player_hand`、`player_forearm`、`nocked_arrow`、`player_body`）**不属于本管线**，
它们是 M4 的人工资产，沿用 `PropKit` 的调用点。

### 4.2 原点约定

- 网格原点必须位于**资产落地接触面**，即 y = 0 是地面。
- 树资产的原点必须在**树根**，不能在几何中心。
  原因：运行时风摆着色器 `PropKit.swaying_material()` 用
  `VERTEX.y / sway_height` 做高度加权，原点错了会导致整棵树以腰为轴摆动，或根部摆动而树冠不动。
- 建筑类资产的原点在其底面中心。
- 禁止负缩放（`content-pipeline.md` §4.1 已规定，导入检查会复核）。

### 4.3 材质契约

**v1 只支持 `material_mode: "vertex_color"`。**

GLB 必须包含 `COLOR_0` 顶点色属性，运行时继续使用现有的两张材质：

| 运行时材质 | 用途 | 对管线的要求 |
|---|---|---|
| `PropKit.painted_material()` | 顶点色即反照率 | 顶点色必须非空且不全是白色 |
| `PropKit.swaying_material()` | 顶点色 + 高度加权风摆 | 同上；资产须带 `sway` 标签 |

**为什么 v1 不做 PBR 贴图**：`swaying_material()` 是手写 shader，`fragment()` 里只有
`ALBEDO = COLOR.rgb`，不采样任何贴图。若此时引入贴图资产，贴图会被静默丢弃——
画面看起来"没贴图"，但排查起来要跨 GDScript 和 Blender 两侧。

PBR 留到 v2，届时需要：改写风摆 shader 支持 albedo texture 与法线贴图、
引入材质库与纹理数组、以及贴图分辨率预算。v2 的改动范围见 §10 里程碑 M3-4。

`glow_material()`（自发光）用于 `cabin_windows` 与 `lantern_glass`：
这两个资产的顶点色需配合运行时既有的自发光材质使用，**v1 仍走顶点色路径**，不产出 Emission 贴图。

### 4.4 LOD 与碰撞

- LOD 编号从 0 开始、连续、升序。LOD0 精度最高。
- 三角面数随 LOD 递增方向**递减**，且 LOD1 ≤ LOD0、LOD2 ≤ LOD1。
- 碰撞代理类型限 `capsule` / `box` / `none`，**禁止用三角网格碰撞**。
- 草丛、灌木默认 `collision: "none"`。
- LOD 资产与碰撞代理可以放在同一个 GLB 里（多 primitive + 命名约定），
  但必须能从文件名区分：`env_tree_pine_a_lod0.glb`（命名规范见 `content-pipeline.md` §4.2）。

---

## 5. 确定性契约

### 5.1 目标

同一 `generator_version` + 同一 `seed` + 同一 SceneSpec → 逐字节相同的 manifest。
这是 M3 的退出条件之一（`development-plan.md` M3 退出条件第 1 条）。

### 5.2 种子派生算法（FNV-1a 32 位）

管线与运行时必须使用**同一个算法**，且该算法不依赖语言特有的整数语义。

```text
seed = base_seed AND 0xFFFFFFFF
for each byte b in utf8(key):
    seed = (seed XOR b) * 16777619 AND 0xFFFFFFFF
seed = (seed MOD 2147483647) + 1
```

- Python：`seed = (seed ^ b) * 16777619 & 0xFFFFFFFF`，每步都截断。
- GDScript：`*` 是 64 位有符号，但 `& 0xFFFFFFFF` 之后结果与 Python 一致。
  GDScript 的 `&` 对负数按二进制补码处理，因此**必须先 `& 0xFFFFFFFF` 再算**，
  或在最后统一 `& 0x7FFFFFFF`（两种写法等价，实现时选一种并写进单元测试）。

参考实现：`tools/forest_generator/lib/seed.py` 与 `game/scripts/core/seed_util.gd`，
两侧各有一条断言相同结果的单元测试。

### 5.3 浮点与顺序

- 所有随机取样使用固定的派生种子，**不得依赖遍历顺序之外的任何隐式状态**。
- 资产形态的随机数按"每个资产一个种子、每次取样推进序列"的方式消费，
  避免同一资产在不同调用点取到不同结果。
- Blender 的随机数不参与资产形态生成：形态种子一旦确定就固定，
  Blender 只负责把确定下来的参数变成网格。
- 顶点顺序、索引顺序、材质槽顺序都必须稳定，否则 sha256 会漂移。
  glTF 导出前按材质名与顶点位置排序。

### 5.4 跨语言一致性检查清单

生成 manifest 时，管线必须额外产出一份 `seed_report.json`，列出每个资产的
`key` 与最终派生种子。Godot 侧的导入检查器重算一遍并比对——
这是抓"Python 与 GDScript 算术不一致"的最直接手段。

---

## 6. 目录与产物布局

```text
tools/forest_generator/
├── main.py                      命令行入口
├── lib/
│   ├── seed.py                  §5.2 种子派生
│   ├── manifest.py              manifest 读写与统计
│   └── budget.py                预算检查
├── schemas/
│   └── scene_spec.schema.json   §3 的 JSON Schema
├── presets/
│   └── pine_valley.json         §3.2 的实例
├── blender/
│   ├── vegetation.py            树、灌木、草、岩石
│   ├── props.py                 建筑与道具
│   ├── materials.py             顶点色材质
│   ├── exporter.py              GLB 导出
│   └── renderer.py              预览图
└── output/                      生成产物（不入库）

game/assets/generated/
└── pine_valley/
    ├── manifest.json
    ├── seed_report.json
    └── meshes/
        ├── env_tree_pine_a_lod0.glb
        └── ...
```

生成产物与人工资产分目录保存（分层见 `content-pipeline.md` §2，
"生成器不得覆盖 authored 目录"见 `technical-design.md` §6.4），
**生成器不得覆盖 `game/assets/authored/`**。

---

## 7. manifest 格式

```json
{
  "manifest_version": "1.0",
  "schema_version": "1.1",
  "generator_version": "0.1.0",
  "seed": 41721,
  "region_id": "pine_valley",
  "material_mode": "vertex_color",
  "generated_at": "2026-11-17T12:00:00Z",
  "environment": {
    "python": "3.13",
    "blender": "5.3.0"
  },
  "assets": [
    {
      "key": "pine_0",
      "variant": "pine",
      "files": [
        { "lod": 0, "path": "meshes/env_tree_pine_a_lod0.glb", "sha256": "…", "bytes": 51234 }
      ],
      "tris": { "lod0": 412, "lod1": 96, "lod2": 24 },
      "bounds": {
        "min": [-1.20, 0.00, -1.20],
        "max": [ 1.20, 9.80,  1.20]
      },
      "collision": { "type": "capsule", "radius": 0.28, "height": 9.80 },
      "tags": ["sway"]
    }
  ],
  "totals": {
    "assets": 24,
    "files": 51,
    "bytes": 4821004,
    "tris_lod0": 11340,
    "materials": 9,
    "textures": 0
  },
  "warnings": []
}
```

约束：

- `manifest_version` 与 `schema_version` 都必须记录。`generator_version` 变化导致输出变化时必须提升它
  （`content-pipeline.md` §9）。
- `totals` 必须由实际产物统计得出，不允许手写。
- `warnings` 非空时不阻断产出，但导入检查器会把非空 warning 标为需人工确认。
- 写入采用**临时文件 + 原子替换**，并保留上一版有效输出；
  失败的任务不得覆盖上一版有效输出（`content-pipeline.md` §8）。

---

## 8. Godot 导入检查器

位置：`game/tests/asset_check.gd`（`extends SceneTree`，可在无头模式运行）。

调用：

```powershell
& $env:GODOT_EXE --headless --path game --script res://tests/asset_check.gd
```

资产本身能否被 Godot 导入，由 `--import` 步骤覆盖（导入失败即非零退出码）。

### 检查项

| # | 检查 | 失败级别 |
|---|---|---|
| 1 | manifest 存在且符合 §7 结构 | P0 |
| 2 | 每个 `key` 在 §4.1 的已知键表内 | P0 |
| 3 | 每个文件存在，sha256 与 manifest 一致 | P0 |
| 4 | 单资产 LOD0 三角面 ≤ 预算 | P0 |
| 5 | LOD 数量与声明一致，且三角面随 LOD 递减 | P0 |
| 6 | 碰撞代理存在且类型合法（非三角网格） | P0 |
| 7 | `material_mode = vertex_color` 时 COLOR_0 存在且非全白 | P0 |
| 8 | 树类资产的包围盒 min.y ≈ 0（原点接触面约定） | P1 |
| 9 | 材质总数 ≤ 预算，纹理数 ≤ 预算 | P1 |
| 10 | 资产包围盒尺寸在 SceneSpec 声明的 `height_m` 区间附近 | P1 |
| 11 | 文件命名符合 `type_variant_lod` 规范 | P2 |
| 12 | 重算种子与 `seed_report.json` 一致 | P0 |
| 13 | `generator_version` 与管线当前版本一致 | P1 |
| 14 | `warnings` 为空 | P2 |

P0 / P1 阻断构建（`development-plan.md` §5：垂直切片发布前必须清除所有 P0/P1 缺陷）。
P2 记录到日志不阻断。

### 检查器自身的可靠性

检查器必须有一个**已知会失败的夹具**（故意越界的 manifest），
随管线一起进版本库，并由无头测试跑一次，确认它真的报错。
否则"检查器永远通过"和"检查器有效"无法区分。

---

## 9. 局部重生成

`content-pipeline.md` §7 给出的 `update_layer` 操作需要扩展为按**资产**粒度：

```json
{
  "operation": "update_asset",
  "region_id": "pine_valley",
  "key": "pine_0",
  "changes": { "height_m": [8.0, 13.0], "tags": ["sway"] }
}
```

规则：

- 重生成单个资产**只影响该 key**，其他资产的文件与 sha256 必须保持不变。
- 重生成后重新计算该资产的派生种子，manifest 中其余条目原样保留。
- **不得触碰 `game/assets/authored/`**（`technical-design.md` §6.4；分层见 `content-pipeline.md` §2）。
- 人工在 Godot 侧对生成资产做的调整不能写在生成文件内部；
  重新生成时只替换生成部分，人工部分由稳定锚点 ID 重新绑定。

实现上，manifest 的每个资产条目独立可寻址，是"局部重生成不波及他人"的前提。

---

## 10. 里程碑拆分

| 里程碑 | 交付 | 退出条件 |
|---|---|---|
| **M3-1** 规格与骨架 | 本文档冻结；SceneSpec JSON Schema；`lib/seed.py` + `seed_util.gd` 与一致性单测；`main.py --validate` 能校验 SceneSpec | SceneSpec 非法输入必须失败；两侧种子派生结果逐位一致 |
| **M3-2** 单资产端到端 | 1 个松树资产（`pine_0`）走完：SceneSpec → Blender → GLB → manifest → Godot 侧 `mesh_for("pine_0")` 能取到该网格 | 运行时加载的是管线产出的 GLB 而不是 `PropKit` 的程序化网格；同 seed 重跑 sha256 不变 |
| **M3-3** 全量资产 | §4.1 全部 24 个键 | 导入检查器全部通过；帧时间不劣于现状（当前 1080p 平均帧 7.8 ms） |
| **M3-4** 工程化 | 导入检查器 + 失败夹具；局部重生成；预览图渲染；CI 接入 | 局部重生成不波及其他资产；失败夹具能触发 P0 |

**M3-1 不碰 Blender。** 先把 Schema、种子、预算、manifest 这些纯逻辑跑通并测住，
再接 Blender。这样出问题时能立刻分清是"规格错了"还是"Blender 脚本错了"——
这正是 `development-plan.md` §1「AI 接入晚于确定性的 Blender 生成器」要防的那类混淆。

---

## 11. 风险

| 风险 | 应对 |
|---|---|
| D1 被否决导致管线重做 | M3-1 开工前先签字；本文档把替代方案的成本写明 |
| 管线产出的资产与运行时参数不匹配 | 资产键表 §4.1 直接由 `mesh_for()` 反推；导入检查项 2 强制校验 |
| 顶点色在 Blender 与 Godot 之间色彩空间不一致 | Blender 端 sRGB 顶点色 → 导出后顶点色按线性处理；导入检查项 7 抽查非全白 |
| 导入检查器形同虚设 | 失败夹具随管线进版本库（M3-4） |
| 资产数量膨胀导致材质数超预算 | `budget.max_materials` 硬约束；共享顶点色材质，不新增材质槽 |
| 管线产出没人用 | M3-2 的退出条件就是"运行时真的加载了 GLB"，不接受"产出了但没接上" |

---

## 12. 与既有文档的关系

| 文档 | 关系 |
|---|---|
| `technical-design.md` §6 | **职责部分被本文 §2 取代**（原文描述 Blender 生成地形分块 GLB 并由 Godot 导入） |
| `content-pipeline.md` §3 | 流程保留（AI → SceneSpec → 校验 → 人工确认 → Blender → 检查 → 导出 → 导入），但"生成地形与撒点"改为"生成资产" |
| `content-pipeline.md` §4 | 命名与 PBR 规范继续有效；§4.4 的 LOD/碰撞要求由本文 §4.4 补充为可校验的硬约束 |
| `content-pipeline.md` §5 | Chunk 输出目录结构由本文 §6 取代（管线不再按世界分块输出） |
| `content-pipeline.md` §7 | `update_layer` 扩展为 `update_asset`，见本文 §9 |
| `development-plan.md` M3 | 交付项"分块 GLB"改为"资产 GLB"；退出条件第 1 条（确定性）细化见本文 §5 |
