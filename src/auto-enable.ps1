# ============================================================
#  开启自动模式: 部署主程序到 C:\ProgramData\PrinterFieldKit,
#  并注册计划任务 (连网/登录时自动扫描安装打印机)
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
            [System.Windows.Forms.MessageBox]::Show('已取消（需要管理员权限才能开启）。', '打印机现场助手 - 自动模式', 'OK', 'Warning') | Out-Null
        } catch { }
    }
    exit
}

$srcDir = Split-Path -Parent $PSCommandPath
$exeSrc = Join-Path $srcDir '打印机现场助手.exe'
if (-not (Test-Path -LiteralPath $exeSrc)) {
    MsgOk "没找到「打印机现场助手.exe」。`r`n请把本文件（开启自动模式.bat 和 auto-enable.ps1）和 exe 放在同一个文件夹里再运行。"
    exit
}

$kit = 'C:\ProgramData\PrinterFieldKit'
New-Item -ItemType Directory -Force -Path $kit | Out-Null
Copy-Item -LiteralPath $exeSrc -Destination (Join-Path $kit 'PrinterFieldKit.exe') -Force
Set-Content -Path (Join-Path $kit 'silent.mode') -Value 'auto' -Encoding ASCII -Force

$sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$xml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Printer Field Kit: auto scan and install printers on network change</Description>
    <URI>\PrinterFieldKit-AutoScan</URI>
  </RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"&gt;&lt;Select Path="Microsoft-Windows-NetworkProfile/Operational"&gt;*[System[EventID=10000]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT20S</Delay>
    </EventTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT45S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>__SID__</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\ProgramData\PrinterFieldKit\PrinterFieldKit.exe</Command>
    </Exec>
  </Actions>
</Task>
'@
$xml = $xml.Replace('__SID__', $sid)

try {
    Register-ScheduledTask -TaskName 'PrinterFieldKit-AutoScan' -Xml $xml -Force -ErrorAction Stop | Out-Null
    MsgOk "已开启自动模式！`r`n`r`n以后每当连接新网络 / 登录电脑，约 20~45 秒后会自动扫描并安装打印机。`r`n（静默运行，只处理夏普机型；已装过的会自动跳过）`r`n`r`n日志: C:\ProgramData\PrinterFieldKit\field-kit.log`r`n`r`n想关闭时双击「关闭自动模式.bat」。"
} catch {
    MsgOk "开启失败: $($_.Exception.Message)"
}
