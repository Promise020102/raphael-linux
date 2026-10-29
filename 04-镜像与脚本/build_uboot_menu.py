# -*- coding: utf-8 -*-
"""重建 u-boot.img，写入双系统启动菜单（只有 Debian / Reset / Power off 三项）。

原理：这台机器的 U-Boot 是 CONFIG_ENV_IS_NOWHERE（没有 saveenv、没有环境存储设备），
默认环境字符串被编译进了固件二进制里。所以只能离线改：

  1. 把 u-boot.img 的 ANDROID! payload 解 gzip 得到 u-boot-nodtb.bin（1,458,240 B）
  2. 在 IMAGE offset 1155745 处覆写 1422 字节的默认环境块（用 \\0 分隔的 KEY=VALUE，尾部补 \\0）
  3. 重新 gzip 压缩，**并把原 payload 尾部附带的 FDT 尾块原样拼回去**
     （少了这个尾块，ABL 会拒绝加载，U-Boot 也起不来 —— 这是最容易踩的坑）
  4. 更新 Android boot 头里的 kernel_size 与 32 字节 id 校验
     id = sha1(payload) + sha1(pack("<III", len(payload), ramdisk_size, second_size))[:12]

用法：
    python build_uboot_menu.py
输出：
    u-boot-menu.img  （md5 应为 89fd728f04c02cb682fa93583c27db41）

刷入（在 Debian 里）：
    sudo dd if=u-boot-menu.img of=/dev/disk/by-partlabel/boot bs=4096 conv=fsync
"""
import io, os, struct, zlib, hashlib

BASE = os.path.dirname(os.path.abspath(__file__))
UB   = os.path.join(BASE, "u-boot-original.img")      # 原始 U-Boot（未打菜单补丁）
RAW  = os.path.join(BASE, "ub_raw.bin")               # 解压缓存，可随时删
OUT  = os.path.join(BASE, "u-boot-menu.img")

ENV_OFF = 1155745
ENV_LEN = 1422


def md5(b):
    return hashlib.md5(b).hexdigest()


def get_raw(img):
    """解出 u-boot-nodtb.bin；返回 (raw, trailer)。trailer 必须原样保留。"""
    (ksize, kaddr, rsize, raddr, ssize, saddr, tags, page, hver, osver) = struct.unpack("<10I", img[8:48])
    payload = img[page:page + ksize]
    dec = zlib.decompressobj(16 + zlib.MAX_WBITS)
    raw = dec.decompress(payload)
    trailer = dec.unused_data
    if trailer[:4] != b"\xd0\x0d\xfe\xed":
        raise SystemExit("payload 尾部不是 FDT，可能不是原厂 u-boot.img")
    return raw, trailer, page


env_lines = [
    "bootdelay=0",
    "bootretry=1",
    "stdin=serial,button-kbd",
    "stdout=serial,vidconsole",
    "stderr=serial,vidconsole",
    "preboot=scsi scan",
    "bootcmd=run menucmd",
    "menucmd=setenv bootcmd run menucmd; bootmenu 5",
    "bootmenu_0=Debian GNU/Linux=bootefi bootmgr; pause",
    "bootmenu_1=Reset device=reset",
    "bootmenu_2=Power off=poweroff",
    "button_cmd_0_name=Volume Down",
    "button_cmd_0=run menucmd",
]

blob = ("\0".join(env_lines) + "\0").encode("ascii")
print("env bytes:", len(blob), "budget:", ENV_LEN)
assert len(blob) <= ENV_LEN, "env too big"
blob = blob + b"\0" * (ENV_LEN - len(blob))

img = io.open(UB, "rb").read()
raw, trailer, page = get_raw(img)
if os.path.exists(RAW) and os.path.getsize(RAW) == len(raw):
    raw = io.open(RAW, "rb").read()
else:
    io.open(RAW, "wb").write(raw)
print("raw u-boot-nodtb.bin:", len(raw), "B   fdt trailer:", len(trailer), "B")
assert len(raw) == 1458240, len(raw)

raw = bytearray(raw)
raw[ENV_OFF:ENV_OFF + ENV_LEN] = blob
patched_raw = bytes(raw)
print("patched raw md5:", md5(patched_raw))

co = zlib.compressobj(9, zlib.DEFLATED, 31)
new_payload = co.compress(patched_raw) + co.flush() + trailer


def and_id(kernel_bytes, ramdisk_size, second_size):
    a = hashlib.sha1(kernel_bytes).digest()
    b = hashlib.sha1(struct.pack("<3I", len(kernel_bytes), ramdisk_size, second_size)).digest()
    return a + b[:12]


hdr = bytearray(img[:page])
struct.pack_into("<I", hdr, 8, len(new_payload))
hdr[576:608] = and_id(new_payload, 0, 0)
body = bytes(hdr) + new_payload
body += b"\0" * ((-len(body)) % page)

io.open(OUT, "wb").write(body)
print("wrote", OUT, len(body), "md5", md5(body))
