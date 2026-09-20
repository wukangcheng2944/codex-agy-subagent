param(
    [string]$CodexCliPath = '',
    [string]$LogFile = ''
)

if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $PSScriptRoot 'notify-codex.log'
}

function Write-NotifyLog([string]$msg) {
    try {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
        Add-Content -LiteralPath $LogFile -Value "[$timestamp] $msg" -Encoding utf8 -ErrorAction SilentlyContinue
    } catch {}
}

# 1. Read AGY lifecycle context from stdin
$inputText = [Console]::In.ReadToEnd()
Write-NotifyLog "Received stdin length: $($inputText.Length)"

$payload = $null
if (-not [string]::IsNullOrWhiteSpace($inputText)) {
    try {
        $payload = $inputText | ConvertFrom-Json
    } catch {
        Write-NotifyLog "Failed to parse stdin JSON: $_"
    }
}

$conversationId = "unknown"
if ($payload -and $payload.conversationId) { $conversationId = $payload.conversationId }

$workspacePath = (Get-Location).Path
if ($payload -and $payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) {
    $workspacePath = $payload.workspacePaths[0]
}

$transcriptPath = $null
if ($payload -and $payload.transcriptPath) { $transcriptPath = $payload.transcriptPath }

$artifactsPath = $null
if ($payload -and $payload.artifactDirectoryPath) { $artifactsPath = $payload.artifactDirectoryPath }

$reason = "model_stop"
if ($payload -and $payload.terminationReason) { $reason = $payload.terminationReason }

$errorMsg = ""
if ($payload -and $payload.error) { $errorMsg = $payload.error }

Write-NotifyLog "Parsed payload: conversationId=$conversationId, reason=$reason, workspace=$workspacePath"

# 2. Extract execution summary from artifacts or transcript
$extractedSummary = ""

if ($artifactsPath -and (Test-Path -LiteralPath $artifactsPath -PathType Container)) {
    $walkthrough = Join-Path $artifactsPath "walkthrough.md"
    $plan = Join-Path $artifactsPath "implementation_plan.md"
    if (Test-Path -LiteralPath $walkthrough -PathType Leaf) {
        $content = Get-Content -LiteralPath $walkthrough -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        if ($content) {
            if ($content.Length -gt 1500) {
                $extractedSummary = $content.Substring(0, 1500) + "`r`n... [Truncated. See walkthrough.md for full report]"
            } else {
                $extractedSummary = $content
            }
        }
    } elseif (Test-Path -LiteralPath $plan -PathType Leaf) {
        $content = Get-Content -LiteralPath $plan -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        if ($content) {
            if ($content.Length -gt 1500) {
                $extractedSummary = $content.Substring(0, 1500) + "`r`n... [Truncated. See implementation_plan.md for full report]"
            } else {
                $extractedSummary = $content
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($extractedSummary) -and $transcriptPath -and (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) {
    try {
        $lines = Get-Content -LiteralPath $transcriptPath -Tail 20 -Encoding utf8 -ErrorAction SilentlyContinue
        if ($lines) {
            [array]::Reverse($lines)
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $item = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($item -and $item.text -and ($item.role -eq "model" -or $item.role -eq "assistant")) {
                    $extractedSummary = $item.text
                    break
                }
            }
        }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($extractedSummary)) {
    if (-not [string]::IsNullOrWhiteSpace($errorMsg)) {
        $extractedSummary = "Task stopped with error: $errorMsg"
    } else {
        $extractedSummary = "Task completed with status: $reason."
    }
}

# 3. Resolve target Codex Thread/Session ID
$targetThread = $null

$realHome = if ($env:AGY_SWITCHER_NATIVE_HOME) { $env:AGY_SWITCHER_NATIVE_HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { "C:\Users\$env:USERNAME" }

if (-not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) {
    $targetThread = $env:CODEX_THREAD_ID.Trim()
    Write-NotifyLog "Target thread from env CODEX_THREAD_ID: $targetThread"
}

if (-not $targetThread) {
    $activeFile = Join-Path $realHome "AppData\Local\AGY OAuth Switcher\active-codex-thread.txt"
    if (Test-Path -LiteralPath $activeFile -PathType Leaf) {
        $candidate = (Get-Content -LiteralPath $activeFile -Raw -Encoding utf8).Trim()
        if ($candidate) {
            $targetThread = $candidate
            Write-NotifyLog "Target thread from active-codex-thread.txt: $targetThread"
        }
    }
}

if (-not $targetThread) {
    $sessionIndexPath = Join-Path $realHome '.codex\session_index.jsonl'
    if (Test-Path -LiteralPath $sessionIndexPath -PathType Leaf) {
        try {
            $lines = Get-Content -LiteralPath $sessionIndexPath -Tail 10 -Encoding utf8
            foreach ($line in ($lines | Sort-Object -Descending)) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $sessionObj = $line | ConvertFrom-Json
                    if ($sessionObj.id) {
                        $targetThread = $sessionObj.id
                        Write-NotifyLog "Target thread fallback from session_index.jsonl: $targetThread"
                        break
                    }
                }
            }
        } catch {
            Write-NotifyLog "Error reading session_index: $_"
        }
    }
}

if (-not $targetThread) {
    $anchorFile = Join-Path $workspacePath '.codex-thread'
    if (Test-Path -LiteralPath $anchorFile -PathType Leaf) {
        $targetThread = (Get-Content -LiteralPath $anchorFile -Raw -Encoding utf8).Trim()
        Write-NotifyLog "Target thread from .codex-thread: $targetThread"
    }
}

# 3.1 Resolve Codex executable path dynamically
if ([string]::IsNullOrWhiteSpace($CodexCliPath) -or (-not (Test-Path -LiteralPath $CodexCliPath))) {
    $foundCmd = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($foundCmd -and (Test-Path -LiteralPath $foundCmd)) {
        $CodexCliPath = $foundCmd
    } else {
        $candidates = Get-ChildItem -Path (Join-Path $realHome "AppData\Local\OpenAI\Codex\bin") -Filter "codex.exe" -Recurse -ErrorAction SilentlyContinue
        if ($candidates) {
            $CodexCliPath = ($candidates | Select-Object -First 1).FullName
        }
    }
}
Write-NotifyLog "Resolved CodexCliPath: $CodexCliPath"

# 4. Push event notification into Codex queue (Event-driven wakeup)
if ($targetThread -and (Test-Path -LiteralPath $CodexCliPath -PathType Leaf)) {
    $dirInfo = if ($artifactsPath) { $artifactsPath } else { "None" }
    $errInfo = if ($errorMsg) { " ($errorMsg)" } else { "" }

    $msgLines = @(
        "[AGY Subagent Task Finished - Event-Driven Notification]",
        "- Status: $reason$errInfo",
        "- AGY Session: $conversationId",
        "- Artifacts: $dirInfo",
        "",
        "---",
        "### Summary & Output:",
        $extractedSummary,
        "---",
        "Notice: Subagent finished. Codex may continue execution without status polling."
    )
    $notifyBody = [string]::Join("`r`n", $msgLines)

    Write-NotifyLog "Invoking codex queue for thread $targetThread"
    try {
        $queueOutput = & $CodexCliPath queue --thread $targetThread --message $notifyBody 2>&1
        Write-NotifyLog "codex queue result: $queueOutput"
    } catch {
        Write-NotifyLog "codex queue invocation exception: $_"
    }
} else {
    $cliExists = Test-Path -LiteralPath $CodexCliPath
    Write-NotifyLog "Skipping codex queue: targetThread=$targetThread, cliExists=$cliExists"
}

# 5. Emit AGY Stop hook contract JSON
$response = @{
    decision = "allow"
}
[Console]::Out.WriteLine(($response | ConvertTo-Json -Compress))
exit 0
