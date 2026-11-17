# Forest Adventure 技术设计文档

- 文档版本：V1.0
- 游戏引擎：Godot 4.x
- 资产工具：Blender
- 脚本语言：GDScript、Python
- 首发平台：Windows PC
- 架构目标：单机优先、数据驱动、场景可分块、工具链可重复执行

## 0. Godot 是否需要参与

需要。Godot Engine 是最终游戏的核心运行时，而不是可选工具。

| 能力 | Godot | Blender / AI 工具 |
|---|---|---|
| 第一人称控制、物理、碰撞 | 负责 | 仅提供模型与碰撞代理 |
| 开放世界分块与流式加载 | 负责 | 按规范导出场景块 |
| 战斗、敌人 AI、任务、背包 | 负责 | 不参与运行时逻辑 |
| 天气、昼夜、音频、UI | 负责 | 提供部分视觉资产 |
| 地形、植被、岩石、建筑资产 | 导入和渲染 | 负责生产 |
| 自然语言生成场景 | 不放入首版游戏运行时 | AI 规划，Blender 执行 |
| 存档与 Windows 发布 | 负责 | 不参与 |

推荐工作流是 Blender 生成 GLB 和清单，Godot 导入后由关卡设计师添加任务、敌人、交互与优化配置。

## 1. 技术目标

1. 建立稳定的第一人称探索游戏基础。
2. 支持由多个大型区域组成的开放世界、分块流式加载和性能优化。
3. 将人工设计的关键区域与程序化生成的自然环境结合。
4. 使用 AI 把自然语言转换为受约束的场景配置，而不是直接生成不可维护的大段 Blender 脚本。
5. 让 Blender 生成结果可重复、可验证并能稳定导入 Godot。
6. 保证核心游戏不依赖云端 AI 服务运行。

## 2. 系统架构

~~~text
Developer Prompt
      |
      v
AI Scene Planner
      |
      v
SceneSpec JSON ----> Schema Validator
      |                    |
      | valid              | errors
      v                    v
Blender Generator <--- Human Review
      |
      +--> forest.blend
      +--> forest.glb
      +--> preview.png
      +--> manifest.json
                |
                v
          Godot Import
                |
                v
 World Chunks + Gameplay + Navigation + Audio
~~~

运行时只包含 Godot 游戏。AI、Python 和 Blender 都属于开发期内容生产管线，不随正式游戏启动。

## 3. 推荐项目结构

~~~text
Forest-Adventure/
├── docs/
│   ├── README.md
│   ├── game-design.md
│   └── technical-design.md
├── game/
│   ├── project.godot
│   ├── autoload/
│   │   ├── game_state.gd
│   │   ├── save_manager.gd
│   │   ├── event_bus.gd
│   │   └── settings_manager.gd
│   ├── scenes/
│   │   ├── main/
│   │   ├── player/
│   │   ├── world/
│   │   ├── interactables/
│   │   └── ui/
│   ├── scripts/
│   │   ├── gameplay/
│   │   ├── world/
│   │   ├── interaction/
│   │   └── ai/
│   ├── resources/
│   │   ├── items/
│   │   ├── quests/
│   │   ├── weather/
│   │   └── audio/
│   ├── assets/
│   │   ├── generated/
│   │   ├── authored/
│   │   └── third_party/
│   └── tests/
├── tools/
│   └── forest_generator/
│       ├── agent/
│       │   ├── planner.py
│       │   ├── scene_parser.py
│       │   └── validator.py
│       ├── blender/
│       │   ├── terrain.py
│       │   ├── vegetation.py
│       │   ├── rocks.py
│       │   ├── river.py
│       │   ├── buildings.py
│       │   ├── materials.py
│       │   ├── exporter.py
│       │   └── renderer.py
│       ├── schemas/
│       │   └── scene_spec.schema.json
│       ├── presets/
│       ├── assets/
│       ├── output/
│       └── main.py
└── README.md
~~~

## 4. Godot 运行时设计

### 4.1 主场景

~~~text
Main
├── WorldManager
│   ├── ChunkLoader
│   ├── TimeOfDay
│   ├── WeatherController
│   └── WorldAudio
├── Player
├── QuestManager
├── SpawnManager
├── NavigationRegion3D
├── UI
└── DebugOverlay
~~~

职责边界：

| 模块 | 职责 |
|---|---|
| WorldManager | 世界状态和区域生命周期 |
| ChunkLoader | 根据玩家位置加载/卸载场景块 |
| Player | 移动、视角、状态与工具 |
| InteractionSystem | 射线检测、交互提示和行为调用 |
| Inventory | 物品槽位、堆叠和使用 |
| QuestManager | 任务状态与目标推进 |
| SaveManager | 持久化稳定 ID 对应的状态 |
| WeatherController | 天气状态和视觉参数 |
| AudioManager | 环境声层和空间音效 |

模块之间通过信号或 EventBus 传递领域事件，避免节点路径硬编码。

### 4.2 第一人称控制器

玩家根节点使用 CharacterBody3D：

~~~text
Player (CharacterBody3D)
├── CollisionShape3D
├── Head (Node3D)
│   ├── Camera3D
│   ├── InteractionRay (RayCast3D)
│   ├── Flashlight (SpotLight3D)
│   └── AudioListener3D
├── FootstepDetector (RayCast3D)
└── StateMachine
~~~

状态机至少包含：

- Grounded
- Sprinting
- Crouching
- Airborne
- Disabled

关键参数应存储为 Resource，而不是散落在脚本中：

~~~gdscript
class_name PlayerTuning
extends Resource

@export var walk_speed := 4.5
@export var sprint_speed := 7.0
@export var crouch_speed := 2.2
@export var acceleration := 14.0
@export var air_control := 0.25
@export var mouse_sensitivity := 0.002
@export var max_stamina := 100.0
~~~

#### 第一人称反馈

镜头与手持物分两层，互不影响：

| 层 | 负责 | 参数 |
|---|---|---|
| `Camera3D` 局部变换 | 走路上下起伏、左右侧倾、落地下沉 | `PlayerTuning.head_bob_amplitude / head_bob_roll_degrees / head_bob_landing_dip` |
| `Bow` 的 `BowViewModel` | 持弓摆动、呼吸起伏、转视角惯性、拉弦与双手 | `bow.gd` 的 `BOB_*`、`SWAY_*`、`MAX_DRAW` |

- 镜头只动局部位置和 roll，不碰 `Head` 的高度——蹲伏改的是 `Head`，两者叠加才是「人蹲下了，头还在动」。
- 第一人称模型不参与物理；弓按真实尺寸建模，手挂在弓身上与弓共用一套缩放，避免手掌和握把比例穿帮。
- 弓弦是两段运行时摆位的细柱，拉弦时折成 V 形，箭和右手跟着后移；落地与射箭各有一记短促下沉。

### 4.3 交互系统

所有可交互对象实现统一约定：

~~~gdscript
class_name Interactable
extends Node3D

func can_interact(actor: Node) -> bool:
    return true

func get_prompt(actor: Node) -> String:
    return "交互"

func interact(actor: Node) -> void:
    pass
~~~

交互流程：

1. Camera3D 中心发射射线。
2. 查找碰撞体或其父节点上的 Interactable。
3. 调用 can_interact。
4. UI 显示 get_prompt 返回的文本，并在前面标出当前交互键（从输入映射读取）。
5. 玩家按下交互键后调用 interact。
6. 交互对象发出领域事件，任务系统按事件推进。

HUD 的按键提示面板（`scripts/ui/hud.gd`）进入游戏时自动显示，9 秒后收起，
之后用 `toggle_help`（默认 H）开关；收起时右上角保留一个角标。
面板内容与交互提示的键位前缀都直接读 `InputMap`，改键后不需要同步改界面。

### 4.4 物品与任务数据

物品使用自定义 Resource：

~~~gdscript
class_name ItemDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var max_stack := 1
@export var tags: Array[StringName]
~~~

任务定义与运行状态分离：

- QuestDefinition：只读设计数据。
- QuestState：当前阶段、已完成目标和时间戳。
- QuestManager：监听事件并更新 QuestState。

事件示例：

~~~text
item.collected(item_id, amount)
location.entered(location_id)
object.inspected(object_id)
device.repaired(device_id)
camp.returned(camp_id)
~~~

### 4.5 保存系统

保存文件使用版本化 JSON 或二进制 Resource，必须包含：

- save_version
- current_scene
- player_transform
- player_state
- inventory
- quest_states
- world_flags
- changed_objects
- time_and_weather

每个需要持久化的对象拥有稳定 ID。不能使用运行时实例 ID 作为存档键。

写入流程采用临时文件 + 原子替换，并保留一个上一版本备份。加载时执行版本迁移，不因新增字段破坏旧存档。

## 5. 世界与性能

### 5.1 场景分块

首个 1 km × 1 km 区域切分为 16 × 16 个 64 m × 64 m 区块（`chunked_world.gd`）。

**高度真相唯一**：整片区域由一个全局高度函数 `TerrainField.height_at(x, z)` 描述。
区块网格只在给定世界坐标处采样这个函数，相邻区块在边界上取到同一组采样点，
因此接缝在结构上不可能裂开，不需要缝合网格或边界遮罩。区块外多采一圈顶点用于算法线，
相邻块的法线也由同一组点算出，光照接缝不会露。区块网格、碰撞、植被落地、玩家与敌人贴地
全部走这一个函数。

每个区块（`world_chunk.gd`）按需生成：

- 33 × 33 顶点的地形网格（2 m 一格，顶点色着色）。
- 凹多边形碰撞：只在玩家附近 2 圈内生成，且单独排队、分帧构建。
- 植被 MultiMesh：近处 2 圈是完整层（乔木 / 枯木 / 岩石 / 灌木 / 地被），3～5 圈只保留乔木。

**流式加载**以玩家所在区块为锚点：

| 距离 | 内容 |
|---:|---|
| 0～2 圈（≤128 m） | 地形 + 碰撞 + 完整植被 |
| 3～5 圈（≤320 m） | 地形 + 稀疏乔木 |
| 6～7 圈（≤448 m） | 仅地形（距离雾遮住边缘） |
| > 7 圈 | 卸载 |

加载队列按同心环排序，地形、植被、碰撞各有队列，每帧共享 3 ms 生成预算；
碰撞优先级最高，避免玩家跨区块时一帧内构建多块碰撞造成尖峰。

**确定性**：区块随机数由（世界种子, 区块坐标）派生，与加载顺序和方向无关，
同一区块重建后逐实例一致。植被候选点是全局格点，一格只归属一个区块；
密度由跨块共享的低频噪声调制，因此不会在区块边界突变。

**存档**：`GameState` 只记录世界种子与改动过的区块稀疏字典
（`chunked_world: {seed, modifications}`）。读档时同种子直接重建，不同种子整世界换图；
区块重建时自动应用 `no_vegetation` 等改动。

### 5.2 世界坐标与浮点精度

完整地图扩大后需要控制浮点精度。优先将世界拆成相对独立的区域坐标空间；若单一区域尺度超过精度预算，再实现浮动原点。存档使用“区域 ID + 局部坐标”，不直接依赖超大绝对坐标。

### 5.3 植被渲染

- 重复树木、草和小型岩石使用 MultiMeshInstance3D。
- 树木至少准备 2～3 级 LOD。
- 远距离树木使用简化网格或 billboard。
- 对密集草地设置可见距离和淡出。
- 碰撞只保留玩家可能接触的树干与关键岩石。
- 阴影距离独立于几何可见距离设置。

### 5.4 目标性能

垂直切片的建议基准：

| 指标 | 目标 |
|---|---|
| 分辨率 | 1920 × 1080 |
| 帧率 | 推荐配置稳定 60 FPS |
| 最低帧率 | 最低配置不低于 30 FPS |
| 初次加载 | 不超过 15 秒 |
| 区块切换卡顿 | 主线程尖峰低于 16 ms 为目标 |
| 显存 | 通过纹理预算控制在目标显卡范围内 |

性能基准需要在确定最低硬件配置后固化，不能只在开发机测试。

当前实测（开发机，1920 × 1080，Forward+，分块世界）：

| 场景 | 结果 |
|---|---|
| 225 个区块全加载（半径 7 圈） | 稳定 60 FPS |
| 流式压力测试：瞬移 23 m / 8 帧穿越全图 | 平均帧 7.6 ms，最差帧 14.6 ms |
| 同时存在的区块数 | 上限 225，与玩家走多远无关 |
| 单区块生成 | 地形 / 植被 / 碰撞各排队，共享每帧 3 ms 预算 |

## 6. AI → Blender 内容生产管线

### 6.1 设计原则

AI 只负责把设计意图转换为受约束的 SceneSpec。具体几何生成由版本受控的 Python 模块完成。

禁止让模型在生产流程中直接执行任意 Python。所有参数先通过 JSON Schema 校验，再映射到允许的生成函数。

### 6.2 SceneSpec

~~~json
{
  "schema_version": "1.0",
  "seed": 41721,
  "scene": {
    "name": "PineValley",
    "size_m": [500, 500],
    "style": "realistic",
    "season": "late_summer"
  },
  "terrain": {
    "max_height_m": 80,
    "roughness": 0.6,
    "mountain_count": 8
  },
  "river": {
    "enabled": true,
    "width_m": 8,
    "path": "curved"
  },
  "vegetation": {
    "pine_count": 300,
    "rock_count": 100,
    "density": 0.7,
    "exclusion_zones": ["camp", "main_path"]
  },
  "landmarks": [
    {"id": "ranger_station", "type": "cabin", "position": [120, -60, 18]}
  ],
  "lighting": {
    "preset": "afternoon_overcast"
  },
  "export": {
    "format": "glb",
    "chunk_size_m": 50
  }
}
~~~

所有随机过程必须接收 seed，保证相同输入得到可重复结果。

### 6.3 生成步骤

1. 解析自然语言并生成 SceneSpec 草案。
2. 使用 Schema 校验类型、范围和必填项。
3. 执行设计规则校验，例如道路坡度、地标间距和资源预算。
4. 人工查看配置差异并确认。
5. Blender 后台模式生成地形。
6. 根据坡度、高度、湿度和排除区分布植被。
7. 生成河流、岩石、道路与建筑占位。
8. 生成碰撞代理、LOD 和命名元数据。
9. 渲染俯视图与关键视角预览。
10. 导出分块 GLB 和 manifest.json。
11. Godot 导入检查器验证坐标、材质、碰撞和资源预算。

命令形式：

~~~bash
blender --background --python tools/forest_generator/main.py -- --spec presets/pine_valley.json --output output/pine_valley
~~~

### 6.4 局部重生成

生成器必须按稳定 ID 管理对象，支持只更新指定层：

- terrain
- river
- vegetation
- rocks
- landmarks
- lighting
- export

例如“增加松树”只重建 vegetation 层，不应删除人工调整的守林站或任务对象。

生成资产与人工资产分目录保存。生成器不得覆盖 authored 目录。

### 6.5 导出约定

- 坐标和单位统一：1 Godot 单位 = 1 米。
- 应用对象变换后再导出。
- 网格名称采用 type_variant_lod 格式。
- 材质使用可预测的命名和 PBR 贴图槽。
- 任务对象只导出占位点和稳定 ID，逻辑在 Godot 中绑定。
- manifest.json 记录生成器版本、seed、源配置、文件校验值与资源统计。

## 7. Blender 模块接口

生成模块应是确定性函数，避免共享隐式全局状态：

~~~python
def create_terrain(spec, context) -> GeneratedLayer:
    ...

def create_vegetation(spec, terrain, context) -> GeneratedLayer:
    ...

def create_river(spec, terrain, context) -> GeneratedLayer:
    ...

def export_chunks(scene, export_spec, context) -> ExportManifest:
    ...
~~~

context 提供随机数生成器、日志器、资产目录和命名服务。模块不直接读取用户自然语言。

## 8. 错误处理与可观测性

每次生成任务创建独立 job_id，并输出结构化日志：

- 解析耗时。
- Schema 错误。
- 各生成阶段耗时。
- 顶点、三角面、材质和实例数量。
- Blender 警告。
- 导出文件及校验值。
- 失败阶段和可执行的错误建议。

失败时保留 SceneSpec、日志和最后一张预览图，便于复现。

## 9. 测试策略

### 9.1 Godot

- 单元测试：物品、任务状态、存档迁移和数值计算。
- 场景测试：交互对象、Chunk 生命周期和任务完整流程。
- 冒烟测试：启动、开始新游戏、保存、加载和完成垂直切片。
- 性能测试：固定路线自动行走并采集帧时间与内存。
- 人工测试：导航可读性、晕动症设置、音频提示和任务理解。

### 9.2 生成器

- Schema 测试：非法范围和缺失字段必须失败。
- 确定性测试：同版本、同 seed、同输入产生相同 manifest。
- 几何检查：NaN、退化面、错误法线和越界对象。
- 预算检查：三角面、材质、纹理和实例数量。
- 导入测试：批量导入 Godot 后不得出现缺失资源。
- 快照测试：保存低分辨率预览用于发现明显视觉回归。

## 10. 安全边界

AI 输出视为不可信输入：

- 只接受符合 Schema 的 JSON。
- 不执行 AI 返回的 shell 命令或任意 Python。
- 文件输出限制在任务专属目录。
- 资产路径解析后必须仍位于允许的资产根目录。
- 限制对象数量、纹理尺寸、地形分辨率和生成时间。
- Blender 进程使用超时和失败退出码。
- 外部资产必须记录许可和来源。

## 11. 实施阶段

### Phase 1：游戏基础

- 初始化 Godot 工程。
- 第一人称控制和设置菜单。
- 统一交互接口。
- 物品、背包、任务和保存框架。
- 使用手工灰盒完成垂直切片流程。

### Phase 2：森林生成器

- 定义 SceneSpec 与 Schema。
- 实现地形、树木、岩石和河流模块。
- 实现 GLB、预览图和 manifest 导出。
- 建立 Godot 自动导入检查。

### Phase 3：内容整合

- 将灰盒替换为生成场景。
- 人工制作营地、守林站和任务路径。
- 完成昼夜、天气、音频和环境谜题。
- 加入 LOD、分块和性能预算。

### Phase 4：打磨与发布

- 完整可玩性测试。
- 优化导航、节奏和视觉可读性。
- 修复存档与阻断性问题。
- 完成 Windows 构建、设置和发布材料。

## 12. 首个开发里程碑

第一个里程碑不是直接生成完整森林，而是完成一条灰盒可玩链路：

> 启动游戏 → 从营地出发 → 穿过树林 → 拾取保险丝 → 到达守林站 → 修复设备 → 保存并退出。

这条链路稳定后，再接入 AI → Blender 场景生产管线。这样可以分别验证“游戏是否好玩”和“内容是否高效生成”，降低两条高风险技术线互相阻塞的概率。
