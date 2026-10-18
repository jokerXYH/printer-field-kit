# ============================================================
#  build.ps1 - 打包「打印机现场助手」
#  用法: powershell -ExecutionPolicy Bypass -File build\build.ps1 [-DriverZip <路径>]
#  产物: dist\打印机现场助手.exe + 自动模式开关脚本
#  说明: 若仓库根目录存在 driver.zip（或用 -DriverZip 指定），会一并打入 EXE
# ============================================================
param(
    [string]$DriverZip = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$srcDir   = Join-Path $repoRoot 'src'
$distDir  = Join-Path $repoRoot 'dist'
$workDir  = Join-Path $env:TEMP ('pfk_build_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$payload  = Join-Path $workDir 'payload'

function Write-Normalized([string]$path, [string]$mode) {
    $c = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) -replace "`r?`n", "`r`n"
    if ($mode -eq 'bom') { [IO.File]::WriteAllText($path, $c, (New-Object Text.UTF8Encoding($true))) }
    else { [IO.File]::WriteAllText($path, $c, [Text.Encoding]::ASCII) }
}

Write-Host '[1/5] 检查环境...'
$iex = Join-Path $env:SystemRoot 'System32\iexpress.exe'
if (-not (Test-Path $iex)) { throw '找不到 IExpress (iexpress.exe)，无法打包' }
foreach ($f in @('launch.bat', 'field-kit.ps1')) {
    if (-not (Test-Path (Join-Path $srcDir $f))) { throw "缺少源文件: src\$f" }
}

Write-Host '[2/5] 准备打包内容...'
New-Item -ItemType Directory -Force -Path $payload | Out-Null
Copy-Item (Join-Path $srcDir 'launch.bat')    (Join-Path $payload 'launch.bat')    -Force
Copy-Item (Join-Path $srcDir 'field-kit.ps1') (Join-Path $payload 'field-kit.ps1') -Force
Write-Normalized (Join-Path $payload 'launch.bat')    'ascii'
Write-Normalized (Join-Path $payload 'field-kit.ps1') 'bom'

if (-not $DriverZip) { $DriverZip = Join-Path $repoRoot 'driver.zip' }
$hasDriver = $false
if (Test-Path -LiteralPath $DriverZip) {
    Copy-Item -LiteralPath $DriverZip (Join-Path $payload 'driver.zip') -Force
    $hasDriver = $true
    Write-Host ("      内置驱动包: {0} ({1:N1} MB)" -f $DriverZip, ((Get-Item -LiteralPath $DriverZip).Length / 1MB))
} else {
    Write-Host '      未提供 driver.zip：生成不含内置驱动的版本（运行时使用本机已有驱动）'
}

Write-Host '[3/5] 生成打包配置...'
$target = Join-Path $workDir 'PrinterFieldKit.exe'
$fileStrings = @('FILE0="launch.bat"', 'FILE1="field-kit.ps1"')
$fileLines   = @('%FILE0%=', '%FILE1%=')
if ($hasDriver) {
    $fileStrings += 'FILE2="driver.zip"'
    $fileLines   += '%FILE2%='
}

$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$target
FriendlyName=Printer Field Kit
AppLaunched=cmd /c launch.bat
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
$($fileStrings -join "`r`n")
[SourceFiles]
SourceFiles0=$payload\
[SourceFiles0]
$($fileLines -join "`r`n")
"@
$sedPath = Join-Path $workDir 'build.sed'
[IO.File]::WriteAllText($sedPath, ($sed -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)

Write-Host '[4/5] 打包 EXE（可能需要 10~60 秒）...'
& $iex /N $sedPath | Out-Null
if (-not (Test-Path $target)) { cmd /c "$iex /N $sedPath" | Out-Null }
if (-not (Test-Path $target)) { throw '打包失败：IExpress 未生成 EXE' }
Write-Host ("      生成: {0:N1} MB" -f ((Get-Item $target).Length / 1MB))

Write-Host '[5/5] 组装 dist 目录...'
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Copy-Item $target (Join-Path $distDir '打印机现场助手.exe') -Force
foreach ($f in @('auto-enable.ps1', 'auto-disable.ps1', '开启自动模式.bat', '关闭自动模式.bat')) {
    $srcF = Join-Path $srcDir $f
    if (Test-Path $srcF) {
        Copy-Item $srcF (Join-Path $distDir $f) -Force
        if ($f.EndsWith('.ps1')) { Write-Normalized (Join-Path $distDir $f) 'bom' }
        else { Write-Normalized (Join-Path $distDir $f) 'ascii' }
    }
}
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "打包完成！产物目录: $distDir"
Get-ChildItem $distDir | ForEach-Object { Write-Host ('  - ' + $_.Name) }
