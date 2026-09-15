# 把 DSH 最新启动令牌发布到 8099 下载服务，供平板"自动授权"拉取
# 用法：pwsh -File .\publish_launch_token.ps1
# 原理：从 dsh-autostart.log 里取最后一次出现的 ?token= 启动令牌 → 写 launch-token.json
# 安全：令牌只在 DSH 进程生命周期内有效；授权换到的是 30 天 browser cookie
# 注意：每次 DSH 重启后需重新运行本脚本；不用时删除 launch-token.json 即可
param(
  [string]$LogPath = 'D:\software\deepseek-harness\dsh-autostart.log',
  [string]$LanHost = '192.168.10.171',
  [int]$DshPort = 3080,
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('INFO', 'WARN', 'ERROR')]
    [string]$Level = 'INFO'
  )
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$ts] [$Level] $Message"
  Write-Output $line
  $logFile = Join-Path $PSScriptRoot 'publish_launch_token.log'
  Add-Content -Path $logFile -Value $line -Encoding UTF8
}

try {
  Write-Log '开始发布启动令牌'
  Write-Log "参数: LogPath='$LogPath'; LanHost='$LanHost'; DshPort=$DshPort; OutDir='$OutDir'"

  if (-not (Test-Path $LogPath)) {
    throw "找不到日志文件: $LogPath"
  }

  $matches = Select-String -Path $LogPath -Pattern '[?&]token=([A-Za-z0-9_-]+)' -AllMatches
  if (-not $matches) { throw "日志里没有找到启动令牌（?token=...）" }
  $last = $matches | Select-Object -Last 1
  $token = $last.Matches[-1].Groups[1].Value
  Write-Log "已提取启动令牌（长度 $($token.Length)）"

  if ($OutDir) {
    $outDir = $OutDir
  } else {
    $default = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk'
    if (-not (Test-Path $default)) {
      New-Item -ItemType Directory -Path $default -Force | Out-Null
      Write-Log "已自动创建默认输出目录: $default"
      Write-Log '请确保 8099 下载服务托管该目录，否则平板无法拉取 launch-token.json'
    }
    $outDir = (Resolve-Path $default).Path
  }
  if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    Write-Log "已创建输出目录: $outDir"
  }
  $tokenFile = Join-Path $outDir 'launch-token.json'

  $meta = [ordered]@{
    token     = $token
    url       = "http://$LanHost`:$DshPort/?token=$token"
    updatedAt = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
  }
  $json = $meta | ConvertTo-Json
  [System.IO.File]::WriteAllText($tokenFile, $json, [System.Text.UTF8Encoding]::new($false))
  Write-Log "已写入: $tokenFile"

  Write-Log "已发布启动令牌: http://$LanHost`:8099/launch-token.json"
  Write-Log '平板点「自动授权」即可换取 30 天 cookie'
  Write-Log '完成'
} catch {
  $err = $_.Exception.Message
  Write-Log "失败: $err" 'ERROR'
  Write-Log "当前路径: $(Get-Location)" 'ERROR'
  Write-Log "脚本路径: $PSScriptRoot" 'ERROR'
  Write-Log "日志路径: $LogPath (存在: $(Test-Path $LogPath))" 'ERROR'
  if ($outDir) {
    Write-Log "输出目录: $outDir (存在: $(Test-Path $outDir))" 'ERROR'
  }
  exit 1
}
