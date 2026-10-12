[CmdletBinding()]
param([switch]$ToolsOnly, [switch]$SpeedOnly)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Get-VerifiedResource([string]$Url, [string]$Hash, [string]$Destination) {
    if ((Test-Path -LiteralPath $Destination) -and (Get-FileHash $Destination).Hash.ToLower() -eq $Hash) { return }
    $part = "$Destination.part"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $part -UseBasicParsing -TimeoutSec 180
        if ((Get-FileHash $part).Hash.ToLower() -ne $Hash) { throw "Resource checksum mismatch: $Url" }
        Move-Item -LiteralPath $part -Destination $Destination -Force
    } finally {
        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part }
    }
}
$lock = Get-Content (Join-Path $Here 'resources.json') -Raw | ConvertFrom-Json
if ($ToolsOnly) {
    New-Item -ItemType Directory -Force (Join-Path $Here 'tools') | Out-Null
    $zip = Join-Path $Here 'tools/platform-tools.zip'
    Get-VerifiedResource $lock.platformTools.url $lock.platformTools.sha256 $zip
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $Here 'tools') -Force
    exit 0
}
New-Item -ItemType Directory -Force (Join-Path $Here 'payload') | Out-Null
Get-VerifiedResource $lock.speedtest.url $lock.speedtest.sha256 (Join-Path $Here 'payload/openspeedtest.tar.gz')
[IO.File]::WriteAllText((Join-Path $Here 'payload/speedtest.sha256'), $lock.speedtest.sha256 + "`n", [Text.UTF8Encoding]::new($false))
if ($SpeedOnly) { exit 0 }
Get-VerifiedResource $lock.alpine.url $lock.alpine.sha256 (Join-Path $Here 'payload/alpine-minirootfs.tar.gz')
Get-VerifiedResource $lock.copyparty.url $lock.copyparty.sha256 (Join-Path $Here 'payload/copyparty-sfx.py')
[IO.File]::WriteAllText((Join-Path $Here 'payload/base.sha256'), $lock.alpine.sha256 + "`n", [Text.UTF8Encoding]::new($false))
Write-Host 'Verified official Alpine base and Copyparty resources prepared.'
