# 一键发布平板包：打 release → 拷 dsh-agent.apk → 写 version.json
# 用法：.\tool\release_apk.ps1 -Changelog "更新说明"
# 必须用 pwsh 7 运行（powershell 5.1 会把中文解码坏）：pwsh -File .\tool\release_apk.ps1
# 注意：先在 pubspec.yaml 里把 version 升上去（versionCode 必须递增，App 才会认出新版）
param(
  [string]$Changelog = "常规更新",
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$flutter = 'D:\software\flutter_windows_3.47.2-stable\bin\flutter.bat'
$outDir = Join-Path $root 'build\app\outputs\flutter-apk'
$apk = Join-Path $outDir 'app-release.apk'
$served = Join-Path $outDir 'dsh-agent.apk'
$versionFile = Join-Path $outDir 'version.json'

$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'

Write-Output "== analyze =="
& $flutter analyze 2>&1 | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { throw "analyze 未通过" }

Write-Output "== build apk --release =="
& $flutter build apk --release 2>&1 | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { throw "build 失败" }

Copy-Item $apk -Destination $served -Force

# 从 pubspec 读 version: x.y.z+N
$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch 'version:\s*([0-9.]+)\+([0-9]+)') { throw "pubspec version 解析失败" }
$versionName, $versionCode = $Matches[1], [int]$Matches[2]
$size = (Get-Item $served).Length

$meta = [ordered]@{
  versionCode = $versionCode
  versionName = $versionName
  size        = $size
  changelog   = $Changelog
  force       = [bool]$Force
}
$json = $meta | ConvertTo-Json
[System.IO.File]::WriteAllText($versionFile, $json, [System.Text.UTF8Encoding]::new($false))

Write-Output "== 发布完成 =="
Write-Output "版本: $versionName ($versionCode)，大小: $([math]::Round($size/1MB,1)) MB"
Write-Output "APK: $served"
Write-Output "版本文件: $versionFile"
Write-Output "平板若装的是旧版，下次启动会自动弹更新；也可进 设置→应用更新 手动检查"
