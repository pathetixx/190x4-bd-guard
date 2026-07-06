# 190x4 BD Guard — keeps BetterDiscord injected across Discord updates.
# Runs at logon (scheduled task), re-injects instantly when the updater
# rewrites discord_desktop_core/index.js.
#
# Module locations:
#   new updater : %LocalAppData%\Discord*\app-<ver>\modules\discord_desktop_core-N\discord_desktop_core\index.js
#   legacy      : %AppData%\discord*\<ver>\modules\discord_desktop_core-N\discord_desktop_core\index.js

param([switch]$Once)  # -Once: single repair pass, no watcher

$ErrorActionPreference = 'SilentlyContinue'

if (-not $Once) {
    # single resident instance
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Global\190x4BDGuard')
    if (-not $script:Mutex.WaitOne(0)) { exit }
}

$BdAsar = Join-Path $env:APPDATA 'BetterDiscord\data\betterdiscord.asar'

$WatchRoots = @()
foreach ($n in 'Discord', 'DiscordPTB', 'DiscordCanary') {
    $p = Join-Path $env:LOCALAPPDATA $n
    if (Test-Path $p) { $WatchRoots += $p }
}
foreach ($n in 'discord', 'discordptb', 'discordcanary') {
    $p = Join-Path $env:APPDATA $n
    if (Test-Path $p) { $WatchRoots += $p }
}
if (-not $WatchRoots) { exit }

function Show-Toast([string]$Text) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $nodes = $xml.GetElementsByTagName('text')
        $null = $nodes.Item(0).AppendChild($xml.CreateTextNode('BD Guard'))
        $null = $nodes.Item(1).AppendChild($xml.CreateTextNode($Text))
        $toast = New-Object Windows.UI.Notifications.ToastNotification($xml)
        $aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show($toast)
    } catch {}
}

# every discord_desktop_core/index.js across all flavors, both layouts
function Get-CoreIndexFiles {
    $files = @()
    foreach ($root in $WatchRoots) {
        $appDirs = @(Get-ChildItem $root -Directory -Filter 'app-*') +
                   @(Get-ChildItem $root -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' })
        foreach ($app in $appDirs) {
            $modules = Join-Path $app.FullName 'modules'
            if (-not (Test-Path $modules)) { continue }
            $files += Get-ChildItem $modules -Directory -Filter 'discord_desktop_core-*' |
                ForEach-Object { Join-Path $_.FullName 'discord_desktop_core\index.js' } |
                Where-Object { Test-Path $_ }
        }
    }
    return $files
}

# Prepends the BD require line to every stock index.js (keeps original content).
# Returns $true if anything was patched.
function Repair-Injection {
    if (-not (Test-Path $BdAsar)) { return $false }
    $asar = $BdAsar -replace '\\', '/'
    $line = "try { require(`"$asar`"); } catch (e) {}"
    $patched = $false

    foreach ($index in Get-CoreIndexFiles) {
        $content = [System.IO.File]::ReadAllText($index)
        if ($content -match 'betterdiscord\.asar') { continue }
        for ($i = 0; $i -lt 5; $i++) {
            try {
                [System.IO.File]::WriteAllText($index, "$line`n$content")
                $patched = $true
                break
            } catch { Start-Sleep -Milliseconds 300 }
        }
    }
    return $patched
}

# 1) fix stale state left from a previous session
$didPatch = Repair-Injection
if ($Once) { exit }
if ($didPatch) {
    Show-Toast 'BetterDiscord восстановлен после обновления Discord.'
}

# 2) watch the updater rewriting index.js and re-inject on the fly
$watchers = @()
foreach ($dir in $WatchRoots) {
    $w = New-Object System.IO.FileSystemWatcher($dir, 'index.js')
    $w.IncludeSubdirectories = $true
    $w.InternalBufferSize = 65536
    foreach ($ev in 'Created', 'Changed', 'Renamed') {
        $null = Register-ObjectEvent $w -EventName $ev
    }
    $w.EnableRaisingEvents = $true
    $watchers += $w
}

while ($true) {
    $evt = Wait-Event -Timeout 3600   # timeout = hourly safety re-check
    if ($evt) {
        Remove-Event -EventIdentifier $evt.EventIdentifier
        Start-Sleep -Milliseconds 800  # let the updater finish the burst
        Get-Event | ForEach-Object { Remove-Event -EventIdentifier $_.EventIdentifier }
    }
    if (Repair-Injection) {
        Show-Toast 'Discord обновился — BetterDiscord восстановлен. Если он не поднялся, перезапусти Discord через трей (Quit).'
    }
}
