# AI、Blender 与 Godot 内容管线

## 1. 管线目标

将“生成一片有山脊、溪流、松林和守林站的区域”转换为可审查、可重复、可导入 Godot 的资产，同时保留关卡设计师对任务路径和地标的控制。

AI 不直接制作最终游戏逻辑，也不执行任意代码。

## 2. 内容分层

| 层 | 主要来源 | 是否允许重新生成 |
|---|---|---|
| 基础地形 | Blender 程序化生成 | 是 |
| 自然植被与岩石 | Blender 程序化生成 | 是 |
| 道路、河流 | 程序化生成 + 人工修正 | 分层重生成 |
| 主地标与建筑 | 人工资产 | 不自动覆盖 |
| 任务对象与敌人 | Godot 场景 | 不由 Blender 修改 |
| 灯光、天气与音频 | Godot | 不由 Blender 修改 |

## 3. 标准流程

~~~text
设计需求
  → AI 生成 SceneSpec
  → JSON Schema 校验
  → 规则与预算校验
  → 人工确认差异
  → Blender 后台生成
  → 自动几何检查
  → 渲染预览
  → 分块导出 GLB + manifest
  → Godot 导入检查
  → 关卡设计与游戏逻辑绑定
~~~

## 4. 资产规范

### 4.1 坐标与比例

- 使用米制单位。
- 1 Blender 米 = 1 Godot 单位。
- 统一轴向由导出预设处理，不允许单个资产自行修正。
- 原点放在合理旋转或放置位置。
- 导出前应用缩放。
- 静态模型不得包含负缩放。

### 4.2 命名

~~~text
环境资产：env_<category>_<name>_<variant>
LOD：      env_tree_pine_a_lod0
碰撞：    env_tree_pine_a_col
材质：    mat_<surface>_<variant>
纹理：    tex_<asset>_<channel>_<resolution>
地标：    lm_<region>_<name>
任务点：  qp_<quest>_<purpose>
~~~

### 4.3 PBR 贴图

标准通道：

- Base Color
- Normal
- Roughness
- Metallic（需要时）
- Ambient Occlusion
- Emission（需要时）

限制独立材质数量，优先共享材质、图集或纹理数组。纹理尺寸按画面占比选择，不默认使用 4K。

### 4.4 LOD 与碰撞

- 大型地标：LOD0～LOD3。
- 普通树木与岩石：LOD0～LOD2。
- 小型植被：LOD0 + billboard 或距离剔除。
- 碰撞使用简化形状，不直接使用高模三角网格。
- 草、灌木和小石头默认无碰撞。

## 5. Chunk 输出

每个 Chunk 输出：

~~~text
region_pine_valley/
├── chunks/
│   ├── chunk_00_00.glb
│   ├── chunk_00_01.glb
│   └── ...
├── proxies/
├── previews/
├── nav_hints/
├── manifest.json
└── scene_spec.json
~~~

manifest 至少记录：

- schema_version
- generator_version
- seed
- region_id
- chunk 坐标和边界
- 资产列表
- 三角面与实例统计
- 材质与纹理统计
- 稳定对象 ID
- 文件校验值
- 生成时间与警告

## 6. 关卡设计保护

人工修改不能直接发生在生成文件内部。推荐在 Godot 中使用组合场景：

~~~text
ChunkRoot
├── GeneratedEnvironment
├── AuthoredLandmarks
├── GameplayObjects
├── Enemies
├── AudioZones
└── NavigationLinks
~~~

重新生成时只替换 GeneratedEnvironment。其他节点由稳定锚点 ID 重新绑定。

## 7. AI 输入与输出

AI 输入包含：

- 区域主题。
- 尺寸和高度范围。
- 地标列表。
- 主路径与禁布区。
- 植被和岩石预算。
- 性能档位。
- 天气与时间预设。

AI 输出只允许 SceneSpec JSON。解析器拒绝额外脚本、命令或未知字段。

示例修改：

~~~json
{
  "operation": "update_layer",
  "region_id": "pine_valley",
  "layer": "vegetation",
  "changes": {
    "pine_count": 420,
    "density": 0.78
  }
}
~~~

## 8. 自动检查

生成完成后必须检查：

- 是否存在 NaN、退化面和非流形关键网格。
- 法线与切线是否有效。
- 对象是否超出 Chunk 边界。
- 地标与主路径是否被植被阻挡。
- 河流是否出现明显反坡。
- 三角面、实例、材质和纹理是否超预算。
- 所有引用资源是否存在。
- Godot 能否无错误导入。

失败的任务不得覆盖上一版有效输出。

## 9. 版本管理

- 生成规则、SceneSpec 和 manifest 进入 Git。
- 大型二进制资产使用 Git LFS。
- 临时渲染、缓存和 Blender 自动保存不进入 Git。
- 生成器升级导致输出变化时必须提升 generator_version。
- 发布构建锁定生成器版本、seed 和资产校验值。

## 10. 首个管线里程碑

输入一个固定 SceneSpec，自动生成：

- 1 km × 1 km 灰度地形。
- 一条溪流。
- 三类松树实例。
- 两类岩石实例。
- 一个守林站占位点。
- 64 m 或 128 m Chunk。
- 俯视图和两个玩家视角预览。
- Godot 可导入的 GLB 与 manifest。

首个里程碑先不接大语言模型。固定配置稳定后，再加入自然语言到 SceneSpec 的转换。
