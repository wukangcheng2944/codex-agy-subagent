# agy-sidebar.ps1: Launch AGY in sidebar terminal or detached background process
# with automatic event-driven Codex wakeup and ZERO polling.

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Task,
    [string]$Mode = "accept-edits",
    [string]$Effort = "high",
    [string]$Direction = "right",
    [string]$Workspace = "",
    [string]$ThreadId = ""
)

$ErrorActionPreference = "Continue"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# 1. Resolve workspace
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}
if (-not (Test-Path -LiteralPath $Workspace)) {
    $Workspace = $env:USERPROFILE
}

# 2. Resolve Codex Thread ID
$dataDir = "C:\Users\EDY\AppData\Local\AGY OAuth Switcher"
$activeThreadFile = Join-Path $dataDir "active-codex-thread.txt"
$wsThreadFile = Join-Path $Workspace ".codex-thread"

$targetThread = $ThreadId
if ([string]::IsNullOrWhiteSpace($targetThread)) {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) {
        $targetThread = $env:CODEX_THREAD_ID.Trim()
    } elseif (Test-Path -LiteralPath $activeThreadFile) {
        $targetThread = (Get-Content -LiteralPath $activeThreadFile -Raw -Encoding utf8).Trim()
    } elseif (Test-Path -LiteralPath $wsThreadFile) {
        $targetThread = (Get-Content -LiteralPath $wsThreadFile -Raw -Encoding utf8).Trim()
    } else {
        $sessionIndex = Join-Path $env:USERPROFILE ".codex\session_index.jsonl"
        if (Test-Path -LiteralPath $sessionIndex) {
            $lines = Get-Content -LiteralPath $sessionIndex -Tail 10
            foreach ($line in ($lines | Sort-Object -Descending)) {
                try {
                    $json = $line | ConvertFrom-Json
                    if ($json.id) { $targetThread = $json.id; break }
                } catch {}
            }
        }
    }
}

# Persist target thread to workspace and active file so hooks find it reliably
if (-not [string]::IsNullOrWhiteSpace($targetThread)) {
    try {
        [IO.File]::WriteAllText($activeThreadFile, $targetThread, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($wsThreadFile, $targetThread, [Text.Encoding]::UTF8)
    } catch {}
}

# 3. Check for Herdr integration
$inHerdr = $false
$herdrCmd = Get-Command herdr -ErrorAction SilentlyContinue
if ($herdrCmd -and -not [string]::IsNullOrWhiteSpace($env:HERDR_PANE_ID)) {
    try {
        $status = & herdr status 2>$null | Out-String
        if ($status -match "status:\s*running") {
            $inHerdr = $true
        }
    } catch {}
}

$launcher = Join-Path $dataDir "Invoke-CodexAGY.ps1"
$psExecutable = if (Test-Path "C:\Program Files\PowerShell\7\pwsh.exe") {
    "C:\Program Files\PowerShell\7\pwsh.exe"
} else {
    "pwsh.exe"
}

$dispatchedVia = ""
$processId = 0

if ($inHerdr) {
    # Split Herdr pane to the side
    try {
        $splitJson = & herdr pane split --current --direction $Direction --no-focus --cwd $Workspace --output json 2>$null | ConvertFrom-Json
        $newPaneId = $splitJson.result.pane.pane_id
        if (-not [string]::IsNullOrWhiteSpace($newPaneId)) {
            $agyExecCmd = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -DataDirectory `"$dataDir`" --prompt `"$Task`" --mode $Mode --effort $Effort --output-format json"
            & herdr pane run $newPaneId $agyExecCmd 2>$null | Out-Null
            $dispatchedVia = "Herdr Sidebar Pane ($newPaneId)"
        }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($dispatchedVia)) {
    # Launch detached background process
    $psArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $launcher,
        "-DataDirectory", $dataDir,
        "--prompt", $Task,
        "--mode", $Mode,
        "--effort", $Effort,
        "--output-format", "json"
    )
    
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $psExecutable
    foreach ($arg in $psArgs) {
        $startInfo.ArgumentList.Add($arg)
    }
    $startInfo.WorkingDirectory = $Workspace
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    if (-not [string]::IsNullOrWhiteSpace($targetThread)) {
        $startInfo.EnvironmentVariables["CODEX_THREAD_ID"] = $targetThread
    }
    
    $proc = [System.Diagnostics.Process]::Start($startInfo)
    $processId = $proc.Id
    $dispatchedVia = "Background Terminal Task (PID: $processId)"
}

# 4. Output structured result and loud no-polling instructions
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "[AGY SIDEBAR SUBAGENT DISPATCHED]" -ForegroundColor Green
Write-Host "  - Task: $Task"
Write-Host "  - Surface: $dispatchedVia"
Write-Host "  - Mode: $Mode | Effort: $Effort"
Write-Host "  - Target Codex Thread: $targetThread"
Write-Host "  - Callback Hook: ACTIVE (Stop Hook -> codex queue)"
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "CRITICAL INSTRUCTIONS FOR CODEX:" -ForegroundColor Yellow
Write-Host "1. DO NOT POLL FOR STATUS." -ForegroundColor Red
Write-Host "2. DO NOT run 'manage_task status', 'Get-Process', or sleep/wait loops." -ForegroundColor Red
Write-Host "3. IMMEDIATELY FINISH THIS TURN AND STOP CALLING TOOLS." -ForegroundColor Yellow
Write-Host "The AGY Stop Hook will automatically inject the completed report directly"
Write-Host "into this Codex thread via 'codex queue' and wake you up reactively."
Write-Host "================================================================================" -ForegroundColor Cyan
