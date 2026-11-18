"""森林生成管线的 Python 工具链库。

各模块与 docs/forest-pipeline-spec.md 的对应关系：

- ``seed``            §5.2 种子派生（FNV-1a 32 位）
- ``asset_keys``      §4.1 资产键表（管线与运行时的接缝）
- ``jsonschema_mini`` §3.2 / §3.3 JSON Schema 子集校验器
- ``spec``            §3.2 / §3.3 SceneSpec 两层校验（schema 层 + 语义层）
- ``budget``          §3.3 预算检查（超预算即失败，不静默截断）
- ``manifest``        §7 manifest 读写与统计

运行期只依赖 Python 3.12 标准库，不引入任何第三方包。
"""

from __future__ import annotations
