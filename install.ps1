# 190x4 BD Guard installer: downloads the guard, registers a hidden
# logon task and starts it immediately.
$ErrorActionPreference = 'Stop'

$Dir  = Join-Path $env:LOCALAPPDATA 'BDGuard'
$Base = 'https://raw.githubusercontent.com/pathetixx/190x4-bd-guard/main'

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Invoke-RestMethod "$Base/bd-guard.ps1" -OutFile (Join-Path $Dir 'bd-guard.ps1')

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

Start-ScheduledTask -TaskName '190x4 BD Guard'
Write-Host 'BD Guard installed and running.' -ForegroundColor Green
