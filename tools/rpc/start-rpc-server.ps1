<#
.SYNOPSIS
Start the ggml-rpc-server built by install-rpc.ps1 -Role Host, plus the stats agent for the llama-server RPC tab.
#>
[CmdletBinding()]
param(
    [int]$Port = 50052,
    [int]$StatsPort = 50053,
    [string]$BindAddress = '0.0.0.0',
    [string]$Device,
    [switch]$Cache,
    [switch]$NoAgent
)

$ErrorActionPreference = 'Stop'

$exe = Join-Path $PSScriptRoot '..\..\build-rpc-host\bin\ggml-rpc-server.exe'
if (-not (Test-Path $exe)) { throw "Not built yet. Run .\install-rpc.ps1 -Role Host first." }

$serverArgs = @('-H', $BindAddress, '-p', $Port)
if ($Device) { $serverArgs += @('-d', $Device) }
if ($Cache) { $serverArgs += '-c' }

$agent = $null
if (-not $NoAgent) {
    $agent = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'stats-agent.ps1'),
        '-Port', $StatsPort, '-RpcPort', $Port)
}
try {
    & $exe @serverArgs
} finally {
    if ($agent -and -not $agent.HasExited) { Stop-Process -Id $agent.Id -Force }
}
