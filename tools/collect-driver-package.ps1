# ============================================================
#  collect-driver-package.ps1
#  从本机 Windows 驱动仓库 (DriverStore) 里，把某个已安装的
#  打印机驱动包整包导出成 driver.zip（供 build\build.ps1 内置）。
#  仅列出 Class=Printer 的驱动包，非管理员也可运行。
#
#  用法:
#    powershell -ExecutionPolicy Bypass -File tools\collect-driver-package.ps1
#        → 列出所有打印机驱动包，输入编号导出到当前目录 driver.zip
#    powershell ... -List
#        → 只看列表
#    powershell ... -Export su2emchs.inf  [-Output D:\driver.zip]
#        → 按 INF 文件名或包目录名直接导出
# ============================================================
param(
    [switch]$List,
    [string]$Export = '',
    [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = 'C:\Windows\System32\DriverStore\FileRepository'
$pkgs = @()
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
    $models = @()
    foreach ($m in [regex]::Matches($txt, '"([^"\r\n]{4,80}?(?:PCL6|PCL5|PCL|PS|PostScript))"')) {
        $models += $m.Groups[1].Value.Trim()
    }
    $models = @($models | Sort-Object -Unique | Select-Object -First 4)
    $sizeMB = [math]::Round(((Get-ChildItem -LiteralPath $dir.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
    $pkgs += [pscustomobject]@{ Folder = $dir.FullName; Name = $dir.Name; Inf = $infF.Name; Models = $models; HasModels = [int]($models.Count -gt 0); SizeMB = $sizeMB }
}
$pkgs = @($pkgs | Sort-Object -Property @{ Expression = 'HasModels'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })

if ($pkgs.Count -eq 0) { Write-Host '本机驱动仓库里没有找到打印机驱动包。'; exit 1 }

if ($List) {
    $i = 0
    foreach ($p in $pkgs) {
        $i++
        $ex = (@($p.Models) | Select-Object -First 3) -join ' / '
        if (-not $ex) { $ex = '(系统组件/无型号信息)' }
        Write-Host ("[{0}] {1}  ({2} MB)  {3}" -f $i, $p.Name, $p.SizeMB, $ex)
    }
    exit 0
}

if (-not $Export) {
    Write-Host '本机驱动仓库中的打印机驱动包:'
    $i = 0
    foreach ($p in $pkgs) {
        $i++
        $ex = (@($p.Models) | Select-Object -First 3) -join ' / '
        if (-not $ex) { $ex = '(系统组件/无型号信息)' }
        Write-Host ("  [{0}] {1}  ({2} MB)  {3}" -f $i, $p.Name, $p.SizeMB, $ex)
    }
    $sel = Read-Host '输入要导出的编号（直接回车取消）'
    if (-not $sel) { Write-Host '已取消'; exit 0 }
    $idx = 0
    try { $idx = [int]$sel - 1 } catch { Write-Host '编号无效'; exit 1 }
    if ($idx -lt 0 -or $idx -ge $pkgs.Count) { Write-Host '编号无效'; exit 1 }
    $pkg = $pkgs[$idx]
} else {
    $pkg = $pkgs | Where-Object { $_.Name -eq $Export -or $_.Inf -eq $Export } | Select-Object -First 1
    if (-not $pkg) { $pkg = @($pkgs | Where-Object { $_.Name -like ('*' + $Export + '*') })[0] }
    if (-not $pkg) { Write-Host ('没找到匹配的驱动包: ' + $Export); exit 1 }
}

if (-not $Output) { $Output = Join-Path (Get-Location).Path 'driver.zip' }
if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($pkg.Folder, $Output, [IO.Compression.CompressionLevel]::Optimal, $false)
Write-Host ''
Write-Host ("已导出: {0}  ({1:N1} MB)" -f $Output, ((Get-Item -LiteralPath $Output).Length / 1MB))
Write-Host '把它放到仓库根目录后运行 build\build.ps1，即可生成内置驱动的 EXE。'
