param([string]$Serial)
$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$adb=Join-Path $here 'tools\adb.exe'
if (-not $Serial) {
    $lines=& $adb devices
    $ids=@($lines | ForEach-Object { if ($_ -match '^([^\s]+)\s+device$') {$Matches[1]} })
    if ($ids.Count -ne 1) { throw '请只连接一台设备，或传入 -Serial。' }
    $Serial=$ids[0]
}
Write-Host '将删除 NAS 服务、APK 和开机钩子，但保留 /data/media/0/NAS 文件。'
$answer=Read-Host '输入 YES 继续'
if ($answer -cne 'YES') { exit 1 }
& $adb -s $Serial root 2>$null | Out-Null
& $adb -s $Serial wait-for-device | Out-Null
& $adb -s $Serial remount 2>$null | Out-Null
& $adb -s $Serial shell sh /data/local/tmp/rk3399-deploy/uninstall.sh
if ($LASTEXITCODE -ne 0) { & $adb -s $Serial shell su -c 'sh /data/local/tmp/rk3399-deploy/uninstall.sh' }
