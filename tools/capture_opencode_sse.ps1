param(
  [Parameter(Mandatory)][string]$Out,
  [string]$BaseUrl = 'http://127.0.0.1:4096',
  # opencode 服务密码（OPENCODE_SERVER_PASSWORD）或配对令牌；必填，不写死
  [Parameter(Mandatory)][string]$Password,
  [int]$Seconds = 30
)
# 抓取 opencode /api/event 的 SSE 原始流到文件，带 Basic 鉴权
$ErrorActionPreference = 'Stop'
$client = [System.Net.Http.HttpClient]::new()
$client.DefaultRequestHeaders.Authorization =
  [System.Net.Http.Headers.AuthenticationHeaderValue]::new(
    'Basic',
    [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("opencode:$Password")))
$resp = $client.GetAsync("$BaseUrl/api/event",
  [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
$stream = $resp.Content.ReadAsStreamAsync().Result
$reader = [System.IO.StreamReader]::new($stream)
$sw = [System.IO.StreamWriter]::new($Out)
$sw.AutoFlush = $true
$sw.WriteLine("# status=$($resp.StatusCode) at $(Get-Date -Format o)")
$deadline = (Get-Date).AddSeconds($Seconds)
$pending = $null
while ((Get-Date) -lt $deadline) {
  # 同一时刻只允许一个未完成的 ReadLineAsync，否则流会报 in use
  if ($null -eq $pending) {
    $pending = $reader.ReadLineAsync()
    continue
  }
  if (-not $pending.Wait(500)) { continue }
  $line = $null
  try { $line = $pending.Result } catch { $sw.WriteLine('# read-error: ' + $_.Exception.Message); break }
  $pending = $null
  if ($null -eq $line) { $sw.WriteLine('# eof'); break }
  $sw.WriteLine($line)
}
$sw.Dispose(); $reader.Dispose(); $stream.Dispose(); $client.Dispose()
'CAPTURE_DONE'
