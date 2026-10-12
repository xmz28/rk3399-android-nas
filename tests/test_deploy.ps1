# Mock ADB only. This script never invokes a device or the real adb executable.
$ErrorActionPreference = 'Stop'
$taskSource = Split-Path -Parent $PSScriptRoot
$taskTemp = Join-Path ([IO.Path]::GetTempPath()) ('rk3399-deploy-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemp | Out-Null
$taskLog = Join-Path $taskTemp 'adb.log'
$taskFake = Join-Path $taskTemp 'fake-adb.ps1'
$taskOldLog = $env:RK_NAS_TEST_ADB_LOG
$taskOldMode = $env:RK_NAS_TEST_ADB_MODE
$taskFakeCode = @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$taskArguments)
[IO.File]::AppendAllText($env:RK_NAS_TEST_ADB_LOG, ($taskArguments -join ' ') + "`n")
$global:LASTEXITCODE = 0
$taskCommand = $taskArguments -join ' '
if ($taskCommand -match 'ro.board.platform') {
    if ($env:RK_NAS_TEST_ADB_MODE -eq 'wrong') { 'other-platform' } else { 'rk3399' }
} elseif ($taskCommand -match 'ro.product.cpu.abi') { 'arm64-v8a' }
elseif ($taskCommand -match 'id -u') { '0' }
elseif ($taskArguments[0] -eq 'devices') { "List of devices attached`nTESTBOARD device`nTESTPHONE device" }
elseif ($taskCommand -match 'preflight.sh') { 'PREFLIGHT=PASS' }
'@
[IO.File]::WriteAllText($taskFake,$taskFakeCode,[Text.UTF8Encoding]::new($false))
$env:RK_NAS_TEST_ADB_LOG = $taskLog
try {
    $env:RK_NAS_TEST_ADB_MODE = 'wrong'
    $taskRejected = $false
    try { & (Join-Path $taskSource 'deploy.ps1') -Serial TESTPHONE -AdbPath $taskFake -CheckOnly }
    catch { if ($_.Exception.Message -match 'Target must be') { $taskRejected = $true } else { throw } }
    if (-not $taskRejected) { throw 'Wrong device was not rejected.' }
    if ((Get-Content $taskLog -Raw) -match 'push|mkdir|install|reboot') { throw 'Wrong device received mutations.' }
    'WRONG_TARGET_REJECTED=PASS'
    [IO.File]::WriteAllText($taskLog,'')
    $env:RK_NAS_TEST_ADB_MODE = 'board'
    & (Join-Path $taskSource 'deploy.ps1') -Serial TESTBOARD -AdbPath $taskFake -CheckOnly
    $taskTrace = Get-Content $taskLog -Raw
    if ($taskTrace -notmatch 'sh /data/local/tmp/rk3399-deploy-v2/preflight.sh') { throw 'Preflight was not run.' }
    if ($taskTrace -match 'install_device|reboot| install ') { throw 'CheckOnly triggered installation.' }
    'CHECK_ONLY_SKIPS_INSTALL=PASS'
    [IO.File]::WriteAllText($taskLog,'')
    & (Join-Path $taskSource 'deploy.ps1') -Serial TESTBOARD -AdbPath $taskFake -Fresh -CheckOnly
    $taskTrace = Get-Content $taskLog -Raw
    if ($taskTrace -notmatch 'preflight.sh --fresh') { throw 'Fresh inspection used upgrade checks.' }
    if ($taskTrace -match 'install_fresh|credentials.json| install |reboot') { throw 'Fresh CheckOnly triggered installation or credential transfer.' }
    'FRESH_CHECK_ONLY_SKIPS_INSTALL=PASS'
} finally {
    $env:RK_NAS_TEST_ADB_LOG = $taskOldLog
    $env:RK_NAS_TEST_ADB_MODE = $taskOldMode
    # Preserve the small trace under the system temp directory for inspection.
    "MOCK_TRACE=$taskTemp"
}
