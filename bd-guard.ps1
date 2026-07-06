# 190x4 BD Guard — keeps BetterDiscord injected across Discord updates.
# Runs at logon (scheduled task), re-injects instantly when the updater
# rewrites discord_desktop_core/index.js.

$ErrorActionPreference = 'SilentlyContinue'

# single instance
$script:Mutex = New-Object System.Threading.Mutex($false, 'Global\190x4BDGuard')
if (-not $script:Mutex.WaitOne(0)) { exit }

$BdAsar   = Join-Path $env:APPDATA 'BetterDiscord\data\betterdiscord.asar'
$DataDirs = @('discord', 'discordptb', 'discordcanary') |
    ForEach-Object { Join-Path $env:APPDATA $_ } |
    Where-Object { Test-Path $_ }

if (-not $DataDirs) { exit }

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

# Re-adds the BD require line to every stock discord_desktop_core/index.js.
# Returns $true if anything was patched.
function Repair-Injection {
    if (-not (Test-Path $BdAsar)) { return $false }
    $patched = $false
    $asar = $BdAsar -replace '\\', '/'
    $inject = "try { require(`"$asar`"); } catch (e) {}`nmodule.exports = require(`"./core.asar`");"

    foreach ($dir in $DataDirs) {
        foreach ($ver in Get-ChildItem $dir -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' }) {
            $core = Get-ChildItem (Join-Path $ver.FullName 'modules') -Directory -Filter 'discord_desktop_core-*' |
                Sort-Object { [int]($_.Name.Split('-')[-1]) } -Descending |
                Select-Object -First 1
            if (-not $core) { continue }
            $index = Join-Path $core.FullName 'discord_desktop_core\index.js'
            if (-not (Test-Path $index)) { continue }

            $content = [System.IO.File]::ReadAllText($index)
            if ($content -match 'betterdiscord\.asar') { continue }

            for ($i = 0; $i -lt 5; $i++) {
                try {
                    [System.IO.File]::WriteAllText($index, $inject)
                    $patched = $true
                    break
                } catch { Start-Sleep -Milliseconds 300 }
            }
        }
    }
    return $patched
}

# 1) fix stale state left from a previous session
if (Repair-Injection) {
    Show-Toast 'BetterDiscord восстановлен после обновления Discord.'
}

# 2) watch the updater rewriting index.js and re-inject on the fly
$watchers = @()
foreach ($dir in $DataDirs) {
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
