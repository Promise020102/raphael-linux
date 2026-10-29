$ErrorActionPreference = "Continue"
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# 目录自身就是项目根，工具放在 .\tools（首次需要下载，见 README 里的说明）
$PROJ  = $PSScriptRoot
$W     = Join-Path $PROJ "tools"
$AAPT2 = Join-Path $W "aapt2\aapt2.exe"
$R8    = Join-Path $W "r8.jar"
$AJAR  = Join-Path $W "android.jar"
$PY    = "E:\develop\python\python3.8.8\python.exe"
$KS    = Join-Path $PROJ "debug.keystore"

if (-not $env:JAVA_HOME) { $env:JAVA_HOME = "E:\develop\jdk\jdk17" }
$JDK = Join-Path $env:JAVA_HOME "bin"

foreach ($p in @($AAPT2, $R8, $AJAR)) {
    if (-not (Test-Path $p)) {
        Write-Host "缺少构建工具: $p" -ForegroundColor Red
        Write-Host @"

首次构建请先下载三个包到 .\tools\ ：
  1) android.jar   (SDK platform 的 android.jar 即可，或 Maven: com.google.android:android:4.1.1.4)
  2) r8.jar        (https://maven.google.com/com/android/tools/r8/<ver>/r8-<ver>.jar) → 提供 d8
  3) aapt2         (Windows 版 aapt2.exe，放到 .\tools\aapt2\aapt2.exe)
详见 00-完整教程.md 的「附录 C：重新编译这个 App」
"@ -ForegroundColor Yellow
        exit 1
    }
}
if (-not (Test-Path $PY)) { $PY = "python" }

Remove-Item -Recurse -Force "$PROJ\classes","$PROJ\dexout","$PROJ\build" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$PROJ\classes","$PROJ\dexout","$PROJ\build" | Out-Null

Write-Host "=== 1. javac ==="
& "$JDK\javac.exe" -encoding UTF-8 -source 8 -target 8 -nowarn -classpath $AJAR -d "$PROJ\classes" `
    "$PROJ\src\com\raphael\switchtolinux\MainActivity.java" 2>&1 | ForEach-Object { "  $_" }
$n = (Get-ChildItem "$PROJ\classes\com\raphael\switchtolinux\*.class" -ErrorAction SilentlyContinue).Count
Write-Host "  class files: $n"
if ($n -lt 1) { throw "javac produced no classes" }

Write-Host "=== 2. d8 ==="
$cls = Get-ChildItem "$PROJ\classes\com\raphael\switchtolinux\*.class" | ForEach-Object { $_.FullName }
& "$JDK\java.exe" -cp $R8 com.android.tools.r8.D8 --release --lib $AJAR --min-api 23 --output "$PROJ\dexout" $cls 2>&1 |
    Select-String -Pattern "Error|error:" | ForEach-Object { "  $_" }
if (-not (Test-Path "$PROJ\dexout\classes.dex")) { throw "d8 produced no classes.dex" }
Write-Host ("  classes.dex: {0} bytes" -f (Get-Item "$PROJ\dexout\classes.dex").Length)

Write-Host "=== 3. aapt2 link ==="
& $AAPT2 link -o "$PROJ\build\base.apk" --manifest "$PROJ\AndroidManifest.xml" -I $AJAR `
    --min-sdk-version 23 --target-sdk-version 29 2>&1 | ForEach-Object { "  $_" }
if (-not (Test-Path "$PROJ\build\base.apk")) { throw "aapt2 link failed" }
Write-Host ("  base.apk: {0} bytes" -f (Get-Item "$PROJ\build\base.apk").Length)

Write-Host "=== 4. pack classes.dex ==="
$pack = @"
import zipfile, os
proj = r"$PROJ"
base = os.path.join(proj, "build", "base.apk")
final = os.path.join(proj, "build", "app-unsigned.apk")
with zipfile.ZipFile(base) as zin, zipfile.ZipFile(final, "w", zipfile.ZIP_DEFLATED) as zout:
    for it in zin.infolist():
        zout.writestr(it, zin.read(it.filename))
    zout.write(os.path.join(proj, "dexout", "classes.dex"), "classes.dex")
print("  packed", final, os.path.getsize(final))
"@
$pack | Set-Content -Encoding utf8 "$env:TEMP\pack_apk.py"
& $PY "$env:TEMP\pack_apk.py"

Write-Host "=== 5. sign ==="
if (-not (Test-Path $KS)) {
    & "$JDK\keytool.exe" -genkeypair -keystore $KS -storepass android -keypass android -alias androiddebugkey `
        -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 10000 2>&1 | ForEach-Object { "  $_" }
}
Copy-Item "$PROJ\build\app-unsigned.apk" "$PROJ\build\app.apk" -Force
& "$JDK\jarsigner.exe" -keystore $KS -storepass android -keypass android "$PROJ\build\app.apk" androiddebugkey 2>&1 |
    ForEach-Object { "  $_" }

Write-Host "=== result ==="
Get-ChildItem "$PROJ\build\app.apk" | Select-Object Name, Length | Format-Table -AutoSize | Out-String | Write-Host
$dist = Join-Path (Split-Path -Parent $PROJ) "04-镜像与脚本\SwitchToDebian.apk"
if (Test-Path (Split-Path -Parent $dist)) { Copy-Item "$PROJ\build\app.apk" $dist -Force; Write-Host "  -> $dist" }
