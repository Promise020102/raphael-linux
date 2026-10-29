# Redmi K20 Pro (raphael) 双系统恢复包

**设备**：Redmi K20 Pro / SM8150 v2 (raphael)，序列号 `e6869f59`
**双系统**：Android 11 (MIUI 12.5.6.0，带 Magisk root) ⇄ Debian GNU/Linux 13 (Phosh)
**切换方式**：改写 `boot` 分区 + 开关 `dtbo`，两边都无需电脑

---

## 一、这套东西是怎么工作的

```
ABL (bootloader)
 ├─ boot 分区 = 原厂/Magisk boot.img, dtbo 有效   →  正常启动 Android
 └─ boot 分区 = U-Boot (671,744 B), dtbo 全 0     →  U-Boot 菜单
                                                      └─ 5 秒后自动 bootefi → Debian
```

关键点：**ABL 只有在 `dtbo` 被擦空时才肯加载 U-Boot**（因为绕过了 AVB 校验）。
所以"切到 Linux"= 写 U-Boot 到 boot + 把 dtbo 写成 0；"切到 Android"= 写回 Android boot + 写回 dtbo。

分区布局（GPT，4096 B 扇区）：

| 分区 | 设备 | 大小 | 用途 |
|---|---|---|---|
| `boot` | sde49 | 128 MiB | 在 Android boot 与 U-Boot 之间切换 |
| `dtbo` | sde45 | 32 MiB | Linux 时必须为全 0 |
| `cache` | sda29 | 256 MiB | **ESP**（U-Boot 从这里读 `EFI/BOOT/BOOTAA64.EFI` 和内核） |
| `userdata` | sda32 | 100 GiB | Android /data（U-Boot 的 `preboot` 会把它当 blkmap 映射，找不到 ESP 就跳过） |
| `linux` | sda31 | 368.7 GiB | Debian 根（内部嵌套 GPT：p1 = ESP 副本 236M，p2 = ext4 根 368.4G） |

Debian 侧 fstab 用 `PARTLABEL=cache /boot`，所以 ESP 永远挂在 `cache`，不受嵌套 GPT 影响。

---

## 二、文件清单

```
android-side/
  SwitchToDebian.apk          Android 上的切换 App（点一下 → 重启进 Debian）
  99-raphael-switch.sh        Magisk 开机钩子，负责真正写 boot/dtbo 并重启
debian-side/
  switch-android              Debian 上的切换脚本（sudo switch-android → 重启进 Android）
u-boot.img                    带双系统菜单的 U-Boot（md5 89fd728f04c02cb682fa93583c27db41）
dtbo.img                      原厂 dtbo（切回 Android 时必须写回）
boot-android-rooted.img       Magisk 29 打过补丁的原厂 boot（42.3 MiB，已裁掉填充；只对 V12.5.6.0 有效）
pc-tools/                     adb / fastboot 及 DLL，PC 端备用
restore-linux.ps1             PC 端：把手机刷成"启动 Linux"
restore-android.ps1           PC 端：把手机刷成"启动 Android"
install-on-debian.sh          在 Debian 里一键装好 sudo switch-android
```

---

## 三、日常切换

| 方向 | 操作 |
|---|---|
| Android → Debian | 点桌面上的 **Switch to Debian** 图标（确认框 → 立即重启） |
| Debian → Android | 终端 `sudo switch-android` |
| 手动兜底（Android 侧） | 在 `/sdcard` 放一个空文件 `to-linux`，重启 |
| 手动兜底（Debian 侧） | `sudo dd if=/boot/u-boot.img of=/dev/disk/by-partlabel/boot bs=1M conv=fsync && sudo dd if=/dev/zero of=/dev/disk/by-partlabel/dtbo bs=4096 count=8192 && sudo reboot` |

Debian 侧的镜像放在 ESP 里，ROM 重刷不会动它们：
`/boot/u-boot.img`、`/boot/dtbo.img`、`/boot/android-boot.img`（Magisk 补丁版，已裁剪到 44,351,488 B）。

---

## 四、恢复场景

### 场景 A：重刷了 MIUI，只剩 Android

重刷 ROM 会覆盖 `boot` 和 `dtbo`（`boot` 变回原厂无 root），但 **`cache` 里的 ESP 和 `linux` 分区不受影响**，所以 Debian 本体没丢。重新装回切换能力：

```powershell
# 1) 让 Magisk 有 root（用 Magisk App 打补丁刷入，或直接刷 debian 侧那份已打过补丁的镜像：
#    从 Debian 的 /boot/android-boot.img 取出即可，但它只对 V12.5.6.0 这个版本有效）
# 2) 装切换 App 与钩子
adb push android-side\SwitchToDebian.apk /data/local/tmp/
adb shell su -c "pm install -r /data/local/tmp/SwitchToDebian.apk"
adb push android-side\99-raphael-switch.sh /data/local/tmp/
adb shell su -c "mkdir -p /data/adb/service.d /data/raphael"
adb shell su -c "cp /data/local/tmp/99-raphael-switch.sh /data/adb/service.d/; chmod 755 /data/adb/service.d/99-raphael-switch.sh"
# 3) 放好镜像
adb push u-boot.img /data/raphael/u-boot.img
adb push dtbo.img   /data/raphael/dtbo.img
# 4) 在 Android 里重开 Magisk 的 su 授权（App 首次点会弹窗，允许即可）
```

> `cache` 上的 ESP 若也被清空（极少见），需从备份 `esp.img` 恢复：`fastboot flash cache esp.img`。

### 场景 B：卡在 FASTBOOT，进不去任何系统

一般是连刷多次后 ABL 拒绝加载。**长按电源 15 秒强制关机，再长按电源开机**一般即可恢复。
仍然卡住就手动进 fastboot（关机 → 音量下 + 电源），然后：

```powershell
.\restore-android.ps1    # 刷回 Android boot + dtbo
# 或
.\restore-linux.ps1      # 刷成 U-Boot + 擦 dtbo，进 Debian
```

> 注意：`fastboot reboot` 在这台机器上是**假命令**（0.001 s 返回但什么都不做），必须手动断电重启。

### 场景 C：Debian 进不去，但 U-Boot 菜单能出来

U-Boot 菜单（`1. Debian GNU/Linux / 2. Reset device / 3. Power off`）5 秒后自动选 1。
若 Debian 内核或 initramfs 坏了：ESP 里有备份 `vmlinuz`、`initrd.img`、`linux.conf`，
或直接用 PC 刷 `restore-android.ps1` 先回 Android 再排查。

---

## 五、踩过的坑（省的再踩一遍）

1. **`fastboot flash recovery` 是无效的** —— 分区写进去了，但 MIUI 的 "recovery" 其实是 Android 系统本身，ABL 忽略 recovery 分区内容。
2. **U-Boot 的 fastboot 不能写盘** —— 能连上、能 `getvar`，但所有 `flash` 都报 `invalid partition or device`；只能用 ABL 的 fastboot。
3. **J1900 EDL 需要小米授权** —— `fastboot oem edl` 能进 9008，Sahara 也能过，但 firehose 会报 `Only nop and sig tag can be received before authentication`。别指望 EDL 救砖。
4. **U-Boot 靠分区名 `userdata` 找 ESP** —— 它的默认环境里 `setup_blkmap=part start ${rootdev} userdata ...`。这台机器上 `userdata` 是 Android /data（没有嵌套 GPT），所以 U-Boot 直接跳过 blkmap，改为从顶层 FAT 分区（`cache`）找到 ESP —— 这也是为什么不改分区名也能跑双系统。
5. **U-Boot 不能用链式引导器拉 Android** —— MIUI 的 4.14 内核没有 EFI stub，systemd-boot / GRUB 都拒绝加载（GRUB arm64 直接报 `plain image kernel not supported`）。所以 Android 必须由 ABL 原生启动。
6. **`/sdcard`（/data/media/0）在 Magisk `service.d` 阶段不可见** —— 钩子必须同时查 `/data/adb/to-linux` 和 `/data/media/0/to-linux`。
7. **`dtbo` 被擦后 TWRP 认不到任何分区**（UFS 控制器节点在 dtbo 里），`/proc/partitions` 是空的。
8. Android 无 root 时 **`input tap` 会被 MIUI 拒**（`INJECT_EVENTS` 权限），需要用 `su -c 'input tap ...'`。

---

## 六、脚本路径依赖与修改说明（必读，送给别人前先改）

下面每个脚本都用了**脚本所在目录的相对路径**，解压到不同电脑或不同目录时，需要按以下说明修改。

---

### `restore-android.ps1` —— PC 端：把手机刷成"启动 Android"

**脚本位置：** `restore-kit\restore-android.ps1`

**它会去找的文件（都在脚本同目录下）：**

| 文件 | 用途 | 如果没有/不匹配怎么办 |
|---|---|---|
| `pc-tools\fastboot.exe` | PC 端 fastboot 工具 | 把 `pc-tools/` 文件夹放在脚本同目录 |
| `boot-android-rooted.img` | Magisk 已打补丁的 Android boot 镜像 | **只对 MIUI V12.5.6.0 有效**。换 ROM 版本需用 Magisk 重新打补丁生成你的 `boot.img`，改名为 `boot-android-rooted.img` 放在这里 |
| `dtbo.img` | 原厂 dtbo | 从你的 MIUI 包 `images\dtbo.img` 复制 |

**运行前确认目录结构：**

```
restore-kit\
├── restore-android.ps1
├── restore-linux.ps1
├── pc-tools\
│   ├── fastboot.exe
│   ├── AdbWinApi.dll
│   └── AdbWinUsbApi.dll
├── u-boot.img
├── dtbo.img
└── boot-android-rooted.img
```

**运行：**

```powershell
# 手机先进 ABL fastboot（关机 → 音量下 + 电源，屏幕显示 FASTBOOT 兔子）
.\restore-kit\restore-android.ps1
```

**换了 ROM 版本？** 用参数指定你的 boot.img：

```powershell
.\restore-kit\restore-android.ps1 -BootImage "F:\你的路径\boot.img"
```

---

### `restore-linux.ps1` —— PC 端：把手机刷成"启动 Linux (U-Boot + Debian)"

**脚本位置：** `restore-kit\restore-linux.ps1`

**它会去找的文件（都在脚本同目录下）：**

| 文件 | 用途 |
|---|---|
| `pc-tools\fastboot.exe` | PC 端 fastboot 工具 |
| `u-boot.img` | 带双系统菜单的 U-Boot 镜像 |
| `dtbo.img` | 原厂 dtbo（Linux 启动时会被擦成全 0） |

**运行：**

```powershell
# 手机先进 ABL fastboot
.\restore-kit\restore-linux.ps1
```

**u-boot.img 从哪来？** 来自上游项目 `linux-xiaomi-raphael-uboot` 编译后的镜像，或者直接用恢复包里的（只对当前这台 raphael 有效，其他设备需重新编译）。

---

### `install-on-debian.sh` —— Debian 侧：一键装 `sudo switch-android`

**脚本位置：** `restore-kit\install-on-debian.sh`

**它会去找的文件（都在脚本同目录下）：**

| 文件 | 用途 | 放到手机哪里 |
|---|---|---|
| `u-boot.img` | U-Boot 镜像 | ESP（`/boot`，即 cache 分区） |
| `dtbo.img` | 原厂 dtbo | ESP（`/boot`，即 cache 分区） |
| `boot-android-rooted.img` | Magisk 已打补丁的 Android boot | ESP（`/boot`，即 cache 分区），会被复制为 `android-boot.img` |

**使用方法（在 Debian 里执行）：**

```bash
# 把整个 restore-kit 目录拷到 Debian 里，比如放到 /root/
sudo sh /root/restore-kit/install-on-debian.sh
```

脚本会自动把三个镜像复制到 ESP（`/boot`），并安装 `switch-android` 到 `/usr/local/bin/`。

---

### `switch-android` —— Debian 侧切换脚本（运行在手机 Debian 里）

**安装后位置：** 手机 `/usr/local/bin/switch-android`

**它用了固定的硬编码路径：**

| 路径 | 含义 |
|---|---|
| `/boot` | ESP 挂载点（本机 fstab 用 `PARTLABEL=cache`） |
| `/dev/disk/by-partlabel/boot` | Android boot 分区设备节点 |
| `/dev/disk/by-partlabel/dtbo` | dtbo 分区设备节点 |

**如果你需要修改：**

用文本编辑器打开 `/usr/local/bin/switch-android`，修改第 11–15 行：

```bash
ESP=/boot                                    # 改成你实际挂载 ESP 的路径
BOOT_IMG="$ESP/android-boot.img"
DTBO_IMG="$ESP/dtbo.img"
BOOT_DEV=/dev/disk/by-partlabel/boot        # 改成你实际的 boot 分区设备节点
DTBO_DEV=/dev/disk/by-partlabel/dtbo        # 改成你实际的 dtbo 分区设备节点
```

---

### `99-raphael-switch.sh` —— Android 侧 Magisk 开机钩子（运行在手机 Android 里）

**安装后位置：** 手机 `/data/adb/service.d/99-raphael-switch.sh`

**它用了固定的硬编码路径：**

| 路径 | 含义 |
|---|---|
| `/data/raphael/u-boot.img` | U-Boot 镜像存放位置（需要提前推进手机） |
| `/dev/block/by-name/boot` | Android boot 分区设备节点 |
| `/dev/block/by-name/dtbo` | dtbo 分区设备节点 |

**使用前准备（PC 端）：**

```bash
# 把 u-boot.img 推到手机
adb push u-boot.img /sdcard/Download/
adb shell su -c 'mkdir -p /data/raphael'
adb shell su -c 'cp /sdcard/Download/u-boot.img /data/raphael/u-boot.img'
```

**如果你需要修改：**

用文本编辑器打开 `/data/adb/service.d/99-raphael-switch.sh`，修改第 11–14 行：

```bash
FLAG1=/data/adb/to-linux
FLAG2=/data/media/0/to-linux
SRC=/data/raphael/u-boot.img          # 改成你实际放 u-boot.img 的路径
LOG=/data/raphael/switch.log
```

---

## 七、备份在哪

- GPT 主表：`sda-head-1M.bin`（md5 b6f2e12707aae72fe25762e4f6314b7f）
- 原 ESP 整盘：`esp.img`（247,463,936 B）
- Debian rootfs 整包：`rootfs.img`（8 GiB）
- 原厂 Android boot：`android_boot_real.img` / `C:\raphael-rom\boot.img`

  
