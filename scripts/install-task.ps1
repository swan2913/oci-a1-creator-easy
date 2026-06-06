$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

$config = Read-LocalConfig
$taskName = "OCI-A1-Creator"
$scriptPath = Join-Path $PSScriptRoot "run-once.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Send-DiscordMessage $config "OCI A1 creator scheduled task installed and started. Task: $taskName"

Get-ScheduledTask -TaskName $taskName | Select-Object TaskName,State
Get-ScheduledTaskInfo -TaskName $taskName | Format-List LastRunTime,LastTaskResult,NextRunTime

