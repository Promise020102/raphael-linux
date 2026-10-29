#!/system/bin/sh
# Magisk late_start service hook: switch back to the Linux (U-Boot) boot slot.
#
# Trigger: create an empty file to-linux in one of these places, then reboot:
#   /data/adb/to-linux          (written by the "Switch to Debian" app)
#   /sdcard/to-linux            (manual, via any file manager)
#
# Writes u-boot.img into the boot partition, wipes dtbo (ABL only accepts the
# U-Boot image with dtbo blank) and reboots into the U-Boot menu / Debian.

FLAG1=/data/adb/to-linux
FLAG2=/data/media/0/to-linux
SRC=/data/raphael/u-boot.img
LOG=/data/raphael/switch.log

exec >>"$LOG" 2>&1
echo "---- $(date) service.d ----"
if [ -f "$FLAG1" ]; then
    echo "flag1=$FLAG1 present"
    FLAG=$FLAG1
elif [ -f "$FLAG2" ]; then
    echo "flag2=$FLAG2 present"
    FLAG=$FLAG2
else
    echo "no flag, staying in Android"
    exit 0
fi

[ -f "$SRC" ] || { echo "missing $SRC"; exit 0; }

echo "switching to Linux"
rm -f "$FLAG1" "$FLAG2"

dd if="$SRC" of=/dev/block/by-name/boot bs=4096 conv=fsync || echo "boot write FAILED"
dd if=/dev/zero of=/dev/block/by-name/dtbo bs=4096 count=8192 conv=fsync || echo "dtbo wipe FAILED"
sync
echo "done, rebooting"
reboot
