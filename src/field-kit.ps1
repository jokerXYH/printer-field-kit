# ============================================================
#  打印机现场助手  (Printer Field Kit)
#  用途: 扫描当前所处的本地网络, 自动发现网络打印机,
#        自动匹配本机已有驱动, 自动创建端口 + 打印机队列.
#  运行: 建议双击打包好的 EXE. 也支持 -TestDescr 做匹配自检.
#  自动模式: 存在 C:\ProgramData\PrinterFieldKit\silent.mode 时静默运行,
#            不弹窗、只写日志、只处理 SHARP 机型.
# ============================================================
param([string]$TestDescr = '')

$ErrorActionPreference = 'Continue'
$script:logLines = New-Object System.Collections.Generic.List[string]
$KitDir  = 'C:\ProgramData\PrinterFieldKit'
$LogFile = Join-Path $KitDir 'field-kit.log'
$Silent  = Test-Path (Join-Path $KitDir 'silent.mode')
$NameFormat = '{0} ({1})'
$SilentVendorOnly = 'SHARP'

function W([string]$s) {
    $script:logLines.Add(("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $s)) | Out-Null
    if (-not $Silent) { Write-Host $s }
}
function Get-ModelToken([string]$n) { ($n -replace '\s*(PCL6|PCL5|PCL|PS|PostScript)\s*$', '').Trim() }

function Get-DriverMenu {
    $list = @()
    foreach ($d in (Get-PrinterDriver -ErrorAction SilentlyContinue)) {
        if ($d.Name -notlike '*Microsoft*' -and $d.Name -notlike '*Generic*') {
            $list += [pscustomobject]@{ Name = $d.Name; Inf = $null }
        }
    }
    try {
        $root = 'C:\Windows\System32\DriverStore\FileRepository'
        foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $infF = Get-ChildItem -LiteralPath $dir.FullName -Filter '*.inf' -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $infF) { continue }
            $txt = ''
            try {
                $bytes = [IO.File]::ReadAllBytes($infF.FullName)
                if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                    $txt = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
                } else {
                    $txt = [Text.Encoding]::GetEncoding(1252).GetString($bytes)
                }
            } catch { continue }
            if ($txt -notmatch '(?im)^\s*Class\s*=\s*Printer') { continue }
            foreach ($m in [regex]::Matches($txt, '"([^"\r\n]{4,80}?(?:PCL6|PCL5|PCL|PS|PostScript))"')) {
                $nm = $m.Groups[1].Value.Trim()
                if ($nm -match 'CD-ROM|Driver CD') { continue }
                $list += [pscustomobject]@{ Name = $nm; Inf = $infF.FullName }
            }
        }
    } catch { }
    # 去重(优先保留带 Inf 的)
    if ($list.Count -eq 0) { return @() }
    $map = @{}
    foreach ($d in $list) {
        if (-not $map.ContainsKey($d.Name)) { $map[$d.Name] = $d }
        elseif (-not $map[$d.Name].Inf -and $d.Inf) { $map[$d.Name] = $d }
    }
    return @($map.Values)
}

function Select-DriverFor([string]$text, $menu) {
    if (-not $text -or $text.Trim().Length -eq 0) { return $null }
    $norm = ($text.ToUpper() -replace '\s', '')
    $cands = @()
    foreach ($d in $menu) {
        $t = ((Get-ModelToken $d.Name).ToUpper() -replace '\s', '')
        if ($t.Length -ge 4 -and $norm.Contains($t)) {
            $cands += [pscustomobject]@{ D = $d; Score = $t.Length; Prefer = [int]($d.Name -match 'PCL6') }
        }
    }
    if ($cands.Count -eq 0) { return $null }
    $best = $cands | Sort-Object -Property @{ Expression = 'Prefer'; Descending = $true }, @{ Expression = 'Score'; Descending = $true } | Select-Object -First 1
    return $best.D
}

function Get-SnmpSysDescr([string]$IP, [string]$Community = 'public', [int]$TimeoutMs = 1200) {
    try {
        $oid = @(1, 3, 6, 1, 2, 1, 1, 1, 0)
        $oidB = New-Object System.Collections.Generic.List[byte]
        $oidB.Add([byte](40 * $oid[0] + $oid[1]))
        foreach ($v in $oid[2..($oid.Count - 1)]) { $oidB.Add([byte]$v) }
        $vbBody = New-Object System.Collections.Generic.List[byte]
        $vbBody.Add([byte]0x06); $vbBody.Add([byte]$oidB.Count)
        foreach ($x in $oidB) { $vbBody.Add($x) }
        $vbBody.Add(0x05); $vbBody.Add(0x00)
        $vb = New-Object System.Collections.Generic.List[byte]
        $vb.Add([byte]0x30); $vb.Add([byte]$vbBody.Count)
        foreach ($x in $vbBody) { $vb.Add($x) }
        $vblBody = New-Object System.Collections.Generic.List[byte]
        $vblBody.Add([byte]0x30); $vblBody.Add([byte]$vb.Count)
        foreach ($x in $vb) { $vblBody.Add($x) }
        $pduBody = New-Object System.Collections.Generic.List[byte]
        foreach ($x in @(0x02, 0x01, 0x01, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00)) { $pduBody.Add([byte]$x) }
        foreach ($x in $vblBody) { $pduBody.Add($x) }
        $pdu = New-Object System.Collections.Generic.List[byte]
        $pdu.Add([byte]0xA0); $pdu.Add([byte]$pduBody.Count)
        foreach ($x in $pduBody) { $pdu.Add($x) }
        $commB = [Text.Encoding]::ASCII.GetBytes($Community)
        $msgBody = New-Object System.Collections.Generic.List[byte]
        foreach ($x in @(0x02, 0x01, 0x01)) { $msgBody.Add([byte]$x) }
        $msgBody.Add([byte]0x04); $msgBody.Add([byte]$commB.Count)
        foreach ($x in $commB) { $msgBody.Add($x) }
        foreach ($x in $pdu) { $msgBody.Add($x) }
        $msg = New-Object System.Collections.Generic.List[byte]
        $msg.Add([byte]0x30); $msg.Add([byte]$msgBody.Count)
        foreach ($x in $msgBody) { $msg.Add($x) }
        $req = $msg.ToArray()
        $u = New-Object System.Net.Sockets.UdpClient
        $u.Client.ReceiveTimeout = $TimeoutMs
        $u.Connect($IP, 161)
        $u.Send($req, $req.Length) | Out-Null
        $rem = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $u.Receive([ref]$rem)
        $u.Close()
    } catch { return $null }
    # 从响应中提取最长的可打印 OCTET STRING (即 sysDescr)
    $best = $null
    for ($i = 0; $i -lt $resp.Length - 2; $i++) {
        if ($resp[$i] -ne 0x04) { continue }
        $len = [int]$resp[$i + 1]; $hdr = 2
        if ($len -gt 127) {
            if ($len -eq 0x81 -and ($i + 3) -le $resp.Length) { $len = [int]$resp[$i + 2]; $hdr = 3 } else { continue }
        }
        if ($len -lt 8) { continue }
        if (($i + $hdr + $len) -gt $resp.Length) { continue }
        $s = [Text.Encoding]::ASCII.GetString($resp, $i + $hdr, $len)
        if ($s -match '^[\x20-\x7E\r\n\t]+$') { if (-not $best -or $s.Length -gt $best.Length) { $best = $s } }
    }
    return $best
}

function Done([string]$summary, [bool]$ok) {
    try {
        New-Item -ItemType Directory -Force -Path $KitDir | Out-Null
        Add-Content -Path $LogFile -Value (("`r`n===== {0} =====" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) + "`r`n" + ($script:logLines -join "`r`n")) -Encoding UTF8
    } catch { }
    if ($Silent) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $icon = if ($ok) { 'Information' } else { 'Warning' }
        [System.Windows.Forms.MessageBox]::Show(($summary + "`r`n`r`n日志: " + $LogFile), '打印机现场助手', 'OK', $icon) | Out-Null
    } catch { Write-Host $summary }
}

# ---------- 驱动菜单(自检模式也用到) ----------
$menu = Get-DriverMenu

# ---------- 自检模式: 只测试型号匹配逻辑 ----------
if ($TestDescr) {
    Write-Host ("驱动菜单: {0} 个型号" -f @($menu).Count)
    $sel = Select-DriverFor $TestDescr $menu
    if ($sel) { Write-Host ("输入 [{0}]  =>  匹配 [{1}]" -f $TestDescr, $sel.Name) }
    else { Write-Host ("输入 [{0}]  =>  无匹配" -f $TestDescr) }
    exit
}

# ---------- 管理员检查 / 自动提权 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($Silent) {
        $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '"'
    } else {
        $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    }
    try {
        Start-Process powershell -Verb RunAs -ArgumentList $argLine -Wait -ErrorAction Stop
    } catch {
        if (-not $Silent) {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show('已取消（需要管理员权限才能安装打印机）。', '打印机现场助手', 'OK', 'Warning') | Out-Null
            } catch { }
        }
    }
    exit
}

# ============ 主流程 ============
W ("开始 (silent=$Silent, user=$env:USERNAME, pc=$env:COMPUTERNAME)")
if ($Silent) { W '自动模式: 只处理 SHARP 机型, 静默运行' }

# 1) 确保内置驱动包在系统驱动仓库中
$srcDir = Split-Path -Parent $PSCommandPath
$zip = Join-Path $srcDir 'driver.zip'
if (Test-Path $zip) {
    try {
        $ex = Join-Path $env:TEMP ('pfk_drv_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force -ErrorAction Stop
        $inf = Get-ChildItem -LiteralPath $ex -Recurse -Filter '*.inf' | Select-Object -First 1
        if ($inf) {
            $po = & pnputil.exe /add-driver $inf.FullName /install 2>&1 | Out-String
            $po = (($po -replace "`r?`n", ' ') -replace '\s+', ' ').Trim()
            if ($po.Length -gt 220) { $po = $po.Substring(0, 220) + '...' }
            W ('驱动包: ' + $po)
        }
    } catch { W ("驱动包处理失败: " + $_.Exception.Message) }
}
W ("驱动菜单: {0} 个型号可用" -f @($menu).Count)

# 2) 找活动网段
$subnets = @()
foreach ($a in (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254)' -and $_.PrefixOrigin -ne 'WellKnown' })) {
    $p = $a.IPAddress.Split('.')
    $subnets += "$($p[0]).$($p[1]).$($p[2])."
}
$subnets = @($subnets | Sort-Object -Unique | Select-Object -First 3)
if ($subnets.Count -eq 0) { Done '没有检测到活动网络连接。' $false; exit }
W ('扫描网段: ' + ($subnets -join ', '))

# 3) 扫描打印端口 (9100/631/515)
$hits = @{}
foreach ($sn in $subnets) {
    foreach ($port in @(9100, 631, 515)) {
        $jobs = @()
        foreach ($i in 1..254) {
            $tip = "$sn$i"
            $c = New-Object System.Net.Sockets.TcpClient
            $ar = $c.BeginConnect($tip, $port, $null, $null)
            $jobs += [pscustomobject]@{ IP = $tip; C = $c }
        }
        Start-Sleep -Milliseconds 1500
        foreach ($j in $jobs) {
            if ($j.C.Connected) {
                if (-not $hits.ContainsKey($j.IP)) { $hits[$j.IP] = New-Object System.Collections.Generic.List[int] }
                $hits[$j.IP].Add($port)
            }
            $j.C.Close()
        }
    }
}
W ("扫描完成: 发现 {0} 台候选设备" -f $hits.Keys.Count)

# 4) 逐台识别 + 安装
$installed = @(); $skipped = @(); $problems = @()
foreach ($ip in ($hits.Keys | Sort-Object { [version]$_ })) {
    $ports = (($hits[$ip] | Sort-Object) -join ',')
    $descr = ''
    foreach ($comm in @('public', 'private', 'sharp')) {
        $d = Get-SnmpSysDescr -IP $ip -Community $comm
        if ($d) { $descr = $d; break }
    }
    $title = ''
    try {
        $r = Invoke-WebRequest -Uri "http://$ip/" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        if ($r.Content -match '(?s)<title>\s*(.*?)\s*</title>') { $title = $Matches[1] }
    } catch { }
    $all = ($descr + ' ' + $title).Trim()
    if (-not $all) { W "跳过 ${ip}: 无法识别型号 (端口: $ports)"; $problems += "$ip 无法识别型号"; continue }
    W "设备 ${ip}: [$descr] [$title]"
    $sel = Select-DriverFor $all $menu
    if (-not $sel) { W "跳过 ${ip}: 无可用驱动 (识别文本: $all)"; $problems += "$ip ($descr) 没有可用驱动"; continue }
    if ($Silent -and $sel.Name -notmatch $SilentVendorOnly) { W "静默模式跳过非 $SilentVendorOnly : $($sel.Name)"; continue }
    $exists = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -eq $ip })
    if ($exists.Count -gt 0) { W "跳过 ${ip}: 已有打印机队列「$($exists[0].Name)」"; $skipped += "$ip 已有「$($exists[0].Name)」"; continue }
    try {
        if (-not (Get-PrinterDriver -Name $sel.Name -ErrorAction SilentlyContinue)) {
            try { Add-PrinterDriver -Name $sel.Name -ErrorAction Stop }
            catch {
                if ($sel.Inf) { Add-PrinterDriver -Name $sel.Name -InfPath $sel.Inf -ErrorAction Stop }
                else { throw }
            }
        }
        if (-not (Get-PrinterPort -Name $ip -ErrorAction SilentlyContinue)) {
            Add-PrinterPort -Name $ip -PrinterHostAddress $ip -PortNumber 9100 -ErrorAction Stop
        }
        $short = (Get-ModelToken $sel.Name).Split(' ')[-1]
        $qname = $NameFormat -f $short, $ip
        Add-Printer -Name $qname -DriverName $sel.Name -PortName $ip -ErrorAction Stop
        W "已安装: 「$qname」 驱动=$($sel.Name)"
        $installed += "「$qname」  驱动: $($sel.Name)"
    } catch { W "安装失败 ${ip}: $($_.Exception.Message)"; $problems += "$ip 安装失败: $($_.Exception.Message)" }
}

# 5) 汇总
$s = ''
if ($installed.Count) { $s += "已自动安装 $($installed.Count) 台打印机:`r`n  " + ($installed -join "`r`n  ") }
if ($skipped.Count)   { if ($s) { $s += "`r`n`r`n" }; $s += "已存在跳过 $($skipped.Count) 台:`r`n  " + ($skipped -join "`r`n  ") }
if ($problems.Count)  { if ($s) { $s += "`r`n`r`n" }; $s += "未能处理 $($problems.Count) 台:`r`n  " + ($problems -join "`r`n  ") }
if (-not $s) { $s = '本网络没有发现打印机。' }
W '结束'
Done $s $true
