# setup-wsl.ps1 —— Windows 侧环境检查与准备
#
# 用法（在 Windows PowerShell 里）：
#   powershell -ExecutionPolicy Bypass -File scripts\windows\setup-wsl.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\windows\setup-wsl.ps1 -WriteWslConfig
#
# 它只做「检查 + 提示」，默认不改任何东西。
# 加 -WriteWslConfig 才会创建 %USERPROFILE%\.wslconfig（防 WSL 被空闲回收）。

param(
  [switch]$WriteWslConfig
)

$ErrorActionPreference = "Continue"
$out = @()

function Line($t) { $script:out += $t }

Line "════════ 1. 基本环境 ════════"

# WSL
# 注意：wsl.exe 输出是 UTF-16，PowerShell 捕获后可能夹带 NUL 字节，
# 直接输出会让内容看起来"断行/乱码"，这里统一剥掉。
$wsl = (wsl.exe -l -v 2>&1 | Out-String) -replace "`0", ""
Line "WSL 发行版:"
$wsl -split "`n" | ForEach-Object { if ($_.Trim()) { Line "   $($_.Trim())" } }

# CPU / 内存 / 磁盘
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Line ("CPU: {0} ({1} 核 / {2} 线程)" -f $cpu.Name, $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
$os = Get-CimInstance Win32_OperatingSystem
Line ("内存: 总 {0:N1} GB / 可用 {1:N1} GB" -f ($os.TotalVisibleMemorySize/1MB), ($os.FreePhysicalMemory/1MB))
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -in @('C','D','E') } | ForEach-Object {
  Line ("磁盘 {0}: 剩余 {1:N1} GB" -f $_.Name, ($_.Free/1GB))
}

Line ""
Line "════════ 2. ESP32 USB 设备 ════════"
$usb = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like "*303A*" }
if ($usb) {
  $usb | ForEach-Object { Line ("   {0,-8} | {1,-12} | {2}" -f $_.Status, $_.Class, $_.FriendlyName) }
} else {
  Line "   (未发现 VID_303A 设备 —— 板子没插或线是纯充电线)"
}

Line ""
Line "════════ 3. usbipd-win（USB 直通给 WSL，烧录用）════════"
$usbipd = "C:\Program Files\usbipd-win\usbipd.exe"
if (Test-Path $usbipd) {
  Line "   已安装: $usbipd"
  Line "   （烧录前用它把板子 USB 共享给 WSL，见 docs/Windows复现指南.md）"
} else {
  Line "   ❌ 未安装。烧录固件需要它：winget install usbipd"
}

Line ""
Line "════════ 4. .wslconfig（防止发行版被空闲回收）════════"
$cfgPath = "$env:USERPROFILE\.wslconfig"
if (Test-Path $cfgPath) {
  Line "   已存在 $cfgPath :"
  # 必须显式指定 UTF8：PS 5.1 默认按 ANSI 读，会让中文注释变乱码
  (Get-Content $cfgPath -Encoding UTF8) | ForEach-Object { Line "     $_" }
} else {
  Line "   不存在。建议创建（否则 WSL 空闲会被回收，Host 一起断）："
  Line "   [wsl2]"
  Line "   instanceIdleTimeout=-1"
  Line ""
  if ($WriteWslConfig) {
    "[wsl2]`ninstanceIdleTimeout=-1" | Out-File -FilePath $cfgPath -Encoding ascii
    Line "   ✅ 已写入 $cfgPath（重启 WSL 生效：wsl --shutdown）"
  } else {
    Line "   （本次未写入。要写就重跑并加 -WriteWslConfig）"
  }
}

Line ""
Line "════════ 5. 结论 ════════"
Line "   以上检查通过后，进入 WSL 执行："
Line "     bash scripts/wsl/apply-patches.sh     # 编译 Host（补丁已内置，会自动跳过）"
Line "     bash scripts/wsl/install-service.sh   # 装 systemd 服务"
Line "     bash scripts/wsl/bind-slots.sh        # 绑定四个槽位"
Line "     bash scripts/wsl/doctor.sh            # 诊断"

# 报告写到临时目录，不污染仓库工作区
$reportPath = Join-Path $env:TEMP "setup-wsl-report.txt"
$out | Tee-Object -FilePath $reportPath
Write-Output ""
Write-Output "报告已保存到: $reportPath"
