# raphael fastboot flash - NEVER touches the GPT, so the "linux" (Debian) partition survives.
# Usage:
#   .\flash_rom.ps1                        # default ROM dir: C:\raphael-rom (V12.5.6.0 junction)
#   .\flash_rom.ps1 -RomDir "D:\other\images"
#   .\flash_rom.ps1 -SkipBoot              # leave the boot partition alone (keeps U-Boot)
#   .\flash_rom.ps1 -SkipUserdata          # keep /data (only safe within the same ROM family)
#   .\flash_rom.ps1 -OnlyVerify            # just print device info
param(
    [switch]$SkipBoot,
    [switch]$SkipUserdata,
    [switch]$OnlyVerify,
    [string]$RomDir = "C:\raphael-rom"
)

$ErrorActionPreference = "Stop"
$FB  = Join-Path $PSScriptRoot "fastboot.exe"
$IMG = $RomDir

if (-not (Test-Path $FB))  { throw "fastboot missing: $FB" }
if (-not (Test-Path $IMG)) { throw "image dir missing: $IMG" }

Write-Host "=== devices ==="
& $FB devices
Write-Host "=== getvar product ==="
& $FB getvar product
Write-Host "=== getvar anti ==="
& $FB getvar anti

if ($OnlyVerify) { return }

$fails = @()

$list = @(
  "xbl:xbl.elf",
  "xblbak:xbl.elf",
  "xbl_config:xbl_config.elf",
  "xbl_configbak:xbl_config.elf",
  "abl:abl.elf",
  "ablbak:abl.elf",
  "tz:tz.mbn",
  "tzbak:tz.mbn",
  "hyp:hyp.mbn",
  "hypbak:hyp.mbn",
  "devcfg:devcfg.mbn",
  "devcfgbak:devcfg.mbn",
  "storsec:storsec.mbn",
  "bluetooth:BTFM.bin",
  "cmnlib:cmnlib.mbn",
  "cmnlibbak:cmnlib.mbn",
  "cmnlib64:cmnlib64.mbn",
  "cmnlib64bak:cmnlib64.mbn",
  "modem:NON-HLOS.bin",
  "dsp:dspso.bin",
  "keymaster:km4.mbn",
  "keymasterbak:km4.mbn",
  "logo:logo.img",
  "misc:misc.img",
  "aop:aop.mbn",
  "aopbak:aop.mbn",
  "qupfw:qupv3fw.elf",
  "qupfwbak:qupv3fw.elf",
  "imagefv:imagefv.elf",
  "uefisecapp:uefi_sec.mbn",
  "uefisecappbak:uefi_sec.mbn",
  "multiimgoem:multi_image.mbn",
  "vendor:vendor.img",
  "vbmeta:vbmeta.img",
  "dtbo:dtbo.img",
  "system:system.img",
  "cache:cache.img",
  "recovery:recovery.img",
  "cust:cust.img"
)

$t0 = Get-Date
$n = 0
foreach ($item in $list) {
  $n++
  $part, $file = $item.Split(":")
  $path = Join-Path $IMG $file
  if (-not (Test-Path $path)) { throw "missing image file: $path" }
  $mb = [math]::Round((Get-Item $path).Length / 1MB, 1)
  Write-Host ("[{0}/{1}] flash {2} <- {3} ({4} MB)" -f $n, ($list.Count + 2), $part, $file, $mb)
  & $FB flash $part $path
  if ($LASTEXITCODE -ne 0) {
    Write-Host ("    !! FAILED {0}" -f $part)
    $fails += $part
  }
}

if (-not $SkipBoot) {
  Write-Host "[$($list.Count + 1)/$($list.Count + 2)] flash boot <- boot.img (stock Android boot)"
  & $FB flash boot (Join-Path $IMG "boot.img")
  if ($LASTEXITCODE -ne 0) { Write-Host "    !! FAILED boot"; $fails += "boot" }
}

if ($SkipUserdata) {
  Write-Host "[$($list.Count + 2)/$($list.Count + 2)] userdata skipped (-SkipUserdata) - /data kept"
} else {
  Write-Host "[$($list.Count + 2)/$($list.Count + 2)] flash userdata <- userdata.img (clean /data)"
  & $FB flash userdata (Join-Path $IMG "userdata.img")
  if ($LASTEXITCODE -ne 0) { Write-Host "    !! FAILED userdata"; $fails += "userdata" }
}

Write-Host ("=== all done in {0:N1} min ===" -f ((Get-Date) - $t0).TotalMinutes)
if ($fails.Count -gt 0) {
  Write-Host ("=== FAILED PARTITIONS: {0} ===" -f ($fails -join ", "))
  $critical = @("boot", "system", "vendor", "userdata") | Where-Object { $fails -contains $_ }
  if ($critical) {
    Write-Host "!!! critical partition(s) failed, NOT rebooting: $($critical -join ', ')"
    exit 1
  }
}
& $FB reboot
