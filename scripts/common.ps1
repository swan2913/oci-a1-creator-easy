function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-LocalConfigPath {
    Join-Path (Get-RepoRoot) "config.local.json"
}

function Read-LocalConfig {
    $path = Get-LocalConfigPath
    if (-not (Test-Path $path)) {
        throw "Missing config.local.json. Run scripts\setup.ps1 first."
    }
    Get-Content -Raw -Path $path | ConvertFrom-Json
}

function Save-LocalConfig {
    param([object] $Config)
    $path = Get-LocalConfigPath
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding ascii
}

function Ensure-StateDir {
    $stateDir = Join-Path $env:USERPROFILE ".oci\a1-creator"
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $stateDir
}

function Send-DiscordMessage {
    param(
        [object] $Config,
        [string] $Content
    )
    if (-not $Config.discordWebhookUrl) {
        return
    }
    try {
        $body = @{ content = $Content } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post -Uri $Config.discordWebhookUrl -ContentType "application/json" -Body $body | Out-Null
    }
    catch {
        $stateDir = Ensure-StateDir
        "[$(Get-Date -Format o)] Discord webhook failed: $($_.Exception.Message)" | Add-Content -Path (Join-Path $stateDir "launch.log")
    }
}

function Get-OciErrorSummary {
    param([string] $Text, [int] $ExitCode)

    $summary = [ordered]@{
        ExitCode = $ExitCode
        Code = ""
        Status = ""
        Message = ""
        OpcRequestId = ""
        Operation = ""
    }

    $jsonStart = $Text.IndexOf("{")
    $jsonEnd = $Text.LastIndexOf("}")
    if ($jsonStart -ge 0 -and $jsonEnd -gt $jsonStart) {
        $jsonText = $Text.Substring($jsonStart, $jsonEnd - $jsonStart + 1)
        try {
            $errorJson = $jsonText | ConvertFrom-Json
            $summary.Code = [string]$errorJson.code
            $summary.Status = [string]$errorJson.status
            $summary.Message = [string]$errorJson.message
            $summary.OpcRequestId = [string]$errorJson.'opc-request-id'
            $summary.Operation = [string]$errorJson.operation_name
        }
        catch {
            $summary.Message = ($Text.Trim() -replace "\s+", " ")
        }
    }
    else {
        $summary.Message = ($Text.Trim() -replace "\s+", " ")
    }

    if ($summary.Message.Length -gt 700) {
        $summary.Message = $summary.Message.Substring(0, 700) + "..."
    }

    [pscustomobject]$summary
}
