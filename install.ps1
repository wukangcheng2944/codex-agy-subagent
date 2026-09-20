# ==============================================================================
# Codex-AGY Subagent & Sidebar Zero-Polling One-Click Installer
# GitHub: https://github.com/wukangcheng2944/codex-agy-subagent
# ==============================================================================

[CmdletBinding()]
param(
    [string]$RepoUrl = "https://raw.githubusercontent.com/wukangcheng2944/codex-agy-subagent/main",
    [string]$TargetDir = (Join-Path $env:LOCALAPPDATA "AGY OAuth Switcher")
)

$ErrorActionPreference = "Continue"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Codex-AGY Subagent & Sidebar Zero-Polling Installer" -ForegroundColor Green
Write-Host "Target Machine: $(hostname) | Current User: $env:USERNAME" -ForegroundColor Cyan
Write-Host "Installation Directory: $TargetDir" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Prepare target directories
$userHome = $env:USERPROFILE
$dirs = @(
    $TargetDir,
    (Join-Path $TargetDir "mcp"),
    (Join-Path $TargetDir "scripts"),
    (Join-Path $userHome ".codex"),
    (Join-Path $userHome ".agents\rules"),
    (Join-Path $userHome "bin")
)

foreach ($d in $dirs) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# 2. Determine file source (Local vs Remote GitHub)
$isLocal = $false
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "mcp\subagent-server.mjs"))) {
    $isLocal = $true
}

$filesToDeploy = @(
    @{ Rel = "mcp\subagent-server.mjs"; Dest = (Join-Path $TargetDir "mcp\subagent-server.mjs") },
    @{ Rel = "scripts\notify-codex.ps1"; Dest = (Join-Path $TargetDir "scripts\notify-codex.ps1") },
    @{ Rel = "scripts\notify-codex.cmd"; Dest = (Join-Path $TargetDir "scripts\notify-codex.cmd") },
    @{ Rel = "scripts\codex-session-record.ps1"; Dest = (Join-Path $TargetDir "scripts\codex-session-record.ps1") },
    @{ Rel = "scripts\codex-session-record.cmd"; Dest = (Join-Path $TargetDir "scripts\codex-session-record.cmd") },
    @{ Rel = "scripts\agy-sidebar.ps1"; Dest = (Join-Path $TargetDir "scripts\agy-sidebar.ps1") },
    @{ Rel = "scripts\agy-sidebar.cmd"; Dest = (Join-Path $TargetDir "scripts\agy-sidebar.cmd") },
    @{ Rel = "rules\agy-subagent.md"; Dest = (Join-Path $userHome ".agents\rules\agy-subagent.md") }
)

Write-Host "[1/6] Deploying core components..." -ForegroundColor Yellow

if ($isLocal) {
    Write-Host "Installing from local repository files..." -ForegroundColor Gray
    foreach ($item in $filesToDeploy) {
        $sourcePath = Join-Path $PSScriptRoot $item.Rel
        if (Test-Path -LiteralPath $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination $item.Dest -Force
        }
    }
} else {
    Write-Host "Downloading components from GitHub ($RepoUrl)..." -ForegroundColor Gray
    foreach ($item in $filesToDeploy) {
        $downloadUrl = "$RepoUrl/" + ($item.Rel -replace '\\', '/')
        try {
            Invoke-RestMethod -Uri $downloadUrl -OutFile $item.Dest -ErrorAction Stop
        } catch {
            Write-Host "Warning: Failed to download $($item.Rel) from $downloadUrl: $_" -ForegroundColor Red
        }
    }
}

# Copy CLI commands to ~/bin
Copy-Item (Join-Path $TargetDir "scripts\agy-sidebar.*") (Join-Path $userHome "bin\") -Force

# Copy AGENTS rules to workspace roots
$rulesSrc = Join-Path $userHome ".agents\rules\agy-subagent.md"
if (Test-Path -LiteralPath $rulesSrc) {
    Copy-Item $rulesSrc (Join-Path $userHome ".codex\AGENTS.md") -Force
    Copy-Item $rulesSrc (Join-Path $userHome "AGENTS.md") -Force
}

# 3. Create space-free NTFS junction
Write-Host "[2/6] Configuring path compatibility junction..." -ForegroundColor Yellow
$junctionPath = Join-Path $userHome ".codex-agy"
if (-not (Test-Path -LiteralPath $junctionPath)) {
    cmd /c mklink /J "$junctionPath" "$TargetDir" 2>$null | Out-Null
    Write-Host "[OK] Created junction: $junctionPath -> $TargetDir" -ForegroundColor Green
} else {
    Write-Host "[OK] Junction already exists: $junctionPath" -ForegroundColor Green
}

# 4. Register Codex MCP Server in config.toml
Write-Host "[3/6] Registering Codex MCP Subagent Server..." -ForegroundColor Yellow
$configToml = Join-Path $userHome ".codex\config.toml"
if (Test-Path -LiteralPath $configToml) {
    $content = Get-Content -LiteralPath $configToml -Raw -Encoding utf8
    if ($content -notmatch 'mcp_servers\.agy_subagent') {
        $mcpServerPath = (Join-Path $TargetDir "mcp\subagent-server.mjs") -replace '\\', '\\'
        $mcpEntry = @"

[mcp_servers.agy_subagent]
command = 'node'
args = ['$mcpServerPath']
startup_timeout_sec = 30
tool_timeout_sec = 600
"@
        Add-Content -LiteralPath $configToml -Value $mcpEntry -Encoding utf8
        Write-Host "[OK] Registered agy_subagent in $configToml" -ForegroundColor Green
    } else {
        Write-Host "[OK] agy_subagent already registered in $configToml" -ForegroundColor Green
    }
} else {
    $mcpServerPath = (Join-Path $TargetDir "mcp\subagent-server.mjs") -replace '\\', '\\'
    $newConfig = @"
[mcp_servers.agy_subagent]
command = 'node'
args = ['$mcpServerPath']
startup_timeout_sec = 30
tool_timeout_sec = 600
"@
    Set-Content -LiteralPath $configToml -Value $newConfig -Encoding utf8
    Write-Host "[OK] Created $configToml with agy_subagent" -ForegroundColor Green
}

# 5. Register Stop Hook for event-driven wakeup
Write-Host "[4/6] Registering AGY Stop Hook (Zero-Polling Event Bridge)..." -ForegroundColor Yellow
$hookDirs = @(
    (Join-Path $userHome ".agents"),
    (Join-Path $userHome ".gemini\config"),
    (Join-Path $TargetDir "codex-home\.gemini\config")
)

foreach ($hDir in $hookDirs) {
    if (-not (Test-Path -LiteralPath $hDir)) {
        New-Item -ItemType Directory -Path $hDir -Force | Out-Null
    }
    $hPath = Join-Path $hDir "hooks.json"
    $hConfig = if (Test-Path -LiteralPath $hPath) {
        try { Get-Content -LiteralPath $hPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { [pscustomobject]@{} }
    } else { [pscustomobject]@{} }
    
    if (-not $hConfig.hooks) {
        $hConfig | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    
    $stopCommand = (Join-Path $junctionPath "scripts\notify-codex.cmd")
    $stopHook = @(
        [pscustomobject]@{
            hooks = @(
                [pscustomobject]@{
                    type = "command"
                    command = $stopCommand
                    timeout = 15
                }
            )
        }
    )
    $hConfig.hooks | Add-Member -NotePropertyName "Stop" -NotePropertyValue $stopHook -Force
    $hConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $hPath -Encoding utf8
    Write-Host "[OK] Updated Stop Hook in $hPath" -ForegroundColor Green
}

# 6. Register SessionStart Hook in .codex/hooks.json
Write-Host "[5/6] Registering Codex SessionStart Hook..." -ForegroundColor Yellow
$codexHookPath = Join-Path $userHome ".codex\hooks.json"
$codexHookConfig = if (Test-Path -LiteralPath $codexHookPath) {
    try { Get-Content -LiteralPath $codexHookPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { [pscustomobject]@{} }
} else { [pscustomobject]@{} }

if (-not $codexHookConfig.hooks) {
    $codexHookConfig | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([pscustomobject]@{}) -Force
}

$sessionHooks = @()
if ($codexHookConfig.hooks.SessionStart) {
    $sessionHooks = @($codexHookConfig.hooks.SessionStart)
}
$sessionRecordCmd = (Join-Path $junctionPath "scripts\codex-session-record.cmd")
$hasHook = $false
foreach ($sh in $sessionHooks) {
    if ($sh.hooks) {
        foreach ($h in $sh.hooks) {
            if ($h.command -match "codex-session-record") { $hasHook = $true }
        }
    }
}

if (-not $hasHook) {
    $sessionHooks += [pscustomobject]@{
        hooks = @(
            [pscustomobject]@{
                type = "command"
                command = $sessionRecordCmd
                timeout = 5
            }
        )
    }
    $codexHookConfig.hooks | Add-Member -NotePropertyName "SessionStart" -NotePropertyValue $sessionHooks -Force
    $codexHookConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $codexHookPath -Encoding utf8
    Write-Host "[OK] Registered SessionStart Hook in $codexHookPath" -ForegroundColor Green
} else {
    Write-Host "[OK] SessionStart Hook already present in $codexHookPath" -ForegroundColor Green
}

# 7. Update PowerShell profile and PATH
Write-Host "[6/6] Configuring Shell Profile & PATH..." -ForegroundColor Yellow
$profilePath = Join-Path $userHome "Documents\PowerShell\profile.ps1"
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$profileContent = if (Test-Path -LiteralPath $profilePath) { Get-Content -LiteralPath $profilePath -Raw -Encoding utf8 } else { "" }
if ($profileContent -notmatch "function global:agy-sidebar") {
    $profileAppend = @"

function global:agy-sidebar {
    `$sidebarScript = '$TargetDir\scripts\agy-sidebar.ps1'
    if (-not (Test-Path -LiteralPath `$sidebarScript -PathType Leaf)) {
        `$sidebarScript = (Join-Path `$env:USERPROFILE 'bin\agy-sidebar.ps1')
    }
    & `$sidebarScript @args
}
"@
    Add-Content -LiteralPath $profilePath -Value $profileAppend -Encoding utf8
    Write-Host "[OK] Added agy-sidebar function to $profilePath" -ForegroundColor Green
} else {
    Write-Host "[OK] agy-sidebar function already exists in $profilePath" -ForegroundColor Green
}

$userBin = Join-Path $userHome "bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -split ';' -notcontains $userBin) {
    [Environment]::SetEnvironmentVariable("Path", "$userBin;$currentPath", "User")
    Write-Host "[OK] Added $userBin to User PATH" -ForegroundColor Green
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Codex-AGY Subagent & Sidebar Zero-Polling successfully installed!" -ForegroundColor Green
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "  1. Inline MCP Subagent: Call agy_subagent inside Codex"
Write-Host "  2. Sidebar Dispatch: Run 'agy-sidebar -Task \"<task>\"' or tool 'agy_sidebar_dispatch'"
Write-Host "================================================================================" -ForegroundColor Cyan
