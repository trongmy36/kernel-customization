# Tùy biến kernel Linux và tối ưu thời gian boot cho hệ thống hiển thị ô tô

## Kết quả và kết luận

| | Baseline | Custom | Giảm |
|---|---|---|---|
| Thời gian tới `Run /init` (`dmesg`) | 20.08 s | 0.51–0.54 s | **~97%** |
| Thời gian tới `AUTOMOTIVE DISPLAY READY` | 20.08 s | 0.57–0.60 s | **~97%** |
| Kích thước kernel `Image` | 123.6 MiB | 28.2 MiB | **77%** |

**Kết luận:** chỉ bằng cách chỉnh Kconfig (rootfs và service giữ nguyên), thời gian boot tới khi màn hình sẵn
sàng giảm từ khoảng 20 s xuống khoảng 0.6 s (giảm 97%), kernel nhỏ đi 77%, trong khi vẫn giữ đủ các chức năng
của màn hình ô tô. Phần lớn thời gian tiết kiệm đến từ việc bỏ driver của các SoC khác và các tính năng sản phẩm
không dùng, vì mỗi driver built-in đều có hàm khởi tạo chạy lúc boot.

Log: [`analysis/boot-baseline.log`](analysis/boot-baseline.log),
[`analysis/03-boot-custom-qcom-modules.log`](analysis/03-boot-custom-qcom-modules.log). Custom đo 3 lượt.

## 1. Tóm tắt

Trên xe, màn hình (cụm đồng hồ, camera lùi) phải hiển thị sớm nhất có thể sau khi cấp nguồn. Đồ án tùy biến
cấu hình kernel Linux 6.18.62 để rút ngắn thời gian từ lúc kernel khởi động tới lúc service hiển thị sẵn sàng.

**Hệ thống giả lập:**

- **Phần cứng:** máy ảo ARM64 QEMU `virt` (Cortex-A72, 1 CPU, 512 MB RAM). Đây là nền tảng thay cho board thật
  vì không có phần cứng ô tô. SoC mẫu cho xe được chọn là Qualcomm (`ARCH_QCOM`).
- **Tính năng của màn hình ô tô:** hiển thị (DRM), camera (V4L2), CAN bus, Ethernet/TCP-IP, Wi-Fi, Bluetooth,
  USB, âm thanh (ALSA), cảm ứng và nút bấm, lưu trữ (eMMC, ext4), GPIO/I2C/SPI, RTC, watchdog.
- **Phần mềm:** rootfs BusyBox initramfs và một service giả lập màn hình, dùng chung cho baseline và custom.

## 2. Phạm vi

| Thành phần | Lựa chọn |
|---|---|
| Kiến trúc, nền tảng chạy | ARM64, QEMU `virt` |
| Kernel | Linux 6.18.62, source trong `src/linux` |
| Rootfs | BusyBox initramfs, **giữ nguyên** giữa hai phiên bản |
| Service | `app/early-display.c`: in `AUTOMOTIVE DISPLAY READY` ra console và `/dev/kmsg` rồi thoát |
| Chỉ số đo | `boot-to-READY`: từ lúc kernel bắt đầu chạy tới khi service in dòng READY |

Hai phiên bản so sánh, dùng chung rootfs, service và tham số QEMU:

- **Baseline**: cấu hình ban đầu, là `arch/arm64/configs/defconfig` của kernel kèm một số tùy chọn debug của
  kernel đang phát triển. Đây là mốc gốc.
- **Custom**: xuất phát từ baseline, chỉnh Kconfig (`custom/defconfig`).

## 3. Chuỗi boot trên board nhúng ARM64

```mermaid
flowchart LR
    A[Boot ROM] --> B[Bootloader] --> C[Kernel] --> D[Rootfs]
```

| Giai đoạn | Nhiệm vụ |
|---|---|
| **Boot ROM** | Mã cố định do nhà sản xuất ghi sẵn trong SoC, chạy ngay khi cấp nguồn. Đọc cấu hình boot mode để chọn thiết bị boot (eMMC, SD, SPI flash), nạp bootloader vào SRAM rồi chuyển quyền điều khiển |
| **Bootloader** | Khởi tạo clock và DRAM, khởi tạo storage. Nạp kernel `Image`, Device Tree (DTB) và initramfs từ storage vào RAM, truyền kernel cmdline rồi nhảy vào entry point của kernel |
| **Kernel** | Bật MMU, khởi tạo memory, scheduler, interrupt, timer. Lần lượt khởi tạo các subsystem và driver built-in, probe thiết bị theo DTB. Giải nén initramfs làm rootfs rồi khởi chạy `/init` (PID 1) |
| **Rootfs** | `/init` mount các filesystem ảo `proc`, `sys`, `dev`, sau đó khởi chạy các service theo thứ tự định sẵn, trong đó có service hiển thị |

Trên QEMU `virt`, Boot ROM và bootloader không tồn tại: QEMU tự chép `Image` và initramfs vào RAM, tự sinh
DTB rồi nhảy thẳng vào kernel. Mốc `0.000000` trong `dmesg` là lúc kernel bắt đầu, nên phạm vi đo của đồ án
là từ kernel tới READY.

### Yếu tố ảnh hưởng tới fast boot

Xét từ userspace xuống kernel:

1. **Thứ tự service trong rootfs.** Người dùng chỉ cần thấy màn hình, không cần chờ mọi service khác. Nếu
   service hiển thị phải đợi các service khác (network, logging, update...) khởi chạy xong thì thời gian chờ
   đó cộng thẳng vào thời gian boot. Cần đẩy service hiển thị lên chạy sớm nhất, các service không cấp thiết
   khởi chạy sau hoặc song song.
2. **Kích thước rootfs.** Rootfs càng lớn thì càng tốn thời gian đọc từ storage, và với initramfs là thời gian
   giải nén trước khi `/init` chạy được.
3. **Kích thước kernel `Image`.** Bootloader phải đọc toàn bộ `Image` từ storage vào RAM. File càng lớn thì
   thời gian nạp càng lâu, nhất là trên storage chậm như SPI flash hay eMMC.
4. **Các tính năng bật trong Kconfig.** Đây cũng là nguyên nhân chính làm kernel to ra. Mã nguồn kernel dùng
   điều kiện biên dịch (`#ifdef CONFIG_...`, `obj-$(CONFIG_...)` trong Makefile): mỗi option bật lên thì đoạn
   code tương ứng được biên dịch vào kernel. Hệ quả:
   - Kernel có thêm code và data, `Image` lớn hơn (quay về yếu tố 3).
   - Mỗi driver và subsystem built-in đều có hàm khởi tạo chạy lúc boot (initcall): đăng ký với kernel, cấp
     phát bộ nhớ, probe phần cứng, có driver còn phải chờ thiết bị phản hồi. Driver cho phần cứng mà sản phẩm
     không có vẫn tốn thời gian khởi tạo.
   - Một số tính năng chèn thêm mã kiểm tra vào các thao tác thường xuyên của kernel, làm chậm toàn bộ quá
     trình boot chứ không chỉ một bước.

Trong phạm vi đồ án (rootfs giữ nguyên, QEMU thay Boot ROM và bootloader), đòn bẩy chính là **cấu hình kernel
(Kconfig)**.

## 4. Đánh giá để custom

Mỗi thành phần trong kernel được xếp vào một trong ba mức:

| Mức | Ý nghĩa | Kconfig |
|---|---|---|
| Cần | Chức năng của sản phẩm hoặc cần để boot | `=y` (built-in) |
| Có thể cần | Sản phẩm có thể dùng, nhưng không cần trước khi màn hình lên | `=y` hoặc `=m` (module) |
| Hoàn toàn không cần | Không phục vụ sản phẩm | `is not set` |

Module (`=m`) vẫn nằm trong bản build nhưng không chạy lúc boot, nên giữ được tính năng mà không tốn
thời gian boot.

### 4.1 Chức năng của màn hình ô tô: giữ

Bước đầu tiên là xác định màn hình ô tô thực tế cần những chức năng nào, rồi đối chiếu với Kconfig của kernel.
Mọi chức năng dưới đây **được giữ nguyên** như baseline.

| Chức năng | Kconfig đại diện |
|---|---|
| **Hiển thị** | `DRM`, `DRM_MSM`, `DRM_PANEL` |
| **Camera** | `MEDIA_SUPPORT`, `VIDEO_QCOM_CAMSS` |
| **CAN bus** | `CAN`, `CAN_DEV` |
| **Ethernet / TCP-IP** | `NET`, `INET`, `ETHERNET` |
| **Wi-Fi, Bluetooth** | `CFG80211`, `MAC80211`, `BT` |
| **USB** | `USB`, `USB_XHCI_HCD`, `USB_STORAGE` |
| **Âm thanh** | `SND`, `SND_SOC` |
| **Cảm ứng, nút bấm** | `INPUT_TOUCHSCREEN`, `HID` |
| **Lưu trữ** | `MMC`, `SCSI_UFSHCD`, `EXT4_FS` |
| **Bus và ngoại vi** | `GPIOLIB`, `I2C`, `SPI`, `RTC_CLASS`, `WATCHDOG` |
| **Quản lý nguồn, nhiệt** | `PM`, `CPU_FREQ`, `THERMAL` |
| **Ảo hóa** | `XEN` |
| **Hệ thống tối thiểu** | `BLK_DEV_INITRD`, `DEVTMPFS`, `PROC_FS`, `SYSFS`, `SERIAL_AMBA_PL011_CONSOLE` |

### 4.2 Các thay đổi trong custom và lý do

Sau khi giữ đủ chức năng ở 4.1, các thành phần còn lại được xét theo ba mức ở trên:

| Nhóm | Kconfig | Thay đổi | Lý do |
|---|---|---|---|
| Driver của SoC khác | 55 option `ARCH_*` (Rockchip, MediaTek, Tegra, i.MX, Renesas...). Giữ `ARCH_QCOM` | `y` thành **not set** | Sản phẩm chỉ chạy trên một SoC. Mỗi họ SoC kéo theo hàng trăm driver, và mỗi driver có initcall chạy lúc boot dù board không có phần cứng đó |
| Storage và legacy | `MTD_PHYSMAP`, `BLK_DEV_LOOP`, `SERIAL_8250` | `y` thành **module** | Không cần trước khi màn hình lên: không có NOR flash kiểu physmap, không mount file image, console dùng PL011. Là module nên vẫn dùng được khi cần |
| Mạng chia sẻ file | `NFS_FS`, `NFS_V4` | `y` thành **module** | Chỉ dùng khi phát triển hoặc mount từ xa, không cần lúc boot |
| Chia sẻ file với host | `9P_FS`, `NET_9P` | `y` thành **not set** | Chỉ dùng khi chạy trên QEMU, xe thật không có |
| ACPI | `ACPI` | `y` thành **not set** | Board ARM nhúng mô tả phần cứng bằng Device Tree, ACPI chỉ phổ biến ở server. Kiểu `bool` nên không có dạng module |
| Bổ sung | `GPIOLIB`, `GPIO_PL061`, `INET` | thêm **y** | Trước đây các `ARCH_*` bật hộ, nên khi tắt chúng phải bật lại tường minh để giữ GPIO của máy `virt` và TCP/IP |

Phân tích chi tiết nằm ở [docs/KCONFIG_EVALUATION.md](docs/KCONFIG_EVALUATION.md). Toàn bộ thay đổi trong
Kconfig nằm ở [custom/KCONFIG_DIFF.diff](custom/KCONFIG_DIFF.diff).

## 5. Giới hạn

- Baseline đo 1 lượt, custom đo 3 lượt (dao động khoảng 0.03 s).
- Đo trên QEMU, không phải board thật. Thời gian của Boot ROM và bootloader không nằm trong phép đo.
- Tính năng ở dạng module không chạy lúc boot nên không được kiểm chứng trong phép đo.

## 6. Tái hiện

```bash
scripts/build-linux.sh baseline        # build/kernel-baseline
scripts/build-linux.sh custom          # build/kernel-custom (config: custom/defconfig)
scripts/run-qemu.sh baseline           # thoát QEMU: Ctrl-A rồi X
scripts/run-qemu.sh custom
```
