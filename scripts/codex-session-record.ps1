# Record active Codex session ID for AGY event notification bridge
$inputText = [Console]::In.ReadToEnd()
try {
    $payload = if ([string]::IsNullOrWhiteSpace($inputText)) { $null } else { $inputText | ConvertFrom-Json }
    if ($payload -and $payload.session_id) {
        $dataDir = "C:\Users\EDY\AppData\Local\AGY OAuth Switcher"
        if (-not (Test-Path -LiteralPath $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $sessionFile = Join-Path $dataDir "active-codex-thread.txt"
        [IO.File]::WriteAllText($sessionFile, $payload.session_id.ToString().Trim(), [Text.Encoding]::UTF8)
        
        # Also write to codex-home if present
        $homeSessionFile = "C:\Users\EDY\AppData\Local\AGY OAuth Switcher\codex-home\active-codex-thread.txt"
        [IO.File]::WriteAllText($homeSessionFile, $payload.session_id.ToString().Trim(), [Text.Encoding]::UTF8)
    }
} catch {
}
exit 0
