# Đánh giá Kconfig: giữ gì, chuyển module gì, tắt gì

## 1. Nguyên tắc

Mỗi thành phần được bật trong kernel đều thêm code vào `Image` và thêm hàm khởi tạo (initcall) chạy lúc boot.
Vì vậy mỗi thành phần được xếp vào một trong ba mức:

| Mức | Ý nghĩa | Kconfig |
|---|---|---|
| Cần | Chức năng của sản phẩm hoặc cần để boot | `=y` (built-in) |
| Có thể cần | Sản phẩm có thể dùng, nhưng không cần trước khi màn hình lên | `=y` hoặc `=m` |
| Hoàn toàn không cần | Không phục vụ sản phẩm | `is not set` |

Option ở dạng module (`=m`) vẫn nằm trong bản build nhưng không chạy lúc boot, nên không tốn thời gian
boot mà vẫn giữ được tính năng. Chỉ option kiểu `tristate` mới chuyển được sang `=m`, option kiểu `bool`
chỉ có `y` hoặc `n`.

## 2. Chức năng thực tế của màn hình ô tô (giữ lại)

| Chức năng trên xe | Thành phần kernel cần | Quyết định |
|---|---|---|
| Hiển thị hình ảnh (cụm đồng hồ, giải trí, camera lùi) | Display / DRM, media (V4L2) | Giữ |
| Giao tiếp với xe | CAN bus, Ethernet (network stack) | Giữ |
| Kết nối điện thoại, media | USB, Bluetooth, Wi-Fi | Giữ |
| Âm thanh (cảnh báo, nhạc) | Sound (ALSA) | Giữ |
| Cảm ứng, nút bấm vô lăng | Input, HID | Giữ |
| Lưu trữ (cấu hình, dữ liệu) | eMMC / UFS, filesystem ext4 | Giữ |
| Điều khiển phần cứng nền (đèn nền, cảm biến, đồng hồ thời gian thực, watchdog an toàn) | GPIO, I2C, SPI, PWM, RTC, watchdog | Giữ |
| Chạy hệ thống tối thiểu | Console UART, `proc`, `sysfs`, `devtmpfs`, `tmpfs`, initramfs | Giữ |

Chỉ giữ **lõi (subsystem)** của các chức năng trên. Driver của phần cứng không thuộc board đích sẽ bị tắt.
Trong baseline, Sound, DRM, CAN, Bluetooth và Wi-Fi (`cfg80211`) vốn đã là module nên không nằm trong
thời gian boot của kernel. Config custom đã được kiểm tra: mọi subsystem ở bảng trên có trạng thái giống
hệt baseline.

## 3. Các nhóm đã chỉnh

| # | Nhóm | Quyết định | Lý do |
|---|---|---|---|
| 1 | **Driver của SoC khác** (`ARCH_*`: MediaTek, Rockchip, Tegra, i.MX, Renesas...) cùng driver đi kèm (clock, pinctrl, phy, regulator...) | **Tắt** 55 họ SoC, **giữ `ARCH_QCOM`** làm SoC mẫu cho xe | Sản phẩm chỉ chạy trên một SoC. Mỗi họ SoC bật thêm hàng trăm driver mà board đích không có phần cứng tương ứng |
| 2 | **Storage và legacy**: `MTD_PHYSMAP`, `BLK_DEV_LOOP`, `SERIAL_8250` | Chuyển sang **module** | Không cần trước khi hiển thị. Không có NOR flash, không mount file image, console dùng PL011 |
| 3 | **Tính năng tùy chọn** | Xem bảng dưới | |

Chi tiết nhóm 3:

| Option | Quyết định | Lý do |
|---|---|---|
| `XEN` | Giữ `y` | Xe dùng hypervisor Xen để chạy nhiều hệ điều hành trên một SoC. |
| `NFS_FS`, `NFS_V4` | `m` | Chỉ dùng khi phát triển, không cần lúc boot |
| `9P_FS`, `NET_9P` | Tắt | Chia sẻ file với host QEMU, không phải chức năng của xe |
| `ACPI` | Tắt (`bool`, không có dạng module) | Board ARM nhúng mô tả phần cứng bằng Device Tree, ACPI chỉ phổ biến ở server |

## 4. Option bổ sung để giữ nền tảng chạy

Một số option trước đây được các `ARCH_*` bật hộ, nên khi tắt chúng phải bật lại tường minh:

| Option | Vì sao |
|---|---|
| `GPIOLIB`, `GPIO_PL061` | GPIO của máy `virt` |
| `INET` | Ngăn xếp TCP/IP, cần cho chức năng mạng của xe |

Diff đầy đủ giữa baseline và custom nằm ở [custom/KCONFIG_DIFF.diff](../custom/KCONFIG_DIFF.diff).

## 5. Lưu ý khi đọc kết quả

- Option `=m` không chạy lúc boot. Rootfs của đồ án không nạp module nào, nên các tính năng này (như USB
  hay mạng) không được kiểm chứng chạy trong phép đo. Trên sản phẩm thật, chúng được nạp sau khi màn hình
  đã lên.
