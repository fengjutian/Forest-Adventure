"""Blender 侧的森林资产生成工具，对应 docs/forest-pipeline-spec.md §4、§6。

模块职责：

- ``vegetation``：按 Python 侧派生的参数建网格（纯函数）
- ``exporter``：导出 GLB（顶点色即反照率，不带材质）
- ``build_asset``：命令行入口，供 ``lib/build.py`` 调用

这些模块只能在 **Blender 的 Python** 里跑（依赖 ``bpy``），
不能在普通 Python 里直接 import。
"""
