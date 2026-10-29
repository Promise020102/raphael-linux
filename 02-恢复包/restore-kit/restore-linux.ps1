# restore-linux.ps1 —— 把手机刷成"启动 Linux (U-Boot + Debian)"
# 前提：手机在 ABL fastboot（关机 → 音量下 + 电源；屏幕显示 FASTBOOT 兔子）
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fb = Join-Path $here "pc-tools\fastboot.exe"
if (-not (Test-Path $fb)) { $fb = "fastboot" }

Write-Host "=== devices ===" -ForegroundColor Cyan
& $fb devices

Write-Host "`n=== flash U-Boot (with dual-boot menu) ===" -ForegroundColor Cyan
& $fb flash boot (Join-Path $here "u-boot.img")

Write-Host "`n=== erase dtbo (required: ABL only loads U-Boot when dtbo is blank) ===" -ForegroundColor Cyan
& $fb erase dtbo

Write-Host "`n=== done. 手动长按电源 15 秒关机再开机 ===" -ForegroundColor Green
Write-Host "（这台机器的 fastboot reboot 是假命令，不会真的重启）" -ForegroundColor Yellow
