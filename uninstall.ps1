# Removes the 190x4 BD Guard task, its running instance and files.
$ErrorActionPreference = 'SilentlyContinue'

Unregister-ScheduledTask -TaskName '190x4 BD Guard' -Confirm:$false

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'bd-guard\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item (Join-Path $env:LOCALAPPDATA 'BDGuard') -Recurse -Force
Write-Host 'BD Guard removed.' -ForegroundColor Green
