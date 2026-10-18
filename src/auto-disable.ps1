# ============================================================
#  关闭自动模式: 注销计划任务并移除自动标记
# ============================================================
$ErrorActionPreference = 'Continue'

function MsgOk([string]$t) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show($t, '打印机现场助手 - 自动模式', 'OK', 'Information') | Out-Null
    } catch { Write-Host $t }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '"'
    try { Start-Process powershell -Verb RunAs -ArgumentList $argLine -Wait -ErrorAction Stop }
    catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show('已取消（需要管理员权限才能关闭）。', '打印机现场助手 - 自动模式', 'OK', 'Warning') | Out-Null
        } catch { }
    }
    exit
}

Unregister-ScheduledTask -TaskName 'PrinterFieldKit-AutoScan' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\PrinterFieldKit\silent.mode' -Force -ErrorAction SilentlyContinue
MsgOk "已关闭自动模式。`r`n`r`n（已经装好的打印机不受影响；以后想手动扫描，双击「打印机现场助手.exe」即可。）"
