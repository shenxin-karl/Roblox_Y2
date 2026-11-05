@echo off
setlocal
set "CLASH_RULES_SELF=%~f0"
set "CLASH_RULES_CHECK=%~1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:CLASH_RULES_SELF); & ([scriptblock]::Create(($s -split '(?m)^# POWERSHELL_START\r?\n',2)[1]))"
set "task_exit=%errorlevel%"
if /i not "%~1"=="--check" pause
exit /b %task_exit%
# POWERSHELL_START
$ErrorActionPreference = 'Stop'
try {
    $root = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
    $profiles = [IO.File]::ReadAllText((Join-Path $root 'profiles.yaml'))
    $current = [regex]::Match($profiles, '(?m)^current:\s*([^\r\n]+)').Groups[1].Value.Trim().Trim("'", '"')
    if (-not $current) { throw 'Cannot find the active Clash Verge profile.' }
    $entry = [regex]::Match($profiles, '(?ms)^- uid:\s*' + [regex]::Escape($current) + '\s*\r?\n(?:(?!^- uid:).)*')
    $file = [regex]::Match($entry.Value, '(?m)^\s+file:\s*([^\r\n]+)').Groups[1].Value.Trim().Trim("'", '"')
    if (-not $file -or [IO.Path]::GetFileName($file) -ne $file) { throw 'Cannot resolve the active profile file.' }
    $targets = @((Join-Path $root ('profiles\' + $file)), (Join-Path $root 'clash-verge.yaml'))
    $rules = @(
        'PROCESS-NAME,steam.exe,DIRECT'
        'PROCESS-NAME,steamwebhelper.exe,DIRECT'
        'PROCESS-NAME,steamservice.exe,DIRECT'
        'PROCESS-NAME,etalien.exe,DIRECT'
        'GEOSITE,steam,DIRECT'
        'DOMAIN-SUFFIX,feishu.cn,DIRECT'
        'DOMAIN-SUFFIX,feishucdn.com,DIRECT'
        'DOMAIN-SUFFIX,feishupkg.com,DIRECT'
        'DOMAIN-SUFFIX,youku.com,DIRECT'
        'DOMAIN-SUFFIX,youku.tv,DIRECT'
        'DOMAIN-SUFFIX,ykimg.com,DIRECT'
        'DOMAIN-SUFFIX,tudou.com,DIRECT'
        'DOMAIN-SUFFIX,soku.com,DIRECT'
        'DOMAIN,ykimg.alicdn.com,DIRECT'
        'GEOSITE,private,DIRECT'
        'GEOIP,private,DIRECT,no-resolve'
        'GEOSITE,cn,DIRECT'
        'GEOIP,CN,DIRECT'
    )
    $updates = @()
    foreach ($path in $targets) {
        $text = [IO.File]::ReadAllText($path)
        $header = [regex]::Match($text, '(?m)^rules:[ \t]*\r?$')
        if (-not $header.Success) { throw "No explicit rules list in $path. No files changed." }
        $nl = "`n"
        if ($text.Contains("`r`n")) { $nl = "`r`n" }
        $tail = $text.Substring($header.Index + $header.Length).TrimStart("`r", "`n")
        foreach ($rule in $rules) {
            $tail = [regex]::Replace($tail, '(?m)^[ \t]*-[ \t]*' + [regex]::Escape($rule) + '[ \t]*\r?\n?', '')
        }
        $insert = (($rules | ForEach-Object { '  - ' + $_ }) -join $nl) + $nl
        $updated = $text.Substring(0, $header.Index) + 'rules:' + $nl + $insert + $tail
        $updates += [pscustomobject]@{ Path = $path; Text = $updated }
    }
    if ($env:CLASH_RULES_CHECK -eq '--check') {
        Write-Host ('Check OK. Active profile: ' + $file + '; direct rules: ' + $rules.Count)
        Write-Host 'No files changed.'
        exit 0
    }
    $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')
    foreach ($update in $updates) {
        [IO.File]::Copy($update.Path, ($update.Path + '.' + $stamp + '.bak'), $false)
        [IO.File]::WriteAllText($update.Path, $update.Text, [Text.UTF8Encoding]::new($false))
    }
    Write-Host 'Rules saved. Timestamped .bak backups are beside both configuration files.'
    $pipe = $null
    try {
        $runtime = $updates[1].Text
        $pipePath = [regex]::Match($runtime, '(?m)^external-controller-pipe:[ \t]*([^\r\n]+)').Groups[1].Value.Trim().Trim("'", '"')
        if (-not $pipePath) { throw 'No local control pipe configured.' }
        $pipeName = ($pipePath -split '\\')[-1]
        $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect(3000)
        $body = @{ path = $targets[1] } | ConvertTo-Json -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $headerBytes = [Text.Encoding]::ASCII.GetBytes("PUT /configs?force=true HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
        $pipe.Write($headerBytes, 0, $headerBytes.Length)
        $pipe.Write($bytes, 0, $bytes.Length)
        $pipe.Flush()
        $reader = [IO.StreamReader]::new($pipe)
        $status = $reader.ReadLine()
        if ($status -notmatch '^HTTP/\S+ 204\b') { throw "Reload failed: $status" }
        Write-Host 'Clash configuration reloaded. Pause/resume Steam downloads to reconnect.'
    } catch {
        Write-Warning ('Automatic reload unavailable: ' + $_.Exception.Message)
        Write-Host 'Rules are saved. Restart Clash Verge to apply them.'
    } finally {
        if ($pipe) { $pipe.Dispose() }
    }
    Write-Host 'Enable Steam acceleration in ETAlien separately. DIRECT does not enable the accelerator.'
    exit 0
} catch {
    Write-Error $_
    exit 1
}
