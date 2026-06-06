$ErrorActionPreference = "Continue"
. "$PSScriptRoot\common.ps1"

$config = Read-LocalConfig
$stateDir = Ensure-StateDir
$logFile = Join-Path $stateDir "launch.log"
$successFlag = Join-Path $stateDir "INSTANCE_CREATED"
$startedFlag = Join-Path $stateDir "STARTED"
$attemptFile = Join-Path $stateDir "attempt.txt"

if (Test-Path $successFlag) {
    exit 0
}

if (-not (Test-Path $startedFlag)) {
    "started $(Get-Date -Format o)" | Set-Content -Path $startedFlag -Encoding ascii
    Send-DiscordMessage $config "OCI A1 creator started. Region: $($config.region), shape: VM.Standard.A1.Flex, $($config.ocpus) OCPU / $($config.memoryInGBs) GB, boot volume $($config.bootVolumeSizeInGBs) GB."
}

$attempt = 0
if (Test-Path $attemptFile) {
    [void][int]::TryParse((Get-Content -Raw -Path $attemptFile).Trim(), [ref]$attempt)
}
$attempt++
$attempt | Set-Content -Path $attemptFile -Encoding ascii

"[$(Get-Date -Format o)] Attempt $attempt" | Add-Content -Path $logFile

$shapeConfigFile = Join-Path $stateDir "shape-config.json"
@{ ocpus = $config.ocpus; memoryInGBs = $config.memoryInGBs } | ConvertTo-Json -Compress | Set-Content -Path $shapeConfigFile -Encoding ascii

$args = @(
    "compute", "instance", "launch",
    "--no-retry",
    "--compartment-id", $config.compartmentId,
    "--availability-domain", $config.availabilityDomain,
    "--shape", "VM.Standard.A1.Flex",
    "--shape-config", "file://$shapeConfigFile",
    "--subnet-id", $config.subnetId,
    "--image-id", $config.imageId,
    "--assign-public-ip", "true",
    "--boot-volume-size-in-gbs", ([string]$config.bootVolumeSizeInGBs),
    "--ssh-authorized-keys-file", $config.sshPublicKeyFile,
    "--display-name", $config.instanceName,
    "--output", "json"
)

$result = & oci @args 2>&1
$exitCode = $LASTEXITCODE
$resultText = $result | Out-String
$resultText | Add-Content -Path $logFile

if ($exitCode -eq 0) {
    try {
        $json = $resultText | ConvertFrom-Json
        if ($json.data.id) {
            $instanceId = $json.data.id
            $instanceName = $json.data.'display-name'
            "created $(Get-Date -Format o)`n$instanceId" | Set-Content -Path $successFlag -Encoding ascii
            Send-DiscordMessage $config "OCI A1 instance created: $instanceName`n$instanceId`nScheduled task will be disabled automatically."
            Disable-ScheduledTask -TaskName "OCI-A1-Creator" -ErrorAction SilentlyContinue | Out-Null
            exit 0
        }
    }
    catch {
        "[$(Get-Date -Format o)] Success exit code but JSON parse failed: $($_.Exception.Message)" | Add-Content -Path $logFile
    }
}

$errorSummary = Get-OciErrorSummary -Text $resultText -ExitCode $exitCode
$discordMessage = @"
OCI A1 creator attempt $attempt failed.
ExitCode: $($errorSummary.ExitCode)
Status: $($errorSummary.Status)
Code: $($errorSummary.Code)
Message: $($errorSummary.Message)
Operation: $($errorSummary.Operation)
OpcRequestId: $($errorSummary.OpcRequestId)
Log: $logFile
"@
Send-DiscordMessage $config $discordMessage.Trim()
exit 0

