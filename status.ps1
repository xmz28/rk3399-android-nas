param([string]$Serial)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'deploy.ps1') -VerifyOnly -Serial $Serial
exit $LASTEXITCODE
