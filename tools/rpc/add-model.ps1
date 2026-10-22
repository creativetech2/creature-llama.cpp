<#
.SYNOPSIS
Add a model to the pool: copy a local .gguf (or a folder for sharded/multimodal models) or download one, then rescan.

.EXAMPLE
.\add-model.ps1 -Source D:\downloads\Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf
.\add-model.ps1 -Source https://huggingface.co/unsloth/Qwen3-8B-GGUF/blob/main/Qwen3-8B-Q4_K_M.gguf
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [string]$ModelsDir = (Join-Path $env:USERPROFILE 'llama-models'),
    [string]$Server = 'http://127.0.0.1:9931',
    [string]$ApiKey,
    [switch]$Move
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force $ModelsDir | Out-Null

if ($Source -match '^https?://') {
    # a Hugging Face page link points at the file page, resolve/ is the download
    $url = $Source -replace '/blob/', '/resolve/'
    $fileName = [IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
    if ($fileName -notmatch '\.gguf$') { throw "The link must point at a .gguf file, got '$fileName'" }
    $dest = Join-Path $ModelsDir $fileName

    # curl.exe ships with Windows, resumes with -C - and needs no OpenSSL
    & curl.exe -L --fail -C - --progress-bar -o $dest $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed (curl exit code $LASTEXITCODE)" }
} else {
    if (-not (Test-Path $Source)) { throw "Not found: $Source" }
    $item = Get-Item $Source
    $dest = Join-Path $ModelsDir $item.Name
    if ($Move) { Move-Item $Source $dest -Force } else { Copy-Item $Source $dest -Recurse -Force }
}

$id = [IO.Path]::GetFileNameWithoutExtension($dest)
Write-Host "Added $id to $ModelsDir"

# tell a running router to rescan, it picks the file up on the next start otherwise
$headers = @{}
if ($ApiKey) { $headers.Authorization = "Bearer $ApiKey" }
try {
    Invoke-RestMethod "$Server/models?reload=1" -Headers $headers -TimeoutSec 10 | Out-Null
    Write-Host "Router rescanned. Load '$id' from the Models tab, or send a request with that model name."
} catch {
    Write-Host "Router not reachable at $Server, the model shows up when start-master.ps1 starts."
}
