# Redmi K20 Pro（raphael / SM8150）Android 11 + Debian 13  phosh双系统教程

> ⚠️ **风险提示**：解锁 Bootloader 会失去保修；操作过程中 `/data` 会被清空，请先备份手机内全部重要数据（照片、文档、微信聊天记录等）。
>
> 适用设备：Redmi K20 Pro / K20 Pro 尊享版（代号 `raphael`，骁龙 855 / SM8150）
> 本机实测配置：512 GB UFS，MIUI 12.5.6.0 (V12.5.6.0.RFKCNXM)，Android 11

---

## 建议：使用 agent 执行本项目

该项目为本人使用deepseek harness一步步实现Debian+MIUI12.5双系统共存的效果，不保证完全没问题，但加上ai辅助的情况下为可实现双系统共存提供一定思路和案例。如果你有 AI agent（如 Cursor、codex、opencode、或者deepseek harness），**强烈建议让 agent 来帮你执行这个刷双系统项目**。

agent 可以：
- 帮你逐条核对每一步的命令是否正确
- 提醒你哪一步容易出错（比如 `dtbo` 必须擦成 0、`fastboot reboot` 是假命令）
- 在卡住时快速查阅踩坑记录并给出解决方案
- 把下载好的文件路径和命令对应起来，避免路径写错

建议在开始前先把下面的文件夹结构和所有文件下载好，然后让 agent 按阶段带你走一遍。

---

## 0. 一句话结论

**把 `boot` 分区当成"启动开关"**：

- `boot` = 原厂/Magisk 的 Android 内核 + `dtbo` 有效 → 正常启动 **Android**
- `boot` = U-Boot（约 672 KB）+ `dtbo` 全 0 → 启动 **U-Boot**，再进入 **Debian**

两边都**不需要电脑**就能切换：
- Android 里点一下 App → 写 U-Boot、擦 dtbo、重启 → 进 Debian
- Debian 里 `sudo switch-android` → 写回 Android 内核和 dtbo、重启 → 进 Android

---

## 1. 原理：为什么能双系统

常规的双系统（MultiROM / A/B 槽 / U-Boot 菜单直接加 Android 启动项）在这台机器上都走不通，因为 raphael 没有 A/B 槽、MIUI 内核没有 EFI stub、也没有动态分区 super。

本方案的核心发现：**当 `dtbo` 分区被擦成全 0 时，ABL（高通启动程序）就不再做 AVB 校验，会信任 `boot` 分区里的东西。** 于是：

```
                    ┌─ dtbo 有效 + boot=Android 内核 ──→ 正常启动 Android
ABL 上电 ─ 校验 ────┤
                    └─ dtbo 全 0 + boot=U-Boot ─────────→ U-Boot 菜单 ──→ Debian
```

把 `boot` 分区当"开关"，Linux 放在自己的分区，Android 放在自己的分区，两边互不干扰。

---

## 2. 下载所需文件与文件夹结构

在你的电脑上新建一个文件夹，作为本项目的工作目录，文件夹名直接叫 `raphael-linux`，里面再建三个子文件夹：

```
raphael-linux\
├── 镜像\          ← 放系统镜像（MIUI 包、Debian rootfs、U-Boot、TWRP、Magisk APK）
├── 工具\          ← 放 PC 端刷写工具（adb、fastboot 等）
└── 04-镜像与脚本\ ← 放 U-Boot 菜单生成、切换脚本、Magisk 钩子等（实际脚本都在这里）
```

下面所有命令示例里，如果出现 `..\镜像\`，就是指"回到上一级，进入镜像文件夹"；如果出现 `.\工具\`，就是指当前文件夹里的工具文件夹。

### 2.1 需要下载的文件清单

| 文件 | 用途 | 放哪 | 下载说明 |
|---|---|---|---|
| **MIUI 12.5.6.0 fastboot 包**<br>（完整版，含 `images\` 文件夹） | 刷回干净的 Android 11，提取 `boot.img`、`dtbo.img`、`system.img` 等 | `镜像\` | https://xiaomirom.com/rom/redmi-k20-pro-mi-9t-pro-raphael-china-fastboot-recovery-rom/ |
| **Debian rootfs**<br>`rootfs-debian-phosh-7.3-trixie-phosh-core.7z` | Debian 13 系统 | `镜像\` | https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/releases |
| **U-Boot 镜像**<br>`u-boot.img` | 写进手机 `boot` 分区，当启动开关 | `镜像\` | 同上 GitHub Release 页面 |
| **TWRP**<br>`twrp.img` | 救援用（可选，先不急着用） | `.\01-备份\`（已有一份，64 MB） | 上游项目 Release：https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/releases（文件夹里已直接提供，不需要重新下载） |
| **Magisk v29 APK** | 给 Android 取 root | `镜像\` | https://github.com/topjohnwu/Magisk/releases |
| **adb** | PC 端调试桥 | `工具\` | Android 平台工具包 |
| **fastboot** | PC 端刷写工具 | `工具\` | Android 平台工具包 |
| **AdbWinApi.dll**、**AdbWinUsbApi.dll** | adb/fastboot 依赖库 | `工具\` | 与 adb/fastboot 一起下载 |

> `adb` 和 `fastboot` 可以从 [Android Studio 平台工具](https://developer.android.com/studio/releases/platform-tools) 下载，解压后把 `adb`、`fastboot`、`AdbWinApi.dll`、`AdbWinUsbApi.dll` 全部放进 `raphael-linux\工具\`。

### 2.2 命令行怎么打开

1. 用资源管理器打开 `raphael-linux\工具\` 文件夹
2. 在文件夹空白处按住 **Shift + 右键**，选择"在此处打开 PowerShell 窗口"或"在此处打开命令行窗口"
3. 就可以输入下面的命令了

---

## 2.3 脚本路径依赖说明（先看这个）

下面几个脚本有 PC 端路径依赖，使用前请先检查：

| 脚本 | 路径依赖 | 处理建议 |
|---|---|---|
## 2.3 脚本路径依赖说明（先看这个）

下面几个脚本有 PC 端路径依赖，使用前请先检查，并按说明修改成你自己的环境：

### 2.3.1 `.\05-APK源码\build.ps1` —— 构建 SwitchToDebian.apk

**当前硬编码路径（在我电脑上的）：**

```powershell
# 第 11 行
$PY = "E:\develop\python\python3.8.8\python.exe"

# 第 14 行
$env:JAVA_HOME = "E:\develop\jdk\jdk17"
```

**你需要改成你自己的：**

```powershell
# 如果你装的是 Python 3.11，路径可能是：
$PY = "C:\Users\你的用户名\AppData\Local\Programs\Python\Python311\python.exe"

# 如果你装的是 JDK 21，路径可能是：
$env:JAVA_HOME = "C:\Program Files\Java\jdk-21"
```

**修改方法：** 用记事本打开 `.\05-APK源码\build.ps1`，把这两行里的路径改成你电脑上实际安装的 Python 和 JDK 路径，保存后重新运行脚本即可。

---

### 2.3.2 `.\03-工具\flash_rom.ps1` —— 刷入 MIUI 原厂 ROM

**当前默认设置：**

```powershell
$RomDir = "C:\raphael-rom"
```

脚本要求 `fastboot.exe` 与脚本在同一文件夹（即 `.\03-工具\`）。

**你需要改成你自己的：**

运行时不要修改脚本文件，直接在命令行里传参数：

```powershell
# 把 "F:\红米K20Pro相关\raphael_images_V12.5.6.0.RFKCNXM_...\images" 换成你解压后的 images 目录
.\03-工具\flash_rom.ps1 -RomDir "F:\红米K20Pro相关\raphael_images_V12.5.6.0.RFKCNXM_20211025.0000.00_11.0_cn\images"
```

或者先把 `fastboot.exe` 复制到 `.\03-工具\`，再运行脚本。

---

### 2.3.3 其他脚本（无 PC 端硬编码路径）

`build_uboot_menu.py`、`switch-android`、`99-raphael-switch.sh`、`setup_android.sh`、`rapsh.py`、`flash_uboot_menu.sh`、`install_hook.sh` 均使用 `$PSScriptRoot`、`os.path.dirname(__file__)` 或手机内路径，没有 PC 端硬编码路径，可直接使用。

---

### 2.3.4 恢复包脚本路径说明（`02-恢复包\restore-kit\`）

下面几个脚本用了**脚本所在目录的相对路径**（`Split-Path`、`dirname`），没有硬编码绝对路径，但解压位置不同需要注意文件彼此要在同一目录。详细的逐脚本路径依赖和修改方法，已移到 **第 5.4 节**，以免本章过长。

| 脚本 | 主要依赖文件 | 详情见章节 |
|---|---|---|
| `restore-android.ps1` | `pc-tools\fastboot.exe`、`boot-android-rooted.img`、`dtbo.img` | 第 5.4.1 节 |
| `restore-linux.ps1` | `pc-tools\fastboot.exe`、`u-boot.img`、`dtbo.img` | 第 5.4.2 节 |
| `install-on-debian.sh` | `u-boot.img`、`dtbo.img`、`boot-android-rooted.img` | 第 5.4.3 节 |
| `switch-android`（Debian 侧） | `/boot`、`/dev/disk/by-partlabel/boot`、`/dev/disk/by-partlabel/dtbo` | 第 5.4.4 节 |
| `99-raphael-switch.sh`（Android 侧） | `/data/raphael/u-boot.img`、`/dev/block/by-name/boot`、`/dev/block/by-name/dtbo` | 第 5.4.5 节 |

> 简要：`boot-android-rooted.img` **只对 MIUI V12.5.6.0 有效**，换 ROM 版本需用 Magisk 重新打补丁。

---

## 3. 分区容量：Linux 和 Android 各分多少空间

手机的存储空间被切成几块，分别给 Android 和 Linux 用。下面是**本机实际使用的分配方案**，你可以直接照用，也可以按第 3.2 节自定义。

### 3.1 本机分配方案

| 分区 | 给谁用 | 大小 | 说明 |
|---|---|---|---|
| `linux` | Debian 13 整个系统 | 约 368 GB | Linux 的根目录，存系统文件和你的个人资料 |
| `userdata` | Android 的照片、微信、下载文件等 | 100 GB | Android 的 /data，存你的应用和数据 |
| `cache` | Linux 启动文件（ESP，FAT32） | 256 MB | Linux 从这里读内核和启动菜单，Android 平时不占用 |
| `boot` | 启动开关（放 Android 内核或 U-Boot） | 128 MB | 两个系统共用，写谁就启谁 |
| `dtbo` | 设备树 | 32 MB | Linux 启动时擦成全 0；回 Android 时要还原 |



### 3.2 如果你想自定义大小

比如你想让 Android 只分 50 GB，剩下的都给 Linux，你需要修改**Debian 的 initramfs 里的重分区脚本**。

当前手机正在跑 Debian 时，initramfs 脚本在：

```
/usr/share/initramfs-tools/scripts/local-top/raphael-repart
```

文件里有个常量：

```
ANDROID_SECTORS=26214400     # 对应 100 GB，我这里分100GB给Android 
```

**计算方法：**
```
目标大小（字节）÷ 512 = 扇区数
```

举例：
- 50 GB = 50 × 1024 × 1024 × 1024 字节 = 53,687,091,200 字节
- 53,687,091,200 ÷ 512 = 104,857,600 个扇区

所以把该文件里的 `ANDROID_SECTORS=26214400`（对应 100 GB）改成 `ANDROID_SECTORS=104857600`（对应 50 GB）即可。

> **改完常量后别忘了生效**：回到「阶段 2.2 一键重分区」章节，在 ESP 上加上 `raphael.repart=apply` 参数重启，系统就会按新常量重新划分 `linux` / `userdata` 容量。

改完后要重新打包 initramfs 并刷回手机（或改完后在 Debian 里手动 `update-initramfs -u` 后重启触发 `raphael.repart=apply`），重启即可生效。手动调整分区有数据丢失风险，操作前务必备份。

---

## 4. 从零开始的完整步骤

> 全程需要 **Windows PC + USB 数据线**，以及一台能进 `fastboot` 的手机。
> 每一步都标注了：**在哪个文件夹、用什么终端、输入什么命令**，照抄即可。**不要跳步骤**，尤其阶段 3。

---

### 阶段 0：准备

#### 0.1 确认机型

**操作位置**：打开 `.\工具\` 文件夹的命令行窗口。

```cmd
adb devices
adb shell getprop ro.product.device     # 必须显示 raphael
# 或者进 fastboot 后：
fastboot getvar product                 # 必须显示 raphael
```

#### 0.2 解锁 Bootloader（一次性，会清空数据）

1. 去小米社区申请解锁资格 → 下载 `miflash_unlock` 工具 → 登录账号解锁
2. 解锁后，在 fastboot 模式下输入：
   ```cmd
   fastboot getvar unlocked
   ```
   必须返回 `yes`。
3. 注意：**解锁即失去保修**；MIUI 高版本会校验账号绑定 7 天。

#### 0.3 备份（非常重要，做双系统过程中 data 会被清）

备份分两步：先临时启动 TWRP（不刷入任何分区），然后在 TWRP 里备份 GPT 主表。整个过程**不需要 root**。

**第一步：临时启动 TWRP**
1. 手机关机，按住 **音量下 + 电源** 进入 ABL fastboot（屏幕出现 FASTBOOT 兔子）
2. 在电脑 `.\工具\` 目录打开命令行，运行：
   ```cmd
   fastboot boot ..\01-备份\twrp.img
   ```
   等待 TWRP 启动。这是**临时启动**，不会写入任何分区，重启后 TWRP 就会消失。

**第二步：在 TWRP 里备份 GPT 主表**
TWRP 自带 root 权限，可以直接用 `dd`：

1. 连接电脑，运行：
   ```cmd
   adb shell
   ```
2. 备份 GPT 主表（前 1MB）：
   ```sh
   dd if=/dev/block/sda of=/sdcard/sda-head-1M.bin bs=1M count=1
   ```
3. 拉回电脑：
   ```cmd
   adb pull /sdcard/sda-head-1M.bin .\01-备份\sda-head-1M.bin
   ```

> **如果你已经 root 过了**，不需要临时启动 TWRP，可以直接在 Android 里用 adb shell 执行：
> ```cmd
> adb shell su -c "dd if=/dev/block/sda of=/sdcard/sda-head-1M.bin bs=1M count=1"
> adb pull /sdcard/sda-head-1M.bin .\01-备份\sda-head-1M.bin
> ```

**第三步：生成 esp.img（Linux 启动分区）**
ESP 是当前设备专用的 FAT32 分区，不能直接用别人的。生成步骤：

1. 在手机上挂载并查看 ESP 内容：
   ```cmd
   adb shell su -c "mount -t vfat /dev/block/by-name/cache /mnt"
   adb shell su -c "ls /mnt"
   ```
2. 把 ESP 整盘打包成镜像：
   ```cmd
   adb shell su -c "dd if=/dev/block/by-name/cache of=/sdcard/esp.img bs=4096"
   adb pull /sdcard/esp.img .\01-备份\esp.img
   ```
   生成的 `esp.img` 里包含 `BOOTAA64.EFI`、`vmlinuz`、`initrd.img`、`loader/entries/linux.conf` 等，供后续阶段 3 把 ESP 搬到 `cache` 分区时使用。

> ⚠️ **ESP（esp.img）不可通用**：ESP 是 FAT32 文件系统，里面包含针对当前设备的内核、DTB、启动配置（BOOTAA64.EFI、vmlinuz、initrd.img、loader/entries/linux.conf 等）。**不能直接用别人的 esp.img**，每个设备需要自己制作。

**第三步（续）：备份原厂 boot.img**
从 MIUI fastboot 包的 `images\` 文件夹里直接复制 `boot.img` 到 `.\01-备份\boot.img`（不需要设备端操作）。

> 本机已有的完整备份：`sda-head-1M.bin`（GPT，仅本机有效）、`esp.img`（ESP 整盘，仅本机有效，由本节第 3 步生成）、`twrp.img`（临时 TWRP，可用于备份操作）、以及设备 100 个全分区 dump。

#### 0.4 准备三份镜像

| 文件 | 实际位置 | 下载说明 |
|---|---|---|
| 原厂 ROM fastboot 包 | —— | **不在文件夹里**，需要自己下载：https://xiaomirom.com/rom/redmi-k20-pro-mi-9t-pro-raphael-china-fastboot-recovery-rom/（下载后解压，把 `images\` 里的内容放进 `.\镜像\`） |
| `rootfs-debian-phosh-7.3-trixie-phosh-core.7z` | `.\01-备份\`（已有一份，1.55 GB） | 上游项目 Release：https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/releases |
| `u-boot.img` | `.\04-镜像与脚本\`（已有 `u-boot-original.img` 和 `u-boot-menu.img`） | 同上 GitHub Release 页面 |

---

### 阶段 1：把 Android 弄成"干净 + 有 root"

为什么要先做 Android：Magisk 会给 `boot.img` 打补丁，而 `boot` 分区后面要放 U-Boot。先把 Android 侧的东西准备好，才不会来回折腾。

#### 1.1 刷原厂 ROM

**操作位置**：打开 `.\工具\` 文件夹的命令行窗口。

1. 把下载的 MIUI V12.5.6.0 fastboot 包解压，把里面 `images\` 文件夹的内容放到某个目录，比如你电脑上任意一个文件夹（必须包含 `boot.img`、`dtbo.img`、`system.img` 等）
2. 手机先进 ABL fastboot：关机 → 音量下 + 电源 → 屏幕出现 FASTBOOT 兔子
3. 输入：

```powershell
.\flash_rom.ps1 -RomDir "你解压后的镜像目录"
```

（脚本默认会去 `C:\raphael-rom` 找镜像，如果你放在那儿，直接运行 `.\flash_rom.ps1` 也行）

这段脚本是基于 ROM 包里的 `flash_all.bat` 改写的，**不刷 GPT**，所以分区布局不会被破坏，Linux 分区会保留。

它会刷 41 个分区（xbl/abl/tz/hyp/devcfg/storsec/bluetooth/cmnlib/modem/dsp/keymaster/logo/misc/aop/qupfw/imagefv/uefisecapp/multiimgoem/vendor/vbmeta/dtbo/system/cache/recovery/cust/boot/userdata），约 3.9 分钟，全部 OKAY 后重启。

> ⚠️ 不要直接运行 ROM 包里的 `flash_all.bat`，因为它会重建分区表，把 Linux 分区和你的数据一起抹掉。必须用这个 `flash_rom.ps1`。
>
> ⚠️ 刷完 `boot` 就是原厂 Android 内核，**之前装的 U-Boot 会被覆盖** —— 这是正常的，阶段 4 会重新装。

#### 1.2 装 Magisk（拿到 root）

1. 把 Magisk 29 的 apk 拷到手机装上（你可以自行下载 Magisk v29 APK 放进 `.\镜像\`）
2. Magisk App → 安装 → **选择并修补一个文件** → 选从 ROM 里解出来的 `boot.img`
3. 产物在 `/sdcard/Download/magisk_patched-XXXXX.img`，拷到 PC：

```cmd
adb pull /sdcard/Download/magisk_patched-XXXXX.img .
```

4. 进 ABL fastboot：`fastboot flash boot magisk_patched-XXXXX.img`
5. 重启，`adb shell su -c id` 应返回 `uid=0(root)`

#### 1.3 记录两个数字（后面写文档/脚本要用）

```
打过补丁的 boot.img：kernel_size=43958745  ramdisk_size=374968
```

---

### 阶段 2：把 Debian 装进独立分区

#### 2.1 先用上游方案把 Debian 跑起来

**操作位置**：打开 `.\工具\` 文件夹的命令行窗口。注意一定要把之前下载的镜像放进镜像文件夹

```cmd
# 手机进 ABL fastboot
fastboot erase dtbo           # ← 必须，否则 ABL 不做 AVB 信任
fastboot boot ..\镜像\u-boot.img
fastboot flash userdata ..\镜像\rootfs.img     # 约 3.5 分钟
# 手动长按电源 15 秒关机，再开机
```

> 注意：这里用 `fastboot boot`（临时启动）而不是 `fastboot flash`，先让 Debian 跑起来。首次启动会进 Debian（Phosh）。

首次启动会进 Debian（Phosh）。默认账号：

```
user / 1234      （sudo 密码也是 1234）
root / 1234
```

USB 网卡固定 IP `172.16.42.1`（Windows 需要装 USB NCM 驱动；也可以直接连 Wi-Fi 用 IP 访问 SSH）。

#### 2.2 一键重分区：把 userdata 拆成 `linux` + `userdata`

上游在 initramfs 里内置了 `raphael-repart`，靠内核命令行参数触发。记得要先修改**Debian 的 initramfs 里的重分区脚本（3.2自定义大小）**。

**操作位置**：在 Debian 里（或从 Windows SSH 进去），编辑 ESP 上的启动项：

```bash
sudo sed -i 's/^options /options raphael.repart=apply /' /boot/loader/entries/linux.conf
sudo reboot
```

重启时会自动完成（日志写到 ESP 的 `raphael-repart.log`）：

- 把原来的大分区（≈469 GiB）**改名为 `linux`** 并缩到约 368.7 GiB
- 新建 **`userdata`，100 GiB**（留给 Android）
- 顺手 `resize2fs` 让根文件系统用满容量
- 自动去掉 `raphael.repart=` 参数，避免下次又跑

> 本机就是这条路线做出来的。我这里Android 分 **100 GiB**（`ANDROID_SECTORS=26214400`），剩下约 368.7 GiB 给 Linux。如果你想自定义容量（比如 Android 只要 50 GB），见上面的"分区容量：Linux 和 Android 各分多少空间"章节，修改 `ANDROID_SECTORS` 常量后，再按本节的步骤加上 `raphael.repart=apply` 重启重跑。

---

### 阶段 3：把 ESP 搬到 cache 分区（本方案的关键改动）

**为什么**：上游把 ESP 放在 `userdata` 里的嵌套 GPT 中。但 Android 要用 `userdata` 做 /data，一刷 Android 就会把嵌套 GPT 抹掉 → U-Boot 再也找不到 ESP。
把 ESP 搬到 `cache`（256 MiB，Android 平时不用）就彻底解耦。

**3.1 在 Debian 里把 ESP 打包**

```bash
sudo tar -cf /root/esp-backup.tar -C /boot .
```

**3.2 让 cache 变成 FAT32 的 ESP**

最简单：在 Debian 里直接格式化并拷文件

```bash
sudo mkfs.vfat -F 32 -n ESP /dev/disk/by-partlabel/cache
sudo mkdir -p /mnt/esp
sudo mount /dev/disk/by-partlabel/cache /mnt/esp
sudo tar -xf /root/esp-backup.tar -C /mnt/esp
sudo sync && sudo umount /mnt/esp
```

> 也可以把 `esp.img`（ESP 整盘镜像，247,463,936 B）直接用 fastboot 写进去：
> `fastboot flash cache esp.img`

**3.3 改 fstab，让 /boot 永远指向 cache**

⚠️ **不做这一步会出大问题**：`esp.img` 是整盘拷贝，FAT 卷 UUID 和 `linux` 分区里那份旧 ESP 完全一样，系统会随机挂到其中一个 → 改了启动参数却不生效。

```bash
sudo cp /etc/fstab /etc/fstab.bak
# 把 UUID=1BF4-A32B 那行换成 PARTLABEL=cache
sudo sed -i 's|^UUID=1BF4-A32B|PARTLABEL=cache|' /etc/fstab
sudo mount -a
findmnt /boot        # 必须显示 /dev/sda29
```

**3.4 验证 ESP 内容齐全**

```bash
ls /boot
# EFI/BOOT/BOOTAA64.EFI   vmlinuz   initrd.img   dtbs/   loader/
# loader/loader.conf     loader/entries/linux.conf
```

`loader.conf` 建议写成：

```
default  linux.conf
timeout  4
editor   no
```

---

### 阶段 4：装 U-Boot 让它启动 Linux

**4.1 先确认 U-Boot 是哪个版本**

本机用的 U-Boot：`u-boot-original.img`（671,744 B，`ANDROID!` 头，payload 是 gzip 过的 `u-boot-nodtb.bin` + 尾部 108,704 B FDT）。

**4.2 生成带菜单的版本**

原版 U-Boot 的 `bootcmd` 会先 `bootefi bootmgr` 再 `pause`，最后进 `bootmenu -1`，而这台机器的 U-Boot 编译时没有环境存储设备（**没有 saveenv**），所以菜单内容只能离线改固件二进制。

**操作位置**：打开 `.\04-镜像与脚本\` 文件夹的命令行窗口。

```powershell
python build_uboot_menu.py
# 输出 u-boot-menu.img（671,744 B，md5 89fd728f04c02cb682fa93583c27db41）
```

脚本做的事：

1. 从 `u-boot-original.img` 解出 `u-boot-nodtb.bin`（1,458,240 B）
2. 在 IMAGE 偏移 **1155745** 覆盖 **1422 字节**的默认环境块
3. 重新 gzip，**把原来 payload 尾部的 FDT 尾块原样拼回**（少了它 ABL 直接拒绝）
4. 重算 Android boot 头的 `kernel_size` 和 32 字节 id

写进去的菜单：

```
*** U-Boot Boot Menu ***
  1. Debian GNU/Linux        ← bootefi bootmgr; pause
  2. Reset device
  3. Power off
```

5 秒不操作自动选 1。

**4.3 写入 boot 分区**

在 **Debian 里**（最方便）：

```bash
sudo cp u-boot-menu.img /boot/u-boot.img
sudo dd if=/boot/u-boot.img of=/dev/disk/by-partlabel/boot bs=4096 conv=fsync
sudo dd if=/dev/zero of=/dev/disk/by-partlabel/dtbo bs=4096 count=8192 conv=fsync
sync
sudo reboot
```

> ⚠️ **dtbo 必须擦成 0**，否则 ABL 会做 AVB 校验并拒绝 U-Boot（表现为直接掉进 fastboot）。
> 反过来，要回 Android 时必须把 dtbo 写回原厂内容。

重启 → 看到 U-Boot 菜单 → 5 秒后进 Debian ✓

---

### 阶段 5：Android 侧切换能力（App + Magisk 钩子）

现在 Linux 能启动，但 `boot` 里是 U-Boot，Android 起不来。要能"回到 Android"，需要在 Android 里（或 Debian 里）写回 boot。本机两条都做了。

**5.1 Debian 侧（一条命令）**

```bash
sudo sh install-on-debian.sh      # 在 02-恢复包解压后的目录里
# 或者手动：
sudo cp switch-android /usr/local/bin/ && sudo chmod 755 /usr/local/bin/switch-android
```

之后：

```bash
sudo switch-android      # 写 boot + dtbo → reboot → Android
```

脚本内容就是两条 `dd`（`.\04-镜像与脚本\switch-android`）：

```sh
dd if=/boot/android-boot.img of=/dev/disk/by-partlabel/boot bs=1M conv=fsync
dd if=/boot/dtbo.img         of=/dev/disk/by-partlabel/dtbo bs=1M conv=fsync
reboot
```

所以 ESP 里要放三份镜像：`android-boot.img`（Magisk 补丁版）、`dtbo.img`、`u-boot.img`。

**5.2 Android 侧（Magisk 钩子 + App）**

先把镜像和脚本推上去（推荐用 `.\03-工具\setup_android.sh` 一次性做完）。

> 下面的 `u-boot.img` / `99-raphael-switch.sh` / `SwitchToDebian.apk` 都在 `.\04-镜像与脚本\` 里；另外两个文件 `dtbo.img` 和 `boot-android-rooted.img` **不在文件夹里**，需要你自己从 MIUI 包里提取/生成：
> - `dtbo.img`：从 MIUI fastboot 包的 `images\dtbo.img` 复制一份进来
> - `boot-android-rooted.img`：用 Magisk App 给 ROM 包里的 `images\boot.img` 打补丁，得到的 `magisk_patched-xxxxx.img` 改名为 `boot-android-rooted.img` 放进来

```cmd
adb push u-boot.img dtbo.img boot-android-rooted.img 99-raphael-switch.sh SwitchToDebian.apk /sdcard/Download/kits/
adb shell su -c "sh /sdcard/Download/kits/setup_android.sh"
```

它做四件事：

1. 镜像放进 `/data/raphael/`（`u-boot.img`、`dtbo.img`、`android-boot.img`）
2. 同样三份同步到 ESP（`/dev/block/by-name/cache`）
3. 钩子装到 `/data/adb/service.d/99-raphael-switch.sh`
4. `pm install` 切换 App

钩子的逻辑（`.\04-镜像与脚本\99-raphael-switch.sh`）：

```sh
FLAG1=/data/adb/to-linux          # App 点的
FLAG2=/data/media/0/to-linux      # 手动放的 /sdcard/to-linux
SRC=/data/raphael/u-boot.img
[ 有 flag ] → dd SRC → /dev/block/by-name/boot
              dd /dev/zero → /dev/block/by-name/dtbo (count=8192, 32 MiB)
              reboot
```

⚠️ **必须是 `service.d`，不能是 `post-fs-data.d`**：后者运行时 `/data/media/0`（也就是 `/sdcard`）还没挂载，钩子会一直打印 `no flag, staying in Android`（本机踩过，见坑 #14）。

**5.3 App**

`SwitchToDebian.apk`（7,678 B，源码在 `.\05-APK源码\`）：点一下 → 确认框 → 写 flag → 重启。
首次点会弹 Magisk 授权，允许即可。长按应用抽屉里的图标 → **添加到主屏幕**。

---

### 阶段 6：验证双向切换

```
Android ✓ → 点 App → 重启 → Debian ✓     （钩子日志：/data/raphael/switch.log）
Debian  ✓ → sudo switch-android → 重启 → Android ✓
```

本机实测时间线：

```
23:45:24  service.d: flag1=/data/adb/to-linux present → switching to Linux
          164+0 records out  671744 bytes 24.4MB/s
          8192+0 records out 33554432 bytes 79.7MB/s
          done, rebooting
23:46:38  Debian SSH 起来 ✓
```

---

## 5. 日常使用与恢复

### 5.1 切换

| 方向 | 操作 |
|---|---|
| Android → Debian | 点桌面 **Switch to Debian** 图标 → 确认 → 自动重启 |
| Debian → Android | 终端 `sudo switch-android` |
| 兜底（Android） | 在 `/sdcard` 放一个空文件 `to-linux`，重启 |
| 兜底（Debian）| 见 [附录 B](#附录-b-命令速查) |

### 5.2 三种故障的处置

**A. 卡在 FASTBOOT 出不来（本机遇到过两次）**

```powershell
# 1) 先试冷启动：长按电源 15 秒 → 再长按电源开机
# 2) 仍不行就手动进 fastboot：关机 → 音量下 + 电源
Expand-Archive 02-恢复包\raphael-dualboot-restore-kit.zip -DestinationPath . -Force  #恢复包要先自己制作好
.\restore-kit\restore-android.ps1     # 回 Android
.\restore-kit\restore-linux.ps1       # 或回 Linux
```

**B. 重刷了 MIUI，只剩 Android**

分区（`linux` / `cache` 上的 ESP）都还在，Debian 本体没丢。重新装回切换能力：

```powershell
# 1) 先 root（阶段 1.2）
# 2) 解压恢复包 → 一次性装好
adb push ... /sdcard/Download/kits/     # 见阶段 5.2
adb shell su -c "sh /sdcard/Download/kits/setup_android.sh"
# 3) 重新把 U-Boot 装进 boot（Debian 侧：sudo dd … 或直接 sudo switch-android 再 dd）
```

**C. Debian 起不来（U-Boot 菜单能出来）**

```bash
# 从另一台机器 SSH 进去（Wi-Fi 或 USB 172.16.42.1），或直接重装：
# 用 rootfs-debian-phosh-*.7z 解出 rootfs.img，fastboot flash userdata …
# 更快的办法：先刷回 Android，再从 Android 里修
```

> ⚠️ `fastboot` 的 `reboot` 在这台机器上是**假命令**（0.001 s 返回但什么都不做），一律手动断电。

---

## 6. 以后还能不能用这套刷双系统？怎么刷？

**能。** 而且比第一次容易得多，因为方法论和工具都齐了。

### 6.1 同一台机器：重装/恢复

| 情况 | 做法 | 耗时 |
|---|---|---|
| 只想再装一次（两边都还在） | 直接 `switch-android` / 点 App | 秒级 |
| 重刷了 ROM | 阶段 1.2（root）+ 阶段 5.2（`setup_android.sh`）+ Debian 侧 `dd` 回 U-Boot | ~20 分钟 |
| 彻底重来 | 阶段 0 → 阶段 6 全流程，用 `.\镜像\` 里的镜像 | 2~3 小时 |

### 6.2 换一台同型号机器（另一台 raphael）

**能用，但要换三样东西**（因为都跟具体机器/ROM 绑定）：

| 东西 | 为什么不能照搬 | 怎么办 |
|---|---|---|
| `boot-android-rooted.img` | Magisk 补丁和设备/ROM 版本绑定 | 用该机的 ROM `boot.img` 重新 Magisk 补丁 |
| `dtbo.img` | 32 MiB 原厂 dtbo，同型号通常相同，但保不齐批次差异 | 从该机 dump 或该机 ROM 包里取 |
| `SwitchToDebian.apk` | 通用，可直接装 | — |
| `u-boot.img`（带菜单的那个） | **raphael 专用**（SM8150 + 这套 U-Boot 编译）| 同型号可复用；**绝对不能刷到别的机型** |

`cache` 上的 ESP 也可以完全照抄（`esp.img` 直接 `fastboot flash cache`），因为它只包含启动器、内核、initramfs、DTB 和 `linux.conf`，根文件系统用 UUID 引用，不绑机器。

### 6.3 换别的机型（比如小新 Pad、其他骁龙机）

**这套具体做法不能直接用**，但思路通用：

1. 先确认有没有该机型的 U-Boot 移植（`u-boot` 主线 + 该机 dts）
2. 确认该机 ABL 是否也"`dtbo` 空了就跳过 AVB"（这是高通 + 小米设备的常见行为，但要实测）
3. ESP 放哪个分区：找一个 Android 不用、容量 ≥128 MiB、能 FAT32 的分区（`cache`、`persist` 之外的空分区）
4. 剩下的思路完全一样：boot 分区当开关 + Magisk 钩子写回

### 6.4 换别的 Android 系统（同一台机器）

先看一个硬约束——**这台机器的 Android 分区是"非动态分区"布局，没有 `super`**：

| 分区 | 容量 | 说明 |
|---|---|---|
| `system` | 3.5 GiB | 只读，装系统 |
| `vendor` | 1.5 GiB | 只读，厂商驱动 |
| `userdata` | 100 GiB | Android 的 /data |
| `linux` | 368.66 GiB | Debian 的地盘，**别碰** |

所以能不能刷，只取决于**新 ROM 的镜像能不能塞进 3.5 GiB 的 `system`**：

| 想刷的 ROM | 能不能 | 怎么刷 |
|---|---|---|
| **MIUI 12.0 / 12.5 系列（Android 10 / 11）官方 fastboot 包** | ✅ 能 | 照下面步骤 1–6，镜像尺寸和现有一致，`linux` 分区毫发无损 |
| **基于非动态分区的第三方 ROM**（LineageOS 18.1、crDroid 7.x 这类 A11 包） | ✅ 一般能 | 同样思路，但它没有 `vendor.img`/`cust.img`，刷的时候把缺的镜像从 `$list` 里去掉 |
| **MIUI 13 / 14、HyperOS（Android 12/13/14）** | ⚠️ 看包 | 先解压看 `flash_all.bat` 里有没有 `flash partition:` / `gpt_main*.bin`：有就说明它**重建分区表**，会连 Linux 一起抹掉，不行；没有才按下面刷 |
| **LineageOS 19/20/21、PixelExperience、EvolutionX（Android 12+）** | ❌ 不行 | 它们要 `super` 动态分区，刷之前的 `repartition` 步骤会重写 GPT，368 GiB 的 Debian 和你的数据全没 |

**⚠️ 铁律：任何时候都不要运行 ROM 包里的 `flash_all.bat` / `flash_all_lock.bat` / `flash_all_except_storage.bat`。**
它们会 `flash partition:N gpt_mainN.bin`，也就是重建分区表。用 `flash_rom.ps1` 代替（它只刷分区内容，永不碰 GPT）。

#### 刷入步骤（以换一个 MIUI 12.5.x 包为例）

```powershell
# 0) 备份：Android 里的照片/文件先拷到电脑（换 ROM 必须清 /data）
#    也可以先切到 Debian，把文件放进 Debian 的 /home/xy（368 GiB 那边有 324 GiB 空闲）

# 1) 解压新 ROM 包，找到 images 文件夹
cd .工具

# 2) 手机进 ABL fastboot：关机 → 音量下 + 电源 → 出现 FASTBOOT

# 3) 先只看设备状态，确认 product: raphael、anti 版本不比当前低
.\flash_rom.ps1 -RomDir "D:\新ROM\images" -OnlyVerify

# 4) 真刷（会清 /data；不要加 -SkipBoot，因为新 ROM 的内核必须换成它自己的）
.\flash_rom.ps1 -RomDir "D:\新ROM\images"
```

刷完会自动 `reboot`，**这时 Android 是"原厂未 root + 没 root 权限"的状态，但 U-Boot 已经被刷掉了**。

#### 刷完必须做的两件事

**① 重新拿 root（因为 boot.img 换了，旧 Magisk 补丁作废）**

```powershell
# 手机开机进系统 → 设置里打开 USB 调试 → 装 Magisk App（F 盘那个 magisk29.apk）
# Magisk → 安装 → 选择并修补一个文件 → 选 新ROM\images\boot.img
# 得到 magisk_patched-xxxxx.img，然后在 ABL fastboot 里：
.\fastboot flash boot "D:\新ROM\images\magisk_patched-xxxxx.img"
.\fastboot erase dtbo        # 关键：dtbo 清空后 ABL 才不会因为校验失败拒绝启动
```

**② 更新 ESP 里的切换镜像（否则切回 Debian 后就切不回来了）**

原因：ESP（`cache` 分区）里的 `android-boot.img` 还是**旧 ROM 的** Magisk 补丁版，`dtbo.img` 也是旧 ROM 的。用旧镜像去启动新 ROM 会直接进 fastboot。

```bash
# 在 Debian 里（切到 Debian 后执行）：
# 1) 把新 ROM 的 root 后 boot.img 和 dtbo.img 拷进 Debian，比如放到 /home/xy/
# 2) 覆盖 ESP 里的两个文件（ESP 太小，先删旧的再拷）
sudo rm -f /boot/android-boot.img /boot/dtbo.img
sudo cp /home/xy/magisk_patched-xxxxx.img /boot/android-boot.img
sudo cp /home/xy/dtbo.img                /boot/dtbo.img
sudo sync && sync
ls -l /boot
```

更省事的办法：在 Android 里用 root shell 直接写（`/data/raphael/` 目录是我们约定的位置）：

```bash
su -c 'cp /sdcard/Download/magisk_patched-xxxxx.img /data/raphael/android-boot.img'
su -c 'cp /sdcard/Download/dtbo.img /data/raphael/dtbo.img'
# 然后切到 Debian，把 /data/raphael/ 里这两个文件同步进 /boot
```

#### ③ 重装切换钩子和 App（`/data` 被清空后它们没了）

```bash
# 手机 root 后，在 Android 里跑（脚本在 .\03-工具\setup_android.sh，会做完下面所有事）：
#   1. 把 U-Boot / dtbo / root 后的 boot / 钩子 / APK 推到 /sdcard/Download/kits/
#   2. 装钩子到 /data/adb/service.d/ 并设成 755
#   3. 装 SwitchToDebian.apk
adb push ..\04-镜像与脚本\u-boot-menu.img ..\05-APK源码\SwitchToDebian.apk /sdcard/Download/
adb shell su -c 'mkdir -p /data/raphael /data/adb/service.d'
adb shell su -c 'cp /sdcard/Download/u-boot-menu.img /data/raphael/u-boot.img'
```

#### 换 ROM 后要检查的三件事

```bash
# Debian 里
sudo switch-android                 # 能不能正常切回 Android？
# Android 里点 "Switch to Debian"   # 能不能正常切回 Linux？
# 两边都正常 = 完成
```

#### 如果刷完发现新 ROM 塞不进 `system` 分区

`fastboot flash system system.img` 会报 `FAILED (remote: 'size too large')`。
这种情况**只能用动态分区布局**，也就是必须重划分区表 → Debian 那份必须重建。
流程就变成「文档阶段 1–5 从头再来一遍」，而且要先备份 22 GiB 的 Debian 数据（`tar` 到电脑或移动硬盘）。

> 一句话总结：**A11 及以前的 ROM 随便换；A12 以后要保 Linux 就别想了**（除非你愿意重新分区 + 重装 Linux）。

---

## 5.4 恢复包脚本路径依赖与修改说明（`02-恢复包\restore-kit\`）

下面每个脚本都用了**脚本所在目录的相对路径**（`Split-Path`、`dirname`），没有硬编码绝对路径，但解压到不同电脑或不同目录时，需要按以下说明修改。

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


## 7. 踩坑记录（按严重程度排序）

| # | 坑 | 现象 | 解 |
|---|---|---|---|
| 1 | **dtbo 必须全 0** | 带 dtbo 的 U-Boot 直接掉 fastboot / `Load Error` | 切 Linux 时 `dd if=/dev/zero of=…dtbo bs=4096 count=8192` |
| 2 | **`fastboot reboot` 是假命令** | 返回 `OKAY 0.001s`，机器不动 | 一律手动长按电源 15 秒 |
| 3 | **`recovery` 分区无效** | 写进去 U-Boot，重启还是 MIUI recovery | MIUI 的"recovery"是 Android 自己，放弃这条路 |
| 4 | **U-Boot 自带 fastboot 不能写盘** | 能连、能 `getvar`，所有 `flash` 报 `invalid partition or device` | 用 ABL 的 fastboot（关机→音量下+电源） |
| 5 | **EDL 需要小米授权** | `fastboot oem edl` 能进 9008，Sahara 过，firehose 报 `Only nop and sig tag can be received before authentication` | 别指望 EDL 救砖 |
| 6 | **`esp.img` 的 FAT UUID 与旧 ESP 相同** | `/boot` 随机挂到 `loop25p1` 或 `sda29`，改参数不生效 | fstab 改 `PARTLABEL=cache` |
| 7 | **U-Boot 靠分区名 `userdata` 找 ESP** | 改名后 U-Boot 找不到菜单/系统 | 把 ESP 放 `cache`，别改名 userdata |
| 8 | **U-Boot 无 saveenv** | 改了 `bootcmd` 重启就丢 | 只能离线改固件二进制（`build_uboot_menu.py`） |
| 9 | **重打包 U-Boot 丢了 FDT 尾块** | ABL 拒绝加载 / U-Boot 起不来 | 保留 payload 后 108,704 B 的 FDT |
| 10 | **MIUI 内核无 EFI stub** | systemd-boot / GRUB 都报 `plain image kernel not supported` | Android 只能由 ABL 原生启动 |
| 11 | **kexec 无声死机** | 跳到 `Starting kernel …` 后黑屏，无 USB 设备 | 放弃链式/接力启动 |
| 12 | **U-Boot `scsi` 只能按整盘寻址** | `part start scsi 0 cache` → `Invalid partition 41` | 用 `blkmap` 整块映射 |
| 13 | **`fatload` 到保留内存被拒** | `** Reading file would overwrite reserved memory **` | 用已验证地址（0x80000000 / 0x84000000 / 0xB0000000） |
| 14 | **`/sdcard` 在 `service.d` 阶段不可见** | 钩子一直 `no flag, staying in Android` | 改查 `/data/adb/to-linux`，或放 `service.d` 而非 `post-fs-data.d` |
| 15 | **`dtbo` 被擦后 TWRP 看不到分区** | `/proc/partitions` 为空 | TWRP 只能拉文件，不能用它写盘 |
| 16 | **`fastboot flash` 会"撒谎"** | 报 OKAY 但实际没写（`recovery` 分区实测）| 写完回读 md5 校验 |
| 17 | **cmdline 里 `vbmeta.size` 对不上** | ABL 报 5568，实际 struct 3328 | 不要照抄，只留 `vbmeta.device/device_state/veritymode` |
| 18 | **MediaTek/高通 dtbo overlay ≠ 完整 DTB** | 用 overlay 当 DTB → 内核无声死机 | 内核尾部自带完整 DTB，overlay 用 `fdtoverlay` 合并 |
| 19 | **Python 3.8 无 zstandard** | 解不开 initramfs（zstd） | `pip install zstandard` |
| 20 | **PowerShell 5.1 把无 BOM 的 UTF-8 当 ANSI** | 中文路径变乱码 → 路径找不到 | 脚本存成带 BOM 的 UTF-8 |
| 21 | **`javac` 默认按 GBK 读源码** | 中文注释报"不可映射字符" | `-encoding UTF-8` |

---

## 附录 A：文件清单与校验值

```
.
├── 镜像\
│   ├── esp.img                        247,463,936 B   ESP 整盘镜像（改造前的原样）
│   ├── rootfs-debian-phosh-*.7z     1,621,661,186 B   Debian 根（解出 8 GiB rootfs.img）
│   ├── sda-head-1M.bin                1,048,576 B     GPT 主表 + 分区项备份
│   ├── twrp.img                      67,108,864 B     TWRP 3.7.1（fastboot boot 用，不写分区）
│   └── u-boot.img                    约 671,744 B    U-Boot 镜像
├── 工具\
│   ├── adb / fastboot / AdbWinApi.dll / AdbWinUsbApi.dll
│   └── flash_rom.ps1                  刷原厂 ROM（不刷 GPT）
├── 04-镜像与脚本\
│   ├── u-boot-menu.img                  671,744 B   md5 89fd728f04c02cb682fa93583c27db41
│   ├── u-boot-original.img              671,744 B   原版（无自定义菜单）
│   ├── SwitchToDebian.apk               7,678 B     Android 侧切换 App
│   ├── switch-android                   Debian 侧切换脚本
│   ├── 99-raphael-switch.sh             Magisk 开机钩子
│   ├── setup_android.sh                 Android 侧一次性装镜像 + 钩子 + App
│   ├── build_uboot_menu.py              生成 u-boot-menu.img
│   └── ...
├── 05-APK源码\
    └── ...
```

关键校验值：

```
u-boot-menu.img                  89fd728f04c02cb682fa93583c27db41
u-boot-original.img              f6db3e66b6dffc8d1cbd7322978b6516
dtbo.img (原厂)                  438522c16524cca27d04a848da28e0ce
android-boot-rooted.img          fb73d6e5ad7ff05992fdbd9dcabfc4e5（含填充）
                                  kernel=43,958,745  ramdisk=374,968
sda-head-1M.bin                  b6f2e12707aae72fe25762e4f6314b7f
```

---

## 附录 B：命令速查

```bash
# ── Android → Debian（手动兜底）────────────────────────────
adb shell su -c "touch /data/adb/to-linux; reboot"

# ── Debian → Android（手动兜底）────────────────────────────
sudo dd if=/boot/android-boot.img of=/dev/disk/by-partlabel/boot bs=1M conv=fsync
sudo dd if=/boot/dtbo.img         of=/dev/disk/by-partlabel/dtbo bs=1M conv=fsync
sync && sudo reboot

# ── 看 U-Boot 菜单 / 进 shell（无键盘时）────────────────────
# 菜单：开机时按住"音量下"（U-Boot 的 button_cmd_0_name=Volume Down）
# 串口：菜单选 "Enable serial console gadget"，Windows 认成 USB Serial，波特率 115200

# ── 排查 ───────────────────────────────────────────────────
fastboot getvar all                 # 看 anti/secure/unlocked/分区尺寸
fastboot devices                    # ABL: product=raphael；U-Boot: product=xiaomi-raphael
cat /data/raphael/switch.log        # Android 侧钩子日志
sudo cat /boot/raphael-repart.log   # 上次重分区日志
findmnt /boot                       # 必须是 /dev/sda29
sudo blkid /dev/disk/by-partlabel/* # 分区 UUID/PARTUUID 一览

# ── 回读校验（永远不要相信 fastboot 的 OKAY）───────────────
fastboot flash boot x.img && adb shell su -c "md5sum /dev/block/by-name/boot"
```

---

## 附录 C：重新编译这个 App

不需要 Android Studio / Gradle，四个命令行工具足够：

```
05-APK源码\
  AndroidManifest.xml          package com.raphael.switchtolinux
  src\com\raphael\switchtolinux\MainActivity.java   单文件，纯代码 UI
  build.ps1                    javac → d8 → aapt2 → 打包 → jarsigner
  debug.keystore               自签名（storepass/keypass 都是 android）
  tools\                       ← 首次需自己下载三个文件
      android.jar              SDK platform 的 android.jar
      r8.jar                   提供 d8
      aapt2\aapt2          Windows 版 aapt2
```

```powershell
.\05-APK源码\build.ps1
# 产物：SwitchToDebian.apk，并自动复制到指定输出目录
```

装：

```powershell
adb push SwitchToDebian.apk /data/local/tmp/
adb shell su -c "pm install -r /data/local/tmp/SwitchToDebian.apk"
```

> 注意：`adb install` 在这台机器上会被 MIUI 拒（`INSTALL_FAILED_USER_RESTRICTED`），要用 `su -c pm install`。

---

## 附录 D：上游项目与致谢

- **Debian/Ubuntu for Redmi K20 Pro**：https://github.com/GengWei1997/linux-xiaomi-raphael-uboot
  - 提供了 U-Boot 移植、rootfs 镜像、`raphael-repart` 重分区、initramfs 的 loop 映射钩子
- **U-Boot**：https://source.denx.de/u-boot/u-boot （本机固件基于 2025.10-rc4）
- **TWRP for raphael**：Helium Studio 3.7.1_12 版
- **Magisk**：https://github.com/topjohnwu/Magisk （v29）

本方案在本机 README 说明的基础上做了三点改动：
**ESP 从 `userdata` 嵌套 GPT 搬到 `cache`**、**U-Boot 换成带菜单的离线补丁版**、**加了 Android 侧的 Magisk 钩子 + App 双向一键切换**。

---

