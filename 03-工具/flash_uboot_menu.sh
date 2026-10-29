set -e
EP=/dev/disk/by-partlabel/boot
echo "== before =="
dd if=$EP bs=1 count=8 2>/dev/null | od -An -tx1
echo "== write u-boot (clean menu) =="
dd if=/boot/u-boot-menu.img of=$EP bs=4096 conv=fsync
sync
echo "== readback head 671744 =="
dd if=$EP bs=4096 count=164 2>/dev/null | md5sum
echo "== expected =="
md5sum /boot/u-boot-menu.img
echo "== install into ESP too =="
install -m 755 /boot/u-boot-menu.img /boot/u-boot.img
md5sum /boot/u-boot.img
ls -l /boot/u-boot.img
echo "== free space =="
df -h /boot
