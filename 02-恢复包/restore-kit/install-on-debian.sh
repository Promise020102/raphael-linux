#!/bin/sh
# install-on-debian.sh —— 在 Debian(Linux) 侧一键装好 "sudo switch-android"
#
# 用法（在 Debian 里，把本目录拷过去后）：
#   sudo sh install-on-debian.sh
#
# 需要 ESP 已挂在 /boot（本机 fstab 用 PARTLABEL=cache，正常情况下就是挂好的）。
set -e

HERE=$(dirname "$0")
ESP=/boot

[ "$(id -u)" -eq 0 ] || { echo "need root: sudo sh $0" >&2; exit 1; }

command -v findmnt >/dev/null 2>&1 && findmnt "$ESP" || true

# 1) 切换脚本
install -m 755 "$HERE/switch-android" /usr/local/bin/switch-android
ln -sf /usr/local/bin/switch-android /usr/local/bin/switch-to-android
echo "installed /usr/local/bin/switch-android"

# 2) 桌面图标（Phosh 应用列表里会出现 "Switch to Android"）
mkdir -p /usr/share/applications
cat > /usr/share/applications/switch-android.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Switch to Android
Comment=Write the Magisk-patched Android boot image and reboot
Exec=pkexec /usr/local/bin/switch-android
Icon=system-reboot
Terminal=true
Categories=System;
EOF
chmod 644 /usr/share/applications/switch-android.desktop
echo "installed /usr/share/applications/switch-android.desktop"

# 3) 补齐 ESP 里的镜像（缺哪个补哪个）
[ -f "$ESP/u-boot.img" ]        || { cp "$HERE/u-boot.img"        "$ESP/u-boot.img";        echo "seeded $ESP/u-boot.img"; }
[ -f "$ESP/dtbo.img" ]          || { cp "$HERE/dtbo.img"          "$ESP/dtbo.img";          echo "seeded $ESP/dtbo.img"; }
[ -f "$ESP/android-boot.img" ]  || { cp "$HERE/boot-android-rooted.img" "$ESP/android-boot.img"; echo "seeded $ESP/android-boot.img"; }

echo
echo "== ESP contents =="
ls -l "$ESP/u-boot.img" "$ESP/dtbo.img" "$ESP/android-boot.img" 2>/dev/null || true
echo
echo "ok. 用法: sudo switch-android"
