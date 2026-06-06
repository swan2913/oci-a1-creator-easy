$ErrorActionPreference = "SilentlyContinue"
$taskName = "OCI-A1-Creator"
Disable-ScheduledTask -TaskName $taskName | Out-Null
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
Write-Host "Removed scheduled task: $taskName"

