#requires -Version 5.1
param(
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'AGY OAuth Switcher'),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AgyArguments = @()
)
$ErrorActionPreference = 'Stop'
$client = Get-Content -LiteralPath (Join-Path $DataDirectory 'client.json') -Raw -Encoding utf8 | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $client.executable -PathType Leaf)) { throw '未找到 agy.exe。' }
$base = [uri]$client.baseURL
if ($base.Scheme -ne 'http' -or $base.Host -ne '127.0.0.1') { throw '账号池入口必须是本机地址。' }
try {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $null = Invoke-RestMethod -Uri ($client.baseURL + '/v1beta/models') -Headers @{ 'x-goog-api-key' = $client.apiKey } -NoProxy -TimeoutSec 5
    } else {
        $null = Invoke-RestMethod -Uri ($client.baseURL + '/v1beta/models') -Headers @{ 'x-goog-api-key' = $client.apiKey } -TimeoutSec 5
    }
} catch { throw '账号池未就绪，请先打开 AGY OAuth Switcher。' }

$nativeHome = if ($env:AGY_SWITCHER_NATIVE_HOME) { $env:AGY_SWITCHER_NATIVE_HOME } else { $env:USERPROFILE }
$nativeDirectory = Join-Path $nativeHome '.gemini/antigravity-cli'
$profilePath = Join-Path $DataDirectory 'codex-home'
$configDirectory = Join-Path $profilePath '.gemini/antigravity-cli'
New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null

# Share conversation databases and their artifacts by directory, including SQLite WAL files.
# Configuration stays separate, and no native credential or executable is replaced.
foreach ($name in @('conversations', 'brain', 'knowledge', 'annotations', 'implicit')) {
    $source = Join-Path $nativeDirectory $name
    $destination = Join-Path $configDirectory $name
    if (Test-Path -LiteralPath $source -PathType Container) {
        if (-not (Test-Path -LiteralPath $destination)) {
            New-Item -ItemType Junction -Path $destination -Target $source | Out-Null
        } else {
            $link = Get-Item -LiteralPath $destination -Force
            $targetRaw = if ($link.Target -is [System.Collections.IEnumerable] -and $link.Target -isnot [string]) { $link.Target[0] } else { $link.Target }
            $linkTarget = if ($link.ResolvedTarget) { $link.ResolvedTarget } else { $targetRaw }
            $fullTarget = if ($linkTarget) { [IO.Path]::GetFullPath($linkTarget).TrimEnd('\', '/') } else { '' }
            $fullSource = [IO.Path]::GetFullPath($source).TrimEnd('\', '/')

            if ($link.LinkType -ne 'Junction' -or $fullTarget -ne $fullSource) {
                # If junction is invalid, stale, or target mismatch, safely recreate it
                Remove-Item -LiteralPath $destination -Force -Recurse -ErrorAction SilentlyContinue
                New-Item -ItemType Junction -Path $destination -Target $source -Force | Out-Null
            }
        }
    }
}
$configPath = Join-Path $configDirectory 'settings.json'
$nativeConfig = Join-Path $nativeDirectory 'settings.json'
$settings = if (Test-Path -LiteralPath $configPath) {
    Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
} elseif (Test-Path -LiteralPath $nativeConfig) {
    Get-Content -LiteralPath $nativeConfig -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
} else {
    @{}
}
if ($settings.modelProvider -ne 'gemini') {
    $settings.modelProvider = 'gemini'
    $settings | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $configPath -Encoding utf8
}
$oldEnvironment = @{}
foreach ($name in @('USERPROFILE', 'HOME', 'GEMINI_API_KEY', 'GOOGLE_GEMINI_BASE_URL', 'AGY_ADC_AUTH', 'AGY_SWITCHER_NATIVE_HOME')) {
    $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:USERPROFILE = $profilePath
    $env:HOME = $profilePath
    $env:AGY_SWITCHER_NATIVE_HOME = $nativeHome
    $env:GEMINI_API_KEY = $client.apiKey
    $env:GOOGLE_GEMINI_BASE_URL = $client.baseURL
    Remove-Item -LiteralPath Env:AGY_ADC_AUTH -ErrorAction SilentlyContinue
    $effectiveArgs = @($AgyArguments)
    if ($effectiveArgs -notcontains '--dangerously-skip-permissions') {
        $effectiveArgs = @('--dangerously-skip-permissions') + $effectiveArgs
    }
    & $client.executable @effectiveArgs
    $nativeExitCode = $LASTEXITCODE
} finally {
    foreach ($name in $oldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name], 'Process') }
}
$global:LASTEXITCODE = $nativeExitCode
