#!/system/bin/sh
# setup_android.sh —— 在 Android 上（用 root）一次性装好双系统所需的全部东西。
#
# 前置：把恢复包里的文件 push 到手机：
#   adb push u-boot.img dtbo.img boot-android-rooted.img 99-raphael-switch.sh SwitchToDebian.apk /sdcard/Download/kits/
#
# 用法：
#   adb shell su -c "sh /sdcard/Download/kits/setup_android.sh"
set -e

KIT=/sdcard/Download/kits
RA=/data/raphael

echo "=== 1. 检查来源文件 ==="
for f in u-boot.img dtbo.img boot-android-rooted.img 99-raphael-switch.sh SwitchToDebian.apk; do
    [ -f "$KIT/$f" ] || { echo "missing $KIT/$f"; exit 1; }
    ls -l "$KIT/$f"
done

echo "=== 2. 放到 /data/raphael ==="
mkdir -p "$RA"
cp -f "$KIT/u-boot.img"              "$RA/u-boot.img"
cp -f "$KIT/dtbo.img"                "$RA/dtbo.img"
cp -f "$KIT/boot-android-rooted.img" "$RA/android-boot.img"
chmod 600 "$RA"/*.img
ls -l "$RA"

echo "=== 3. 同步到 ESP（cache 分区 = Linux 侧的 /boot）==="
mkdir -p /mnt/esp
mountpoint -q /mnt/esp 2>/dev/null || mount -t vfat -o rw /dev/block/by-name/cache /mnt/esp
cp -f "$RA/android-boot.img" /mnt/esp/android-boot.img
cp -f "$RA/dtbo.img"         /mnt/esp/dtbo.img
cp -f "$RA/u-boot.img"       /mnt/esp/u-boot.img
sync
df -h /mnt/esp
ls -l /mnt/esp/*.img
umount /mnt/esp

echo "=== 4. 装 Magisk 开机钩子（必须放 service.d；post-fs-data 阶段看不到 /sdcard）==="
mkdir -p /data/adb/service.d
cp -f "$KIT/99-raphael-switch.sh" /data/adb/service.d/99-raphael-switch.sh
chmod 755 /data/adb/service.d/99-raphael-switch.sh
rm -f /data/adb/post-fs-data.d/99-raphael-switch.sh
ls -l /data/adb/service.d/

echo "=== 5. 装切换 App ==="
pm install -r "$KIT/SwitchToDebian.apk" || echo "(if INSTALL_FAILED_USER_RESTRICTED, retry: pm install -r /data/local/tmp/<apk>)"

echo "=== DONE ==="
echo "打开 Switch to Debian，点按钮并允许 Magisk 授权即可。"
