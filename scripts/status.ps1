$taskName = "OCI-A1-Creator"
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName,State
Get-ScheduledTaskInfo -TaskName $taskName | Format-List LastRunTime,LastTaskResult,NextRunTime,NumberOfMissedRuns
Get-Content -Tail 80 "$env:USERPROFILE\.oci\a1-creator\launch.log"
