<#
.SYNOPSIS
Build llama.cpp RPC on Windows with NVIDIA CUDA.

.DESCRIPTION
-Role Host   builds ggml-rpc-server, opens the firewall port and optionally starts the server.
-Role Master builds llama-server and llama-cli with the RPC backend and optionally checks the hosts.

.EXAMPLE
.\install-rpc.ps1 -Role Host -Start
.\install-rpc.ps1 -Role Master -Hosts 192.168.88.10:50052,192.168.88.11:50052
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Host', 'Master')][string]$Role,
    [int]$Port = 50052,
    [int]$StatsPort = 50053,
    [string]$BindAddress = '0.0.0.0',
    [string]$CudaPath,
    [string]$CudaArch,
    [string[]]$Hosts,
    [switch]$Cache,
    [switch]$SkipFirewall,
    [switch]$Start,
    [switch]$BuildUi,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path (Join-Path $root 'CMakeLists.txt'))) { throw "llama.cpp source not found at $root" }
$buildDir = Join-Path $root "build-rpc-$($Role.ToLower())"

# GPU architectures, e.g. 12.0 -> 120
if (-not $CudaArch) {
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { throw 'nvidia-smi not found. Install the NVIDIA driver or pass -CudaArch.' }
    $caps = & nvidia-smi --query-gpu=compute_cap --format=csv,noheader
    if ($LASTEXITCODE -ne 0 -or -not $caps) { throw 'Could not read the GPU compute capability. Pass -CudaArch (for example 89).' }
    $CudaArch = ($caps | ForEach-Object { $_.Trim().Replace('.', '') } | Sort-Object -Unique) -join ';'
}
$archNums = $CudaArch -split ';' | ForEach-Object { [int]($_ -replace '[^0-9]', '') }
$minArch = ($archNums | Measure-Object -Minimum).Minimum
$maxArch = ($archNums | Measure-Object -Maximum).Maximum
Write-Host "CUDA architectures: $CudaArch"

# CUDA_PATH often points at an old toolkit, so pick one that fits the GPUs
if (-not $CudaPath) {
    $cudaRoot = Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit\CUDA'
    $toolkits = Get-ChildItem $cudaRoot -Directory -Filter 'v*' -ErrorAction SilentlyContinue |
        ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Version = [version]($_.Name.TrimStart('v')) } } |
        Where-Object { Test-Path (Join-Path $_.Path 'bin\nvcc.exe') } |
        Where-Object { $maxArch -lt 100 -or $_.Version -ge [version]'12.8' } |
        Where-Object { $minArch -ge 75 -or $_.Version -lt [version]'13.0' } |
        Sort-Object Version -Descending
    if (-not $toolkits) { throw "No CUDA toolkit under $cudaRoot supports architectures $CudaArch. GPUs of compute capability 10+ need CUDA 12.8 or newer; before 7.5 need CUDA 12.x. Install one or pass -CudaPath." }
    $CudaPath = @($toolkits)[0].Path
}
$nvcc = Join-Path $CudaPath 'bin\nvcc.exe'
if (-not (Test-Path $nvcc)) { throw "nvcc not found at $nvcc" }
Write-Host "CUDA toolkit: $CudaPath"

# nvcc rejects MSVC 14.50 (VS 2026), so prefer an older toolset when one is installed
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Visual Studio not found. Install Visual Studio with the "Desktop development with C++" workload.' }
$toolsets = foreach ($vs in & $vswhere -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) {
    foreach ($dir in Get-ChildItem (Join-Path $vs 'VC\Tools\MSVC') -Directory) {
        [pscustomobject]@{ VS = $vs; Version = [version]$dir.Name }
    }
}
if (-not $toolsets) { throw 'No MSVC toolset found. Add "MSVC C++ x64/x86 build tools" in the Visual Studio installer.' }
$supported = @($toolsets | Where-Object { $_.Version -lt [version]'14.50' } | Sort-Object Version -Descending)
$cudaFlags = ''
if ($supported) {
    $tool = $supported[0]
    $vcArg = "-vcvars_ver=$($tool.Version.Major).$($tool.Version.Minor)"
} else {
    $tool = @($toolsets | Sort-Object Version -Descending)[0]
    $vcArg = ''
    $cudaFlags = '-allow-unsupported-compiler'
    Write-Warning "Only MSVC $($tool.Version) is installed and CUDA does not support it. Building with -allow-unsupported-compiler. For a supported setup add the 'MSVC v143 - VS 2022 C++ x64/x86 build tools' component in the Visual Studio installer."
}
Write-Host "MSVC toolset: $($tool.Version)"

$vcvars = Join-Path $tool.VS 'VC\Auxiliary\Build\vcvars64.bat'
$envDump = cmd /c "`"$vcvars`" $vcArg >nul 2>&1 && set"
foreach ($line in $envDump) {
    if ($line -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
}
if (-not $env:VCINSTALLDIR) { throw "vcvars64.bat failed ($vcvars $vcArg)" }
foreach ($tool in 'cmake', 'ninja') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found. Add 'C++ CMake tools for Windows' in the Visual Studio installer." }
}

$env:CUDA_PATH = $CudaPath
$env:PATH = "$(Join-Path $CudaPath 'bin');$env:PATH"

if ($Clean -and (Test-Path $buildDir)) { Remove-Item $buildDir -Recurse -Force }
# CMake cannot switch compilers inside an existing build tree
$cachePath = Join-Path $buildDir 'CMakeCache.txt'
if (Test-Path $cachePath) {
    $cachedNvcc = (Select-String -Path $cachePath -Pattern '^CMAKE_CUDA_COMPILER:[A-Z]+=(.*)$').Matches.Groups[1].Value
    if ($cachedNvcc -and ($cachedNvcc -replace '/', '\') -ne $nvcc) {
        Write-Host "Compiler changed ($cachedNvcc), recreating build directory"
        Remove-Item $buildDir -Recurse -Force
    }
}

$cmakeArgs = @(
    '-S', $root, '-B', $buildDir, '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DGGML_CUDA=ON', '-DGGML_RPC=ON',
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch",
    "-DCMAKE_CUDA_COMPILER=$nvcc",
    "-DCUDAToolkit_ROOT=$CudaPath"
)
if ($cudaFlags) { $cmakeArgs += "-DCMAKE_CUDA_FLAGS=$cudaFlags" }
if ($BuildUi) {
    # tools/ui/dist wins over the npm build and the prebuilt download has no RPC/Models tabs
    if (Test-Path (Join-Path $root 'tools\ui\dist')) { throw 'tools\ui\dist exists and would be embedded instead of a fresh UI build. Delete it first.' }
    $cmakeArgs += '-DLLAMA_BUILD_UI=ON', '-DLLAMA_USE_PREBUILT_UI=OFF'
}
[string[]]$targets = if ($Role -eq 'Host') { 'ggml-rpc-server' } else { 'llama-server', 'llama-cli' }

# PowerShell 5.1 turns native stderr into errors when redirected, so rely on exit codes
$ErrorActionPreference = 'Continue'
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }
& cmake --build $buildDir --target $targets
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
$ErrorActionPreference = 'Stop'

# Make bin self-contained, the CUDA runtime DLLs are not on PATH for other users or services
$binDir = Join-Path $buildDir 'bin'
foreach ($dir in 'bin', 'bin\x64') {
    foreach ($pattern in 'cudart64_*.dll', 'cublas64_*.dll', 'cublasLt64_*.dll') {
        Get-ChildItem (Join-Path $CudaPath $dir) -Filter $pattern -ErrorAction SilentlyContinue | Copy-Item -Destination $binDir -Force
    }
}

$lanIps = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
    ForEach-Object { $_.IPAddress }

if ($Role -eq 'Host') {
    $exe = Join-Path $binDir 'ggml-rpc-server.exe'
    $ruleName = 'llama.cpp RPC server'
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $statsRuleName = 'llama.cpp RPC stats'
    $ruleCmds = @(
        "New-NetFirewallRule -DisplayName '$ruleName' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress LocalSubnet -Program '$exe'",
        "New-NetFirewallRule -DisplayName '$statsRuleName' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $StatsPort -RemoteAddress LocalSubnet"
    )
    if ($SkipFirewall) {
        Write-Host 'Skipping firewall rules'
    } elseif ($isAdmin) {
        Get-NetFirewallRule -DisplayName $ruleName, $statsRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        foreach ($cmd in $ruleCmds) { Invoke-Expression $cmd | Out-Null }
        Write-Host "Firewall: allowed TCP $Port and $StatsPort from the local subnet"
    } else {
        Write-Warning "Not elevated, firewall rules not created. Run this once in an Administrator PowerShell:`n  $($ruleCmds -join "`n  ")"
    }

    Write-Host "`nBuilt $exe"
    Write-Host "Host addresses (use one in the master's --rpc): $($lanIps -join ', ')"
    Write-Host "Start later with: .\start-rpc-server.ps1 -Port $Port$(if ($Cache) { ' -Cache' })"
    if ($Start) {
        & (Join-Path $PSScriptRoot 'start-rpc-server.ps1') -Port $Port -StatsPort $StatsPort -BindAddress $BindAddress -Cache:$Cache
    }
} else {
    $failed = $false
    foreach ($endpoint in $Hosts) {
        $name, $p = $endpoint -split ':'
        if (-not $p) { $p = 50052 }
        $client = New-Object Net.Sockets.TcpClient
        $ok = $false
        try { $ok = $client.ConnectAsync($name, [int]$p).Wait(3000) } catch { }
        $client.Dispose()
        Write-Host ("  {0}:{1} {2}" -f $name, $p, $(if ($ok) { 'reachable' } else { 'NOT reachable' }))
        if (-not $ok) { $failed = $true }
    }
    if ($failed) { Write-Warning 'Some hosts are unreachable. Check the host is running start-rpc-server.ps1, the firewall rule and the IP.' }

    $rpc = if ($Hosts) { $Hosts -join ',' } else { '<host1>:50052,<host2>:50052' }
    Write-Host "`nBuilt llama-server and llama-cli in $binDir"
    Write-Host "Run: .\start-master.ps1 -Hosts $rpc"
    Write-Host "Or a single model: $binDir\llama-server.exe -m <model.gguf> -ngl 99 --rpc $rpc"
}
