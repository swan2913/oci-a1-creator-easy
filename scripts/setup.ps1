$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

function Read-Required {
    param([string] $Prompt)
    do {
        $value = Read-Host $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))
    $value.Trim()
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "Installing uv..."
    powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"
}

if (-not (Get-Command oci -ErrorAction SilentlyContinue)) {
    Write-Host "Installing oci-cli with uv..."
    uv tool install oci-cli
}

$ociDir = Join-Path $env:USERPROFILE ".oci"
New-Item -ItemType Directory -Force -Path $ociDir | Out-Null

$configPath = Get-LocalConfigPath
if (Test-Path $configPath) {
    $config = Read-LocalConfig
}
else {
    $config = Get-Content -Raw (Join-Path (Get-RepoRoot) "config.example.json") | ConvertFrom-Json
}

$config.userId = Read-Required "OCI user OCID"
$config.fingerprint = Read-Required "OCI API key fingerprint"
$config.compartmentId = Read-Required "Tenancy OCID"
$config.region = Read-Required "Region, e.g. ap-chuncheon-1"

$keyFile = Read-Required "Private key .pem path"
$keyFile = $keyFile.Trim('"')
if (-not (Test-Path $keyFile)) {
    throw "Private key file not found: $keyFile"
}
$targetKeyFile = Join-Path $ociDir "oci_api_key.pem"
Copy-Item -LiteralPath $keyFile -Destination $targetKeyFile -Force
$config.keyFile = $targetKeyFile

$sshPub = Join-Path $env:USERPROFILE ".ssh\id_ed25519.pub"
if (-not (Test-Path $sshPub)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sshPub) | Out-Null
    ssh-keygen -t ed25519 -f (Join-Path $env:USERPROFILE ".ssh\id_ed25519") -N ""
}
$config.sshPublicKeyFile = $sshPub

$discord = Read-Host "Discord webhook URL, optional"
$config.discordWebhookUrl = $discord.Trim()

$ociConfig = @"
[DEFAULT]
user=$($config.userId)
fingerprint=$($config.fingerprint)
tenancy=$($config.compartmentId)
region=$($config.region)
key_file=$($config.keyFile)
"@
$ociConfigPath = Join-Path $ociDir "config"
$ociConfig | Set-Content -Path $ociConfigPath -Encoding ascii
oci setup repair-file-permissions --file $ociConfigPath | Out-Null
oci setup repair-file-permissions --file $targetKeyFile | Out-Null

Write-Host "Querying availability domains..."
$ads = (oci iam availability-domain list -c $config.compartmentId --output json | ConvertFrom-Json).data
$config.availabilityDomain = ($ads | Select-Object -First 1).name

Write-Host "Preparing network..."
$vcn = (oci network vcn list -c $config.compartmentId --display-name "oci-a1-vcn" --output json | ConvertFrom-Json).data | Select-Object -First 1
if (-not $vcn) {
    $vcn = (oci network vcn create -c $config.compartmentId --cidr-block "10.0.0.0/16" --display-name "oci-a1-vcn" --dns-label "ocia1" --wait-for-state AVAILABLE --output json | ConvertFrom-Json).data
}

$igw = (oci network internet-gateway list -c $config.compartmentId --vcn-id $vcn.id --display-name "oci-a1-igw" --output json | ConvertFrom-Json).data | Select-Object -First 1
if (-not $igw) {
    $igw = (oci network internet-gateway create -c $config.compartmentId --vcn-id $vcn.id --is-enabled true --display-name "oci-a1-igw" --wait-for-state AVAILABLE --output json | ConvertFrom-Json).data
}

$stateDir = Ensure-StateDir
$routeRulesPath = Join-Path $stateDir "route-rules.json"
$secIdsPath = Join-Path $stateDir "security-list-ids.json"
$routeRules = @(@{ destination = "0.0.0.0/0"; destinationType = "CIDR_BLOCK"; networkEntityId = $igw.id })
$secIds = @($vcn.'default-security-list-id')
ConvertTo-Json -InputObject $routeRules -Compress | Set-Content -Path $routeRulesPath -Encoding ascii
ConvertTo-Json -InputObject $secIds -Compress | Set-Content -Path $secIdsPath -Encoding ascii
oci network route-table update --rt-id $vcn.'default-route-table-id' --route-rules "file://$routeRulesPath" --force --output json | Out-Null

$subnet = (oci network subnet list -c $config.compartmentId --vcn-id $vcn.id --display-name "oci-a1-public-subnet" --output json | ConvertFrom-Json).data | Select-Object -First 1
if (-not $subnet) {
    $subnet = (oci network subnet create -c $config.compartmentId --vcn-id $vcn.id --cidr-block "10.0.1.0/24" --display-name "oci-a1-public-subnet" --dns-label "public" --availability-domain $config.availabilityDomain --route-table-id $vcn.'default-route-table-id' --security-list-ids "file://$secIdsPath" --prohibit-public-ip-on-vnic false --wait-for-state AVAILABLE --output json | ConvertFrom-Json).data
}
$config.subnetId = $subnet.id

Write-Host "Selecting latest Ubuntu ARM image..."
$images = (oci compute image list -c $config.compartmentId --operating-system "Canonical Ubuntu" --shape "VM.Standard.A1.Flex" --sort-by TIMECREATED --sort-order DESC --all --output json | ConvertFrom-Json).data
$config.imageId = ($images | Where-Object { $_.'display-name' -like "*aarch64*" } | Select-Object -First 1).id

Save-LocalConfig $config
Send-DiscordMessage $config "OCI A1 creator configured. Region: $($config.region), AD: $($config.availabilityDomain), subnet ready."

Write-Host "Done. Created config.local.json"
Write-Host "Run scripts\install-task.ps1 to start the 1-minute retry loop."
