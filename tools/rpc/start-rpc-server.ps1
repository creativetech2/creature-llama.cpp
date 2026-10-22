<#
.SYNOPSIS
Start the ggml-rpc-server built by install-rpc.ps1 -Role Host.
#>
[CmdletBinding()]
param(
    [int]$Port = 50052,
    [string]$BindAddress = '0.0.0.0',
    [string]$Device,
    [switch]$Cache
)

$ErrorActionPreference = 'Stop'

$exe = Join-Path $PSScriptRoot '..\..\build-rpc-host\bin\ggml-rpc-server.exe'
if (-not (Test-Path $exe)) { throw "Not built yet. Run .\install-rpc.ps1 -Role Host first." }

$serverArgs = @('-H', $BindAddress, '-p', $Port)
if ($Device) { $serverArgs += @('-d', $Device) }
if ($Cache) { $serverArgs += '-c' }
& $exe @serverArgs
