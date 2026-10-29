#!/system/bin/sh
set -x
mkdir -p /data/adb/service.d
cp -f /data/local/tmp/99-raphael-switch.sh /data/adb/service.d/99-raphael-switch.sh
chmod 755 /data/adb/service.d/99-raphael-switch.sh
rm -f /data/adb/post-fs-data.d/99-raphael-switch.sh
ls -lZ /data/adb/service.d/
echo "=== run hook now ==="
sh /data/adb/service.d/99-raphael-switch.sh
echo "=== log ==="
cat /data/raphael/switch.log
