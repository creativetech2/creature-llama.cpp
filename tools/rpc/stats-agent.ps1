<#
.SYNOPSIS
Serve GPU, CPU, memory and network stats of this machine as JSON (GET /stats) for the llama-server RPC tab.

.DESCRIPTION
Run on every RPC host and on the master. Read-only, no authentication: allow the port from the local subnet only.
#>
[CmdletBinding()]
param(
    [int]$Port = 50053,
    [int]$RpcPort = 50052
)

$ErrorActionPreference = 'Stop'

# sampling is slow (CIM, nvidia-smi), so it runs in its own runspace and requests read the latest result
$collector = {
    param($shared, $rpcPort)

    $gpuFields = 'index,name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.sm'
    $state = @{ lastNet = $null }

    function ConvertTo-Number($text) {
        $value = 0.0
        if ([double]::TryParse($text.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { return $value }
        return $null
    }

    function Get-Gpus {
        if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return @() }
        $lines = & nvidia-smi "--query-gpu=$gpuFields" --format=csv,noheader,nounits 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        foreach ($line in $lines) {
            $f = $line -split ','
            if ($f.Count -lt 10) { continue }
            [ordered]@{
                index         = [int]$f[0]
                name          = $f[1].Trim()
                util_gpu      = ConvertTo-Number $f[2]
                util_mem      = ConvertTo-Number $f[3]
                mem_used_mib  = ConvertTo-Number $f[4]
                mem_total_mib = ConvertTo-Number $f[5]
                temp_c        = ConvertTo-Number $f[6]
                power_w       = ConvertTo-Number $f[7]
                power_limit_w = ConvertTo-Number $f[8]
                sm_clock_mhz  = ConvertTo-Number $f[9]
            }
        }
    }

    function Get-Net {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
        if (-not $adapters) { return $null }
        $stats = @(Get-NetAdapterStatistics -Name ($adapters | ForEach-Object Name))
        $now = [datetime]::UtcNow
        $rx = ($stats | Measure-Object ReceivedBytes -Sum).Sum
        $tx = ($stats | Measure-Object SentBytes -Sum).Sum
        $rxMbps = 0.0
        $txMbps = 0.0
        $last = $state.lastNet
        if ($last) {
            $dt = ($now - $last.Time).TotalSeconds
            if ($dt -gt 0) {
                $rxMbps = [math]::Max(0, ($rx - $last.Rx) * 8 / 1e6 / $dt)
                $txMbps = [math]::Max(0, ($tx - $last.Tx) * 8 / 1e6 / $dt)
            }
        }
        $state.lastNet = @{ Time = $now; Rx = $rx; Tx = $tx }
        [ordered]@{
            rx_mbps   = [math]::Round($rxMbps, 1)
            tx_mbps   = [math]::Round($txMbps, 1)
            link_mbps = ($adapters | Measure-Object ReceiveLinkSpeed -Maximum).Maximum / 1e6
        }
    }

    while ($true) {
        try {
            $os = Get-CimInstance Win32_OperatingSystem
            $cpu = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
            $clients = @(Get-NetTCPConnection -LocalPort $rpcPort -State Established -ErrorAction SilentlyContinue | ForEach-Object RemoteAddress)
            $shared.json = [ordered]@{
                host          = $env:COMPUTERNAME
                time          = [datetime]::UtcNow.ToString('o')
                gpus          = @(Get-Gpus)
                cpu_pct       = $cpu
                ram_used_mib  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024)
                ram_total_mib = [math]::Round($os.TotalVisibleMemorySize / 1024)
                net           = Get-Net
                rpc           = [ordered]@{
                    running = [bool](Get-Process ggml-rpc-server -ErrorAction SilentlyContinue)
                    port    = $rpcPort
                    clients = $clients
                }
            } | ConvertTo-Json -Depth 6 -Compress
        } catch {
            $shared.error = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 500
    }
}

function Send-Response($stream, $status, $contentType, $body) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $head = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nConnection: close`r`n`r`n"
    $headBytes = [Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($headBytes, 0, $headBytes.Length)
    $stream.Write($bytes, 0, $bytes.Length)
}

function Invoke-Client($client) {
    $client.ReceiveTimeout = 2000
    $client.SendTimeout = 2000
    $stream = $client.GetStream()
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII)
    $requestLine = $reader.ReadLine()
    while (($line = $reader.ReadLine()) -and $line -ne '') { }

    if (($requestLine -split ' ')[1] -ne '/stats') {
        Send-Response $stream '404 Not Found' 'text/plain' 'GET /stats'
    } elseif ($shared.json) {
        Send-Response $stream '200 OK' 'application/json' $shared.json
    } else {
        $message = if ($shared.error) { $shared.error } else { 'warming up' }
        Send-Response $stream '503 Service Unavailable' 'text/plain' $message
    }
}

$shared = [hashtable]::Synchronized(@{ json = $null; error = $null })
$runspace = [powershell]::Create().AddScript($collector).AddArgument($shared).AddArgument($RpcPort)
$null = $runspace.BeginInvoke()

$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Any, $Port)
$listener.Start()
Write-Host "Stats agent listening on port $Port (GET /stats)"
try {
    while ($true) {
        # poll instead of blocking in AcceptTcpClient so Ctrl+C works
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 20; continue }
        $client = $listener.AcceptTcpClient()
        try { Invoke-Client $client } catch { } finally { $client.Close() }
    }
} finally {
    $listener.Stop()
    $runspace.Stop()
    $runspace.Dispose()
}
