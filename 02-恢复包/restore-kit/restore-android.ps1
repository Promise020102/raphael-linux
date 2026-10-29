# restore-android.ps1 —— 把手机刷成"启动 Android"
# 前提：手机在 ABL fastboot（关机 → 音量下 + 电源；屏幕显示 FASTBOOT 兔子）
#
# 默认刷入 boot-android-rooted.img（已由 Magisk 29 打过补丁，带 root）。
# 该镜像**只对 MIUI 12.5.6.0 (V12.5.6.0.RFKCNXM) 有效**；换了 ROM 版本请改用原厂 boot.img：
#   .\restore-android.ps1 -BootImage "F:\红米K20Pro相关\raphael_images_V12.5.6.0...\images\boot.img"
param(
    [string]$BootImage = ""
)
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fb = Join-Path $here "pc-tools\fastboot.exe"
if (-not (Test-Path $fb)) { $fb = "fastboot" }

$boot = Join-Path $here "boot-android-rooted.img"
if ($BootImage -ne "") { $boot = $BootImage }
if (-not (Test-Path $boot)) { Write-Host "找不到 boot 镜像: $boot" -ForegroundColor Red; exit 1 }

Write-Host "=== devices ===" -ForegroundColor Cyan
& $fb devices

Write-Host "`n=== flash dtbo (restore) ===" -ForegroundColor Cyan
& $fb flash dtbo (Join-Path $here "dtbo.img")

Write-Host "`n=== flash boot ===" -ForegroundColor Cyan
Write-Host "   $boot"
& $fb flash boot $boot

Write-Host "`n=== done. 手动长按电源 15 秒关机再开机 ===" -ForegroundColor Green
Write-Host "（这台机器的 fastboot reboot 是假命令，不会真的重启）" -ForegroundColor Yellow
