# 森林生成管线工具链（M3-1）

对应规格文档 [`docs/forest-pipeline-spec.md`](../../docs/forest-pipeline-spec.md)。
**本文中的 `§N` 一律指该文档的第 N 节。**

本目录是 M3 管线的 Python 侧。**M3-1 只做纯逻辑骨架**：SceneSpec 校验、种子派生、
预算检查、manifest 读写。**M3-1 不碰 Blender**（`blender/` 目录属于 M3-2/M3-3）。

职责边界见规格 §2：**管线生产"资产"，运行时生产"世界"**。地形高度、撒点、植被密度
仍然由运行时的 `TerrainField` / `WorldChunk` 决定，管线不烘焙任何场景数据。

## 目录

```text
tools/forest_generator/
├── main.py                      命令行入口
├── lib/
│   ├── seed.py                  §5.2 种子派生（FNV-1a 32 位）
│   ├── asset_keys.py            §4.1 资产键表（唯一真相源）
│   ├── jsonschema_mini.py       JSON Schema 子集校验器（零依赖）
│   ├── spec.py                  §3.2 / §3.3 SceneSpec 两层校验
│   ├── params.py                §5.3 形态参数派生与 LOD 规则
│   ├── budget.py                §3.3 预算检查
│   ├── manifest.py              §7 manifest 读写与统计
│   └── build.py                 构建编排：参数 → Blender → GLB → manifest
├── blender/
│   ├── vegetation.py            按参数建网格（纯函数）
│   ├── exporter.py              GLB 导出
│   └── build_asset.py           Blender 侧命令行入口
├── schemas/
│   └── scene_spec.schema.json   §3 的 JSON Schema（draft 2020-12）
├── presets/
│   └── pine_valley.json         §3.2 的合法实例
├── tests/                       pytest 用例
└── output/                      构建暂存（不入库）
```

## 命令

```powershell
python tools/forest_generator/main.py --validate tools/forest_generator/presets/pine_valley.json
python tools/forest_generator/main.py --keys
python tools/forest_generator/main.py --derive-seeds 41721
python tools/forest_generator/main.py --emit-golden
python tools/forest_generator/main.py --check-golden

# 构建资产（M3-2）：参数 → Blender → GLB → manifest
python tools/forest_generator/main.py --build --build-keys pine_0
```

- `--validate`：合法时退出 0 并打印 `OK`；非法时**非零退出**并逐条打印 error / warning。
- `--keys`：打印 §4.1 的 29 个键及其运行时接缝。
- `--derive-seeds`：打印所有键的派生种子（§5.2）。
- `--emit-golden` / `--check-golden`：黄金向量的写出与比对（自检用）。
- `--build`：真的调 Blender 建网格、导 GLB、产出 manifest。
  `--build-keys` 指定要建哪些键（逗号分隔，默认全部 `pine_*`），
  `--out` 指定产物目录（默认 `game/assets/generated/<region_id>/`）。

所有输出走 UTF-8。

## 依赖

运行期**只依赖 Python 3.12 标准库**，`lib/` 下没有任何第三方 import。
开发期依赖（pytest、jsonschema）列在 [`requirements.txt`](./requirements.txt)：

```powershell
python -m pip install -r tools/forest_generator/requirements.txt
python -m pytest tools/forest_generator/tests -q
```

`jsonschema` 只出现在测试里：用于把 `lib/jsonschema_mini.py` 与标准库交叉验证
（同一批用例，两个实现"有/无 error"的结论必须一致）。没装 `jsonschema` 时
该交叉验证自动跳过，其余用例照常运行。

## 种子契约（§5.2）

```text
seed = base_seed AND 0xFFFFFFFF
for each byte b in utf8(key):
    seed = (seed XOR b) * 16777619 AND 0xFFFFFFFF
seed = (seed MOD 2147483647) + 1
```

- Python 参考实现：[`lib/seed.py`](./lib/seed.py)
- GDScript 参考实现：`game/scripts/core/seed_util.gd`
- 黄金向量：`game/tests/fixtures/seed_golden.json`（29 个键 × 6 个 base_seed = 174 组，
  外加 6 组边界用例：空串、非 ASCII、超长键、结尾换行）

两侧**不是互相比对**，而是对同一份黄金向量各自复现——黄金向量由第三份独立实现算出，
三方一致才能排除两侧犯了同一个错。

## 资产键与运行时接缝（§4.1）

§4.1 的表格有 24 **行**，展开后是 **29 个键**（13 个植被 + 16 个道具）。
`lib/asset_keys.py` 是这张表的唯一真相源，运行时**有两处不同的取网格方式**：

| 接缝 | 调用点 | 键数 | 说明 |
|---|---|---|---|
| `mesh_for` | `ChunkedWorld.mesh_for(key)` | 13 | 植被键 |
| `make_prop` | `PropKit.make_prop(key)` | 16 | 道具键 |

M3-1 时道具键里有 5 个是第三种接缝 `direct`（营地装配处硬编码调用
`PropKit.make_cabin()`，运行时没有字符串键可查，管线产的 GLB 接不上）。
**M3-2 已补齐**：`PropKit.make_prop()` 扩成完整的 16 键注册表，
营地装配处的调用点也全部改成 `PropKit.make_prop(&"cabin")` 形式。

`tests/test_asset_keys.py` 会反向解析 `world_chunk.gd` / `prop_kit.gd` /
`chunked_world.gd` / `camp_builder.gd` 核对变体数量与接缝分支——
改了运行时却忘了同步管线，测试会直接失败。

## 两层校验

**第一层（schema 层）**：`lib/jsonschema_mini.py` 校验 `schemas/scene_spec.schema.json`。
它自己实现了用到的 JSON Schema 子集（`type` / `const` / `enum` / `required` /
`properties` / `additionalProperties` / `items` / `prefixItems` / `minItems` / `maxItems` /
`uniqueItems` / `minimum` / `maximum` / `exclusiveMinimum` / `exclusiveMaximum` /
`minLength` / `maxLength` / `pattern` / `$ref`（仅 `#/$defs/<name>`）/ `$defs` /
`allOf` / `anyOf` / `oneOf` / `not`），路径是 JSON Pointer 风格。

**第二层（语义层）**：`lib/spec.py` 校验 schema 表达不了的跨字段规则：

1. `assets.*[].key` 必须 ∈ 29 个已知键；
2. 完整性：植被 + 道具的键并集**恰好等于** 29 个键（少一个、多一个、重复都报错）；
3. `height_m[0] < height_m[1]`，且两者都 > 0；
4. `lods` 升序、连续、从 0 开始；
5. `tags` 元素 ∈ `sway` / `authored` / `emissive`；
6. `region.size_m` 两项均 > 0；
7. `budget` 各字段范围合法。

issue 结构是 `{"level": "error"|"warning", "path": ..., "message": ...}`。
schema 层的 `path` 是 JSON Pointer（`/assets/vegetation/0/height_m/1`），
语义层的 `path` 是点号风格（`assets.vegetation[3].height_m`）。

## 构建（M3-2）

```powershell
python tools/forest_generator/main.py --build --build-keys pine_0
```

流程是**两段**的，中间用暂存目录隔开：

1. **形态参数**（`lib/params.py`）——从派生种子算出树高、冠幅、树干粗细、层数、
   每层的半径微扰、颜色乘系数。**Blender 的随机数不参与形态生成**（§5.3）：
   种子在这里定死，Blender 只负责把确定下来的参数变成网格。
   随机数发生器是自己实现的 xorshift32，不用标准库 `random`——
   后者的实现细节可能随版本变化，而这里是跨版本的长期契约。
2. **Blender**（`blender/build_asset.py`）——读 build spec JSON，建网格、导 GLB，
   打印一行 `BUILD_JSON:` 开头的统计。Blender 5.3 的 glTF 导出器参数名和旧教程不同，
   用的是 `export_vertex_color="ACTIVE"`，没有 `export_colors`。

产物先落在 `output/<region_id>/staging/`，全部成功后才装进
`game/assets/generated/<region_id>/`，并且 **manifest 最后写**——
中途被打断时 manifest 里的 sha256 仍指向旧文件，导入检查器能查出不一致，
而不是静默损坏。

Blender 的位置：环境变量 `BLENDER_EXE` 优先，否则找默认安装路径。

### 运行时怎么接

`ChunkedWorld.mesh_for(key)` 改成两级：先查 `AssetLibrary`（读 manifest → 加载 GLB），
取不到才回退 `PropKit` 的程序化网格。管线没跑过时全部走回退，现有玩法不受影响。

```powershell
# 目视对比：管线产的 pine_0 与 PropKit 程序化的 pine_1 并排
& $env:GODOT_EXE --path game res://tests/capture_asset.tscn
# 输出：build/screenshots/asset_compare.png
```

## 提示

`world` 段在 v1 **不参与生成**（§3.4）：它逐项对应 `TerrainField` / `WorldChunk` 的现有常量，
作用是让管线产出的资产与运行时世界的地貌、比例对齐。改动 `world` 段的数值**不会**
改变运行时地形——那要等 v2 由 `TerrainField` 从 `scene_spec.json` 加载参数。
`--validate` 每次都会打印这条提示。
