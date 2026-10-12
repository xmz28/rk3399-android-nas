[CmdletBinding()]
param(
    [string]$Serial,
    [string]$AdbPath,
    [switch]$CheckOnly,
    [switch]$VerifyOnly,
    [switch]$InstallControl,
    [switch]$Fresh,
    [switch]$Uninstall,
    [string]$RollbackBackup,
    [switch]$Reboot,
    [switch]$NoReboot
)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Adb = Join-Path $Here 'tools\adb.exe'
if ($AdbPath) { $Adb = $AdbPath }
if (-not (Test-Path -LiteralPath $Adb)) {
    $sdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $sdkAdb) { $Adb = $sdkAdb }
    elseif ($command) { $Adb = $command.Source }
    else {
        & (Join-Path $Here 'prepare-resources.ps1') -ToolsOnly
        $Adb = Join-Path $Here 'tools\platform-tools\adb.exe'
    }
}
if ($Reboot -and $NoReboot) { throw 'Choose either -Reboot or -NoReboot.' }
if ($Fresh -and ($VerifyOnly -or $Uninstall -or $RollbackBackup)) { throw '-Fresh cannot be combined with verify, uninstall or rollback.' }
if (([int][bool]$CheckOnly + [int][bool]$VerifyOnly + [int][bool]$Uninstall + [int][bool]$RollbackBackup) -gt 1) {
    throw 'Choose one of -CheckOnly, -VerifyOnly, -Uninstall, or -RollbackBackup.'
}
if ($RollbackBackup -and $RollbackBackup -notmatch '^/data/local/rk3399-nas/backups/upgrade-[0-9-]+$') {
    throw 'Invalid rollback backup path.'
}

function Invoke-Adb {
    param([string[]]$Arguments)
    $result = & $Adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')`n$($result -join "`n")" }
    return $result
}
function Invoke-Root {
    param([string]$Command)
    if ($RootMode -eq 'adb') { Invoke-Adb -Arguments @('-s',$Serial,'shell',$Command) }
    else { Invoke-Adb -Arguments @('-s',$Serial,'shell','su','-c',"'$Command'") }
}
function Check-Sources {
    $manifest = Join-Path $Here 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $manifest)) { throw 'Missing SHA256SUMS.txt' }
    $count = 0
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if ($line -notmatch '^([0-9a-f]{64}) \*(.+)$') { throw 'Invalid source checksum manifest.' }
        $expected = $Matches[1]; $relative = $Matches[2]
        if ($relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative)) { throw 'Invalid checksum path.' }
        $path = Join-Path $Here $relative
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() -ne $expected) {
            throw "Source checksum mismatch: $relative"
        }
        $count++
    }
    Write-Host "Source checksums verified: $count"
}

Check-Sources
if ($InstallControl -and -not (Test-Path -LiteralPath (Join-Path $Here 'payload\rk3399-control.apk'))) {
    throw 'Missing payload/rk3399-control.apk. Prepare your trusted RK3399 Control APK first.'
}
if ($InstallControl) {
    $resourceLock = Get-Content (Join-Path $Here 'resources.json') -Raw | ConvertFrom-Json
    if ((Get-FileHash (Join-Path $Here 'payload\rk3399-control.apk')).Hash.ToLower() -ne $resourceLock.control.sha256) {
        throw 'Control APK does not match this release. Build a trusted APK and update resources.json before installing.'
    }
}
if (-not $Serial) {
    $devices = @(Invoke-Adb -Arguments @('devices') | ForEach-Object {
        if ($_ -match '^([^\s]+)\s+device\s*$') { $Matches[1] }
    })
    $candidates = @($devices | Where-Object {
        ((Invoke-Adb -Arguments @('-s',$_,'shell','getprop','ro.board.platform')) -join '').Trim() -match 'rk3399'
    })
    if ($candidates.Count -ne 1) { throw 'Cannot uniquely identify RK3399. Supply -Serial explicitly.' }
    $Serial = $candidates[0]
}
if ($Serial -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Invalid ADB serial.' }
$platform = ((Invoke-Adb -Arguments @('-s',$Serial,'shell','getprop','ro.board.platform')) -join '').Trim()
$abi = ((Invoke-Adb -Arguments @('-s',$Serial,'shell','getprop','ro.product.cpu.abi')) -join '').Trim()
if ($platform -notmatch 'rk3399' -or $abi -notmatch '^(arm64-v8a|aarch64)$') { throw 'Target must be ARM64 RK3399.' }
$uid = ((Invoke-Adb -Arguments @('-s',$Serial,'shell','id','-u')) -join '').Trim()
if ($uid -eq '0') { $RootMode = 'adb' }
else {
    $RootMode = 'su'
    $uid = ((Invoke-Root -Command 'id -u') -join '').Trim()
    if ($uid -ne '0') { throw 'Working root required. Authorize su or enable adb root first.' }
}
Write-Host "Target: $Serial; root: $RootMode"
$Stage = '/data/local/tmp/rk3399-deploy-v2'
# --CheckOnly/--VerifyOnly push inspection scripts; they do not replace services.
Invoke-Root -Command "mkdir -p $Stage" | Out-Null
Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here 'device\status.sh'),"$Stage/status.sh") | Out-Null
if ($VerifyOnly) { Invoke-Root -Command "sh $Stage/status.sh --health"; exit 0 }
if ($RollbackBackup) {
    foreach ($name in @('rollback.sh','service-control.sh')) {
        Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here "device\$name"),"$Stage/$name") | Out-Null
    }
    Invoke-Root -Command "sh $Stage/rollback.sh $RollbackBackup"
    exit 0
}
if ($Uninstall) {
    foreach ($name in @('uninstall.sh','service-control.sh')) {
        Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here "device\$name"),"$Stage/$name") | Out-Null
    }
    Invoke-Root -Command "sh $Stage/uninstall.sh"
    exit 0
}
Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here 'device\preflight.sh'),"$Stage/preflight.sh") | Out-Null
$preflightCommand = "sh $Stage/preflight.sh"
if ($Fresh) { $preflightCommand += ' --fresh' }
elseif ($InstallControl) { $preflightCommand += ' --control' }
Invoke-Root -Command $preflightCommand
if ($CheckOnly) { exit 0 }
if ($Fresh) {
    $image = Join-Path $Here 'payload\alpine-nas-clean.tar.gz'
    $imageManifest = Join-Path $Here 'payload\rootfs.sha256'
    $onlineBuild = -not (Test-Path $image)
    & (Join-Path $Here 'prepare-resources.ps1') -SpeedOnly
    if ($onlineBuild) {
        & (Join-Path $Here 'prepare-resources.ps1')
        $image = Join-Path $Here 'payload\alpine-minirootfs.tar.gz'
        $imageManifest = Join-Path $Here 'payload\base.sha256'
    }
    if (-not (Test-Path $imageManifest)) { throw 'Missing rootfs checksum.' }
    $expectedImage = (Get-Content $imageManifest -Raw).Trim()
    if ($expectedImage -notmatch '^[0-9a-f]{64}$' -or (Get-FileHash $image).Hash.ToLower() -ne $expectedImage) { throw 'Clean rootfs checksum mismatch.' }
    if (Test-Path (Join-Path $Here 'credentials.txt')) { throw 'credentials.txt already exists; preserve it and use a new package directory for another fresh installation.' }
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Here 'device') -File) {
    Invoke-Adb -Arguments @('-s',$Serial,'push',$file.FullName,"$Stage/$($file.Name)") | Out-Null
}
if ($Fresh) {
    $random = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $password = [Convert]::ToBase64String($random).Replace('+','-').Replace('/','_')
    $credentialTemp = Join-Path ([IO.Path]::GetTempPath()) ('rk3399-credential-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($credentialTemp,(@{password=$password} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        # Save before device initialization, so failed installations cannot lose their password.
        $credentialPath = Join-Path $Here 'credentials.txt'
        [IO.File]::WriteAllText($credentialPath,"File-service username: admin`nFile-service password: $password`nTarget: $Serial`nKeep this file private. Control App uses its own password.`n",[Text.UTF8Encoding]::new($false))
        if ($env:OS -eq 'Windows_NT') {
            & icacls $credentialPath /inheritance:r /grant:r "$([Security.Principal.WindowsIdentity]::GetCurrent().Name):(F)" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Unable to protect credentials.txt permissions.' }
            & icacls $credentialTemp /inheritance:r /grant:r "$([Security.Principal.WindowsIdentity]::GetCurrent().Name):(F)" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Unable to protect temporary credential permissions.' }
        }
        Invoke-Root -Command "chmod 700 $Stage" | Out-Null
        if ($onlineBuild) {
            Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here 'payload/copyparty-sfx.py'),"$Stage/copyparty-sfx.py") | Out-Null
            Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here 'build-rootfs.sh'),"$Stage/build-rootfs.sh") | Out-Null
            Invoke-Adb -Arguments @('-s',$Serial,'push',$image,"$Stage/alpine-minirootfs.tar.gz") | Out-Null
        } else {
            Invoke-Adb -Arguments @('-s',$Serial,'push',$image,"$Stage/alpine-nas-clean.tar.gz") | Out-Null
        }
        Invoke-Adb -Arguments @('-s',$Serial,'push',$imageManifest,"$Stage/rootfs.sha256") | Out-Null
        Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here 'payload/openspeedtest.tar.gz'),"$Stage/openspeedtest.tar.gz") | Out-Null
        Invoke-Adb -Arguments @('-s',$Serial,'push',(Join-Path $Here 'payload/speedtest.sha256'),"$Stage/speedtest.sha256") | Out-Null
        Invoke-Adb -Arguments @('-s',$Serial,'push',$credentialTemp,"$Stage/credentials.json") | Out-Null
        $freshCommand = "sh $Stage/install_fresh.sh"
        if ($onlineBuild) { $freshCommand += ' --online' }
        Invoke-Root -Command $freshCommand
        Write-Host 'Your generated file-service password is saved in credentials.txt. Keep it private.'
    } finally {
        if (Test-Path -LiteralPath $credentialTemp) { Remove-Item -LiteralPath $credentialTemp }
        Invoke-Root -Command "rm -f $Stage/credentials.json" | Out-Null
        $password = $null
    }
} else { Invoke-Root -Command "sh $Stage/install_device.sh" }
if ($InstallControl) {
    Invoke-Adb -Arguments @('-s',$Serial,'install','-r',(Join-Path $Here 'payload\rk3399-control.apk'))
    Write-Host 'Open RK3399 Control, grant root, and start its authenticated remote service for /storage/.'
}
if ($Reboot) {
    Invoke-Adb -Arguments @('-s',$Serial,'reboot') | Out-Null
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        Start-Sleep -Seconds 2
        $state = & $Adb devices 2>$null
        if ($state -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") { $ready = $true; break }
    }
    if (-not $ready) { throw 'Reboot timeout: device did not reconnect.' }
    Start-Sleep -Seconds 30
    Invoke-Root -Command "sh $Stage/status.sh --health"
}
Write-Host 'Open http://a.local/ (files, speedtest, storage). Existing file-service passwords were retained.'
Write-Host 'OpenSpeedTest :3000 and RK3399 Control :8765 must already be available for their pages.'
