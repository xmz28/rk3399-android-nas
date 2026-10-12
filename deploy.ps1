[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$NoReboot,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Adb = Join-Path $Here 'tools\adb.exe'
$Payload = Join-Path $Here 'payload'
$Device = Join-Path $Here 'device'
$Stage = '/data/local/tmp/rk3399-deploy'

function Fail([string]$Message) { throw $Message }

if (-not (Test-Path -LiteralPath $Adb)) { Fail "ADB 不存在：$Adb" }

function Invoke-Adb {
    param([Parameter(Position=0)][string[]]$ArgumentList, [switch]$AllowFailure, [switch]$Quiet)
    $out = & $Adb -s $script:Serial @ArgumentList 2>&1
    $code = $LASTEXITCODE
    if (-not $Quiet -and $out) { $out | ForEach-Object { Write-Host $_ } }
    if ($code -ne 0 -and -not $AllowFailure) { Fail "ADB 命令失败（$code）：adb $($ArgumentList -join ' ')" }
    return @($out)
}

function Select-Device {
    if ($script:Serial) {
        $state = & $Adb -s $script:Serial get-state 2>$null
        if ($LASTEXITCODE -ne 0 -or $state -notmatch 'device') { Fail "找不到指定设备 $script:Serial" }
        return
    }
    $lines = & $Adb devices -l
    $candidates = @()
    foreach ($line in $lines) {
        if ($line -match '^([^\s]+)\s+device\b') { $candidates += $Matches[1] }
    }
    if ($candidates.Count -eq 0) { Fail '未发现已授权的 ADB 设备。请连接 RK3399 并允许 USB 调试。' }
    if ($candidates.Count -eq 1) { $script:Serial = $candidates[0]; return }
    $matches = @()
    foreach ($candidate in $candidates) {
        $platform = (& $Adb -s $candidate shell getprop ro.board.platform 2>$null).Trim()
        $abi = (& $Adb -s $candidate shell getprop ro.product.cpu.abi 2>$null).Trim()
        if ($platform -match 'rk3399' -and $abi -match 'arm64|aarch64') { $matches += $candidate }
    }
    if ($matches.Count -eq 1) { $script:Serial = $matches[0]; return }
    Fail "连接了多个设备，无法唯一识别 RK3399。请使用：powershell -File deploy.ps1 -Serial 序列号"
}

function Enable-Root {
    $debuggable = (Invoke-Adb @('shell','getprop','ro.debuggable') -Quiet).Trim()
    if ($debuggable -eq '1') {
        Invoke-Adb @('root') -AllowFailure | Out-Null
        & $Adb -s $script:Serial wait-for-device | Out-Null
        $id = (Invoke-Adb @('shell','id','-u') -Quiet).Trim()
        if ($id -eq '0') { $script:RootMode = 'adb'; return }
    }
    $su = Invoke-Adb @('shell','su','-c','id -u') -AllowFailure -Quiet
    if (($su -join '') -match '(^|\D)0(\D|$)') { $script:RootMode = 'su'; return }
    Fail '设备没有可用 root。Android 10 建议安装 Magisk；Android 7 userdebug 可使用 adb root。'
}

function Invoke-RootScript([string]$Path) {
    if ($script:RootMode -eq 'adb') { Invoke-Adb @('shell','sh',$Path) | Out-Null }
    else { Invoke-Adb @('shell','su','-c',"sh $Path") | Out-Null }
}

function Push-File([string]$Local, [string]$Remote) {
    if (-not (Test-Path -LiteralPath $Local)) { Fail "缺少部署文件：$Local" }
    Invoke-Adb @('push',$Local,$Remote) | Out-Null
}

function Get-BoundsCenter([System.Xml.XmlElement]$Node) {
    if ($Node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { return $null }
    return @([int](([int]$Matches[1] + [int]$Matches[3]) / 2), [int](([int]$Matches[2] + [int]$Matches[4]) / 2))
}

function Get-UiXml {
    Invoke-Adb @('shell','uiautomator','dump','/sdcard/rk3399-ui.xml') -Quiet | Out-Null
    $temp = Join-Path $env:TEMP 'rk3399-ui.xml'
    Invoke-Adb @('pull','/sdcard/rk3399-ui.xml',$temp) -Quiet | Out-Null
    [xml](Get-Content -LiteralPath $temp -Raw -Encoding UTF8)
}

function Tap-Node([System.Xml.XmlElement]$Node) {
    $p = Get-BoundsCenter $Node
    if (-not $p) { Fail '无法读取控件坐标。' }
    Invoke-Adb @('shell','input','tap',"$($p[0])","$($p[1])") -Quiet | Out-Null
    Start-Sleep -Milliseconds 800
}

function Dismiss-CompatibilityDialog {
    $ui = Get-UiXml
    $button = $ui.SelectSingleNode("//node[@resource-id='android:id/button1' and @package='android']")
    if ($button) { Tap-Node $button; Start-Sleep -Seconds 1 }
}

function Set-PrimitiveSetting([string[]]$Labels, [string]$Value) {
    $ui = Get-UiXml
    $title = $null
    foreach ($label in $Labels) {
        $title = $ui.SelectSingleNode("//node[@resource-id='android:id/title' and @text='$label']")
        if ($title) { break }
    }
    if (-not $title) { Fail "Primitive FTPd 设置页中找不到：$($Labels -join '/')" }
    Tap-Node $title
    $dialog = Get-UiXml
    $edit = $dialog.SelectSingleNode("//node[@resource-id='android:id/edit']")
    if (-not $edit) { Fail 'Primitive FTPd 输入框没有打开。' }
    Tap-Node $edit
    Invoke-Adb @('shell','input','keyevent','123') -Quiet | Out-Null
    $deletes = @('shell','input','keyevent') + (@('67') * 64)
    Invoke-Adb $deletes -Quiet | Out-Null
    Invoke-Adb @('shell','input','text',$Value) -Quiet | Out-Null
    $dialog = Get-UiXml
    $ok = $dialog.SelectSingleNode("//node[@resource-id='android:id/button1']")
    if (-not $ok) { Fail 'Primitive FTPd 确定按钮不存在。' }
    Tap-Node $ok
}

function Configure-PrimitiveUi {
    Invoke-Adb @('shell','am','force-stop','org.primftpd') -Quiet | Out-Null
    Invoke-Adb @('shell','monkey','-p','org.primftpd','1') -Quiet | Out-Null
    Start-Sleep -Seconds 2
    Dismiss-CompatibilityDialog
    $ui = Get-UiXml
    $user = $ui.SelectSingleNode("//node[@resource-id='android:id/title' and (@text='用户名' or @text='Username')]")
    if (-not $user) {
        $gear = $ui.SelectSingleNode("//node[@content-desc='⚙']")
        if (-not $gear) { Fail '无法自动进入 Primitive FTPd 设置页。' }
        Tap-Node $gear
    }
    Set-PrimitiveSetting @('用户名','Username') 'admin'
    Set-PrimitiveSetting @('密码','Password') 'admin'
    $ui = Get-UiXml
    $start = $ui.SelectSingleNode("//node[@resource-id='org.primftpd:id/menu_start']")
    if ($start) {
        Tap-Node $start
        Start-Sleep -Seconds 2
        $grantUi = Get-UiXml
        $grant = $grantUi.SelectSingleNode("//node[contains(translate(@text,'abcdefghijklmnopqrstuvwxyz','ABCDEFGHIJKLMNOPQRSTUVWXYZ'),'GRANT') or @text='允许' or @text='授权']")
        if ($grant) { Tap-Node $grant }
    }
}

function Show-Status {
    Write-Host "`n========== RK3399 NAS 状态 ==========" -ForegroundColor Cyan
    Invoke-RootScript "$Stage/status.sh"
    Write-Host 'LAN 直连固定地址：192.168.1.1'
    Write-Host 'Samba: \\设备IP\NAS   HTTP: http://设备IP:3923'
    Write-Host 'FTP: 设备IP:12345   SFTP: 设备IP:1234   OpenSpeedTest: http://设备IP:3000'
}

Select-Device
Write-Host "目标设备：$Serial" -ForegroundColor Cyan
Invoke-Adb @('wait-for-device') -Quiet | Out-Null
Enable-Root
Write-Host "Root 模式：$RootMode"

Invoke-Adb @('shell','mkdir','-p',$Stage) -Quiet | Out-Null
$deviceFiles = @(
    'nas_services.sh','ethernet_role.sh','openspeedtest_guard.sh','rk3399-nas-magisk.sh',
    'nas-services.rc','ethernet-role.rc','openspeedtest-autostart.rc','smb.conf','copyparty.conf',
    'dnsmasq-eth0.conf','install_device.sh','configure_primitiveftp.sh','install_boot.sh',
    'primitiveftp_prefs.xml','status.sh','uninstall.sh'
)
foreach ($name in $deviceFiles) { Push-File (Join-Path $Device $name) "$Stage/$name" }

if ($VerifyOnly) { Show-Status; exit 0 }

Push-File (Join-Path $Payload 'alpine-nas-ready.tar') "$Stage/alpine-nas-ready.tar"
Write-Host "`n[1/5] 安装离线 Samba、HTTP 和自动 WAN/LAN..." -ForegroundColor Green
Invoke-RootScript "$Stage/install_device.sh"

Write-Host "`n[2/5] 安装 FTP/SFTP 与 OpenSpeedTest APK..." -ForegroundColor Green
Invoke-Adb @('install','-r','-g',(Join-Path $Payload 'primitiveFTPd-7.5.apk')) | Out-Null
$ost = @('install-multiple','-r','-g',
    (Join-Path $Payload 'openspeedtest-base.apk'),
    (Join-Path $Payload 'openspeedtest-en.apk'),
    (Join-Path $Payload 'openspeedtest-xhdpi.apk'),
    (Join-Path $Payload 'openspeedtest-zh.apk'))
Invoke-Adb $ost | Out-Null
Invoke-Adb @('shell','monkey','-p','com.openspeedtest.server','1') -Quiet | Out-Null
Start-Sleep -Seconds 2
Dismiss-CompatibilityDialog
Invoke-Adb @('shell','am','force-stop','com.openspeedtest.server') -Quiet | Out-Null
Invoke-Adb @('shell','pm','grant','org.primftpd','android.permission.READ_EXTERNAL_STORAGE') -AllowFailure -Quiet | Out-Null
Invoke-Adb @('shell','pm','grant','org.primftpd','android.permission.WRITE_EXTERNAL_STORAGE') -AllowFailure -Quiet | Out-Null

Write-Host "`n[3/5] 固化 FTP/SFTP 端口、目录、开机启动和账号..." -ForegroundColor Green
Invoke-Adb @('shell','monkey','-p','org.primftpd','1') -Quiet | Out-Null
Start-Sleep -Seconds 2
Invoke-Adb @('shell','am','force-stop','org.primftpd') -Quiet | Out-Null
Invoke-RootScript "$Stage/configure_primitiveftp.sh"
Configure-PrimitiveUi

Write-Host "`n[4/5] 安装开机自启钩子..." -ForegroundColor Green
if ($RootMode -eq 'adb') {
    Invoke-Adb @('remount') -AllowFailure | Out-Null
}
Invoke-RootScript "$Stage/install_boot.sh"

Write-Host "`n[5/5] 完成部署。" -ForegroundColor Green
if (-not $NoReboot) {
    Write-Host '正在重启并等待服务启动...'
    Invoke-Adb @('reboot') -Quiet | Out-Null
    & $Adb -s $Serial wait-for-device | Out-Null
    Start-Sleep -Seconds 35
}
Show-Status
Write-Host "`n账号：admin    密码：admin" -ForegroundColor Yellow
