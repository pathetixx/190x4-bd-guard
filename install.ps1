# 190x4 BD Guard installer: downloads the guard, registers a hidden
# logon task, (re)starts it and prints the injection status.
$ErrorActionPreference = 'Stop'

$Dir = Join-Path $env:LOCALAPPDATA 'BDGuard'

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
# GitHub API instead of raw.githubusercontent: no 5-minute CDN cache
Invoke-RestMethod 'https://api.github.com/repos/pathetixx/190x4-bd-guard/contents/bd-guard.ps1?ref=main' `
    -Headers @{ Accept = 'application/vnd.github.raw' } -OutFile (Join-Path $Dir 'bd-guard.ps1')

# wscript shim -> no console flash at logon
$vbs = @"
CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$Dir\bd-guard.ps1""", 0, False
"@
Set-Content (Join-Path $Dir 'run-hidden.vbs') $vbs -Encoding ASCII

$action   = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$Dir\run-hidden.vbs`""
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName '190x4 BD Guard' -Action $action -Trigger $trigger `
    -Settings $settings -Force | Out-Null

# kill a previous guard instance so the fresh one can take the mutex
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'bd-guard\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-ScheduledTask -TaskName '190x4 BD Guard'

# synchronous first repair - don't rely on the resident guard's startup timing
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'bd-guard.ps1') -Once
Write-Host 'BD Guard installed and running.' -ForegroundColor Green

# --- status report ---
Start-Sleep -Seconds 3

$guardProc = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'bd-guard\.ps1' -and $_.CommandLine -notmatch '-Once' }
if ($guardProc) {
    Write-Host '  guard process: running' -ForegroundColor Green
} else {
    Write-Host '  guard process: NOT running (scheduled task did not start)' -ForegroundColor Red
}

$bdAsar = Join-Path $env:APPDATA 'BetterDiscord\data\betterdiscord.asar'
if (-not (Test-Path $bdAsar)) {
    Write-Host 'WARNING: betterdiscord.asar not found - install BetterDiscord once, then rerun this.' -ForegroundColor Yellow
    return
}

$roots = @()
foreach ($n in 'Discord', 'DiscordPTB', 'DiscordCanary') {
    $p = Join-Path $env:LOCALAPPDATA $n
    if (Test-Path $p) { $roots += $p }
}
foreach ($n in 'discord', 'discordptb', 'discordcanary') {
    $p = Join-Path $env:APPDATA $n
    if (Test-Path $p) { $roots += $p }
}

$found = $false
foreach ($root in $roots) {
    $appDirs = @(Get-ChildItem $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue) +
               @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' })
    foreach ($app in $appDirs) {
        $modules = Join-Path $app.FullName 'modules'
        if (-not (Test-Path $modules)) { continue }
        Get-ChildItem $modules -Directory -Filter 'discord_desktop_core-*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $index = Join-Path $_.FullName 'discord_desktop_core\index.js'
                if (Test-Path $index) {
                    $found = $true
                    $ok = (Get-Content $index -Raw) -match 'betterdiscord\.asar'
                    $state = if ($ok) { 'BD injected' } else { 'NOT injected' }
                    $color = if ($ok) { 'Green' } else { 'Red' }
                    Write-Host ("  {0}\{1}: {2}" -f (Split-Path $root -Leaf), $app.Name, $state) -ForegroundColor $color
                }
            }
    }
}
if (-not $found) {
    Write-Host 'WARNING: no discord_desktop_core/index.js found in any Discord installation.' -ForegroundColor Yellow
}
