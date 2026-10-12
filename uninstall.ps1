param([string]$Serial)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host 'Remove the NAS startup hook; retain data, rootfs, credentials, backups and APKs.'
if ((Read-Host 'Type YES to continue') -cne 'YES') { exit 1 }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Here 'deploy.ps1') -Uninstall -Serial $Serial
exit $LASTEXITCODE
