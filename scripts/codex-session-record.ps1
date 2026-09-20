# Record active Codex session ID for AGY event notification bridge
$inputText = [Console]::In.ReadToEnd()
try {
    $payload = if ([string]::IsNullOrWhiteSpace($inputText)) { $null } else { $inputText | ConvertFrom-Json }
    if ($payload -and $payload.session_id) {
        $sessionId = $payload.session_id.ToString().Trim()
        
        $localApp = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\Local" }
        $dataDir = Join-Path $localApp "AGY OAuth Switcher"
        if (-not (Test-Path -LiteralPath $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $sessionFile = Join-Path $dataDir "active-codex-thread.txt"
        [IO.File]::WriteAllText($sessionFile, $sessionId, [Text.Encoding]::UTF8)
        
        # Also write to codex-home if present
        $homeSessionDir = Join-Path $dataDir "codex-home"
        if (Test-Path -LiteralPath $homeSessionDir) {
            $homeSessionFile = Join-Path $homeSessionDir "active-codex-thread.txt"
            [IO.File]::WriteAllText($homeSessionFile, $sessionId, [Text.Encoding]::UTF8)
        }
    }
} catch {
}
exit 0
