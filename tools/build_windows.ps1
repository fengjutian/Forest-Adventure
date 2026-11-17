<#
.SYNOPSIS
    构建 Forest Adventure 的 Windows 发布版本。

.DESCRIPTION
    流程：导入资源 → 运行冒烟测试 → 导出可执行文件。
    首次在新克隆上运行时需要先执行导入步骤，Godot 才会生成全局类缓存，
    否则以 class_name 声明的脚本无法被解析。

.PARAMETER GodotExe
    Godot 可执行文件路径。默认取 $env:GODOT_EXE，其次在常见安装位置查找。

.PARAMETER OutputDir
    导出目录，默认仓库根目录下的 build/。

.PARAMETER SkipTest
    跳过冒烟测试（不推荐）。

.PARAMETER SkipExport
    只做导入与测试，不执行导出。用于没有安装导出模板的机器或 CI。

.PARAMETER DebugBuild
    导出调试版本而非发布版本。

.EXAMPLE
    .\tools\build_windows.ps1
    .\tools\build_windows.ps1 -GodotExe 'D:\Godot\Godot_v4.6-stable_win64.exe'
    .\tools\build_windows.ps1 -SkipExport
#>
[CmdletBinding()]
param(
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$OutputDir = '',
    [switch]$SkipTest,
    [switch]$SkipExport,
    [switch]$DebugBuild
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$GameDir = Join-Path $RepoRoot 'game'
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot 'build'
}

function Resolve-Godot {
    param([string]$Hint)

    if ($Hint -and (Test-Path $Hint)) { return (ConvertTo-PreferredVariant (Resolve-Path $Hint).Path) }

    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { return (ConvertTo-PreferredVariant $onPath.Source) }

    $candidates = @(
        'C:\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe',
        'C:\Program Files\Godot\Godot_v4.6-stable_win64.exe',
        'D:\Program Files\Godot\Godot_v4.6-stable_win64.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return (ConvertTo-PreferredVariant $candidate) }
    }

    $found = Get-ChildItem 'C:\', 'D:\' -Filter 'Godot*_win64.exe' -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } | Select-Object -First 1
    if ($found) { return (ConvertTo-PreferredVariant $found.FullName) }

    throw '未找到 Godot 可执行文件。请用 -GodotExe 指定路径，或设置 $env:GODOT_EXE。'
}

# Windows 上 GUI 子系统的 Godot 不会可靠地传回退出码，优先使用 console 变体。
function ConvertTo-PreferredVariant {
    param([string]$Path)

    $consoleVariant = Join-Path (Split-Path -Parent $Path) ((Split-Path -Leaf $Path) -replace '_win64\.exe$', '_win64_console.exe')
    if (Test-Path $consoleVariant) { return $consoleVariant }
    return $Path
}

function Invoke-Godot {
    param([string[]]$GodotArgs, [string]$Label)

    Write-Host "==> $Label" -ForegroundColor Cyan
    & $Godot @GodotArgs
    $code = $LASTEXITCODE
    if ($null -eq $code) {
        # GUI 子系统二进制可能不设置退出码，此时以进程是否启动成功为准
        $code = 0
    }
    if ($code -ne 0) {
        throw "$Label 失败（退出码 $code）。"
    }
}

$Godot = Resolve-Godot -Hint $GodotExe
Write-Host "Godot: $Godot" -ForegroundColor DarkGray

# 1. 导入资源，生成 .godot/ 缓存与全局类注册表
Invoke-Godot -GodotArgs @('--headless', '--path', $GameDir, '--import') -Label '导入资源'

# 2. 冒烟测试
if (-not $SkipTest) {
    $testOutput = & $Godot --headless --path $GameDir 'res://tests/test_smoke.tscn' 2>&1 | Out-String
    $testOutput = $testOutput -replace "`e\[[0-9;]*m", ''
    $pass = ([regex]::Matches($testOutput, 'PASS')).Count
    $fail = ([regex]::Matches($testOutput, 'FAIL')).Count
    Write-Host $testOutput
    if ($fail -gt 0) {
        throw "冒烟测试存在 $fail 项失败，终止构建。"
    }
    Write-Host "冒烟测试通过（$pass 项）" -ForegroundColor Green
}

# 3. 导出
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$exportPath = Join-Path $OutputDir 'ForestAdventure.exe'

if ($SkipExport) {
    Write-Host ''
    Write-Host '已跳过导出（-SkipExport）。导入与测试均已通过。' -ForegroundColor Yellow
    exit 0
}

# 导出模板是独立下载的，前置检查可以给出比 Godot 更清晰的提示
$templateDir = Join-Path $env:APPDATA 'Godot\export_templates\4.6.stable'
$requiredTemplates = @('windows_release_x86_64.exe')
if ($DebugBuild) { $requiredTemplates = @('windows_debug_x86_64.exe') }
$missing = @()
foreach ($template in $requiredTemplates) {
    if (-not (Test-Path (Join-Path $templateDir $template))) { $missing += $template }
}
if ($missing.Count -gt 0) {
    throw "缺少 Godot 导出模板：$($missing -join ', ')`n" +
          "请用 Godot 管理器 → 编辑器 → 管理导出模板，安装 4.6 stable 版本。`n" +
          "模板目录：$templateDir`n" +
          "若只需要验证工程可用性，可用 -SkipExport 跳过导出。"
}

$mode = 'Windows Desktop'
Write-Host "==> 导出 $mode → $exportPath" -ForegroundColor Cyan
& $Godot --headless --path $GameDir --export-release $mode $exportPath
if ($LASTEXITCODE -ne 0) {
    throw "导出失败（退出码 $LASTEXITCODE）。"
}

if (-not (Test-Path $exportPath)) {
    throw "导出未生成预期文件：$exportPath"
}

$exe = Get-Item $exportPath
Write-Host ""
Write-Host "构建完成：$($exe.FullName)  ($([math]::Round($exe.Length / 1MB, 1)) MB)" -ForegroundColor Green
