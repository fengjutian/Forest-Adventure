<#
.SYNOPSIS
    启动 Forest Adventure。

.DESCRIPTION
    自动定位 Godot，必要时先执行一次资源导入（生成 .godot 缓存与全局类注册表），
    然后启动游戏。新克隆的仓库必须先导入，否则以 class_name 声明的脚本无法解析。

.PARAMETER GodotExe
    Godot 可执行文件路径。默认取 $env:GODOT_EXE，其次在常见安装位置查找。

.PARAMETER Editor
    用 Godot 编辑器打开工程，而不是直接运行游戏。

.EXAMPLE
    .\tools\run.ps1
    .\tools\run.ps1 -Editor
#>
[CmdletBinding()]
param(
    [string]$GodotExe = $env:GODOT_EXE,
    [switch]$Editor
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$GameDir = Join-Path $RepoRoot 'game'

function Resolve-Godot {
    param([string]$Hint)

    $candidate = $null
    if ($Hint -and (Test-Path $Hint)) {
        $candidate = (Resolve-Path $Hint).Path
    } else {
        $onPath = Get-Command godot -ErrorAction SilentlyContinue
        if ($onPath) {
            $candidate = $onPath.Source
        } else {
            $known = @(
                'C:\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe',
                'C:\Program Files\Godot\Godot_v4.6-stable_win64.exe',
                'D:\Program Files\Godot\Godot_v4.6-stable_win64.exe'
            )
            foreach ($path in $known) {
                if (Test-Path $path) { $candidate = $path; break }
            }
            if (-not $candidate) {
                $found = Get-ChildItem 'C:\', 'D:\' -Filter 'Godot*_win64.exe' -Depth 2 -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer } | Select-Object -First 1
                if ($found) { $candidate = $found.FullName }
            }
        }
    }

    if (-not $candidate) {
        throw '未找到 Godot。请用 -GodotExe 指定路径，或设置 $env:GODOT_EXE。'
    }

    # 控制台变体在脚本里能可靠传回退出码
    $console = Join-Path (Split-Path -Parent $candidate) ((Split-Path -Leaf $candidate) -replace '_win64\.exe$', '_win64_console.exe')
    if (Test-Path $console) { return $console }
    return $candidate
}

$Godot = Resolve-Godot -Hint $GodotExe
Write-Host "Godot: $Godot" -ForegroundColor DarkGray

if ($Editor) {
    Write-Host '==> 用编辑器打开工程' -ForegroundColor Cyan
    & $Godot --editor --path $GameDir
    exit $LASTEXITCODE
}

# 首次运行（或 .godot 缺失）时先导入资源
$classCache = Join-Path $GameDir '.godot\global_script_class_cache.cfg'
if (-not (Test-Path $classCache)) {
    Write-Host '==> 首次运行：正在导入资源（生成全局类缓存）' -ForegroundColor Cyan
    & $Godot --headless --path $GameDir --import
    if ($LASTEXITCODE -ne 0) {
        throw "资源导入失败（退出码 $LASTEXITCODE）。"
    }
}

Write-Host '==> 启动游戏（Esc 释放鼠标，点击画面继续）' -ForegroundColor Green
& $Godot --path $GameDir
exit $LASTEXITCODE
