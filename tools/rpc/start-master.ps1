<#
.SYNOPSIS
Start llama-server in router mode on the master. Models in the models folder load on demand across the RPC pool.

.DESCRIPTION
Only one model is loaded at a time (--models-max 1): the RPC server serves one client, so a second model on the same hosts would hang.
Defaults for all models (context size, GPU layers) and per-model settings live in models.ini.

.EXAMPLE
.\start-master.ps1 -Hosts 192.168.1.15:50052,192.168.1.44:50052 -ApiKey secret
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Hosts,
    [string]$ModelsDir = (Join-Path $env:USERPROFILE 'llama-models'),
    [string]$Preset,
    [string]$ApiKey,
    [int]$Port = 9931,
    [int]$StatsPort = 50053,
    [string]$BindAddress = '127.0.0.1',
    [switch]$NoAgent
)

$ErrorActionPreference = 'Stop'

if (-not $Preset) { $Preset = Join-Path $PSScriptRoot 'models.ini' }
$exe = Join-Path $PSScriptRoot '..\..\build-rpc-master\bin\llama-server.exe'
if (-not (Test-Path $exe)) { throw 'Not built yet. Run .\install-rpc.ps1 -Role Master -BuildUi first.' }

# the router aborts at startup when a host is down, and hangs when another client holds it
$rpcHosts = $Hosts | ForEach-Object { $_ -split ',' } | Where-Object { $_ }
foreach ($endpoint in $rpcHosts) {
    $name, $p = $endpoint -split ':'
    if (-not $p) { $p = 50052 }
    $client = New-Object Net.Sockets.TcpClient
    $ok = $false
    try { $ok = $client.ConnectAsync($name, [int]$p).Wait(3000) } catch { }
    $client.Dispose()
    if (-not $ok) { throw "RPC host ${name}:$p is not reachable. Start it with .\start-rpc-server.ps1 on that machine." }
}

New-Item -ItemType Directory -Force $ModelsDir | Out-Null

$serverArgs = @('--models-dir', $ModelsDir, '--models-max', 1, '--rpc', ($rpcHosts -join ','), '--metrics', '--host', $BindAddress, '--port', $Port)
if (Test-Path $Preset) { $serverArgs += '--models-preset', $Preset }
if ($ApiKey) { $serverArgs += '--api-key', $ApiKey }

# the /rpc/stats endpoint reads the agent port from this variable
$env:LLAMA_RPC_STATS_PORT = $StatsPort

$agent = $null
if (-not $NoAgent) {
    $agent = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'stats-agent.ps1'), '-Port', $StatsPort)
}

Write-Host "Models folder: $ModelsDir"
Write-Host "Web UI:        http://localhost:$Port/  (Models and RPC tabs)"
Write-Host "Claude Code:   ANTHROPIC_BASE_URL=http://localhost:$Port  ANTHROPIC_MODEL=<model id from the Models tab>"
try {
    & $exe @serverArgs
} finally {
    if ($agent -and -not $agent.HasExited) { Stop-Process -Id $agent.Id -Force }
}
