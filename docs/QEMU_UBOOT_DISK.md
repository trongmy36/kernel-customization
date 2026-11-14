# Demo ARM64: U-Boot + rootfs ext4 trên ổ đĩa

Đây là chế độ chạy bổ sung để quan sát boot qua bootloader và thiết bị lưu trữ.
Bản boot trực tiếp bằng `scripts/run-qemu.sh` vẫn giữ nguyên.

```text
QEMU virt (flash chứa U-Boot)
  -> U-Boot dò thiết bị VirtIO
  -> Đọc /boot/extlinux/extlinux.conf trên phân vùng ext4
  -> Đọc /boot/Image từ cùng phân vùng và chuyển quyền cho Linux
  -> Linux nhận /dev/vda, mount /dev/vda1 làm rootfs ext4
  -> /init mount proc/sysfs/devtmpfs và chạy early-display-service
  -> AUTOMOTIVE DISPLAY READY
  -> Shell BusyBox
```

QEMU không dùng `-kernel` hoặc `-initrd` ở chế độ này. Ổ đĩa có MBR và một phân
vùng Linux ext4 bắt đầu tại offset 1 MiB; dung lượng toàn ổ là 256 MiB. Kernel và
rootfs nằm trên cùng phân vùng. U-Boot dùng device tree do QEMU cung cấp.

## Chạy thử

Từ thư mục gốc project, với các artifact hiện có:

```bash
scripts/run-qemu-uboot.sh
```

U-Boot sẽ hiện banner, countdown autoboot mặc định 2 giây, đọc cấu hình extlinux
và kernel, rồi Linux hiện log mount rootfs ext4 và banner READY. Không thêm
`sleep` hoặc tác vụ giả để làm boot chậm.

Thoát QEMU bằng `Ctrl-A`, thả phím, rồi nhấn `X`. Để tắt máy ảo và đồng bộ ổ đĩa,
chạy lần lượt trong shell của máy ảo:

```sh
sync
mount -o remount,ro /
poweroff -f
```

Một số lệnh để xem hệ thống:

```sh
uname -m
cat /proc/cmdline
cat /proc/mounts
ls /boot
```

Ghi file trong máy ảo sẽ lưu vào `build/automotive-disk.img` và còn ở lần boot sau.
Hãy dừng QEMU trước khi build lại image; build lại sẽ tạo rootfs mới từ source,
thay thế dữ liệu trong image cũ.

## Dựng lại image

Script sử dụng kernel baseline tại
`build/kernel-baseline/arch/arm64/boot/Image` và BusyBox đã cài trong
`build/rootfs/`. Nó build service qua `rootfs/Makefile`, sao chép rootfs vào thư
mục tạm, thêm kernel/cấu hình boot, rồi tạo image bằng `mke2fs -d` và `sfdisk`.
Không cần `sudo`, loop device hoặc mount filesystem trên host.

```bash
scripts/build-disk.sh
scripts/run-qemu-uboot.sh
```

Các công cụ cần có: `make`, `aarch64-linux-gnu-gcc`, `mke2fs` (gói `e2fsprogs`),
`sfdisk` (gói `fdisk`), và `qemu-system-aarch64` (gói `qemu-system-arm` trên Ubuntu).

Các file nguồn mới:

- `rootfs/init-disk`: init dành riêng cho rootfs trên ổ đĩa.
- `rootfs/extlinux.conf`: đường dẫn kernel và kernel command line.
- `scripts/build-disk.sh`: đóng gói ổ đĩa.
- `scripts/run-qemu-uboot.sh`: chạy QEMU với U-Boot và ổ đĩa.

Để thêm `initcall_debug`, sửa dòng `APPEND` trong `rootfs/extlinux.conf`, rồi
build lại image. Script mới không nhận kernel arguments từ dòng lệnh vì U-Boot
đọc chúng từ ổ đĩa.

## U-Boot dùng cho bản demo

Đã tải gói Ubuntu `u-boot-qemu` phiên bản `2025.10-0ubuntu0.24.04.4` và giải nén
vào `build/firmware/`, không cài đặt vào hệ thống. SHA256 của file `.deb`:

```text
997cd55ca82e64163595249d1b8117732e6ad4c22a67634e605286cc61508c27
```

Trên máy có cùng phiên bản trong apt repository, có thể chuẩn bị lại bằng:

```bash
cd build
apt-get download u-boot-qemu=2025.10-0ubuntu0.24.04.4
mkdir -p firmware
dpkg-deb -x u-boot-qemu_2025.10-0ubuntu0.24.04.4_all.deb firmware
cd ..
```

Runner ưu tiên `build/firmware/usr/lib/u-boot/qemu_arm64/u-boot.bin`, sau đó tìm
`/usr/lib/u-boot/qemu_arm64/u-boot.bin`. Có thể chỉ định một bản khác:

```bash
UBOOT_BIN=/absolute/path/to/u-boot.bin scripts/run-qemu-uboot.sh
```

CPU và RAM mặc định vẫn là `cortex-a72`, 1 CPU, 512 MiB. Có thể đổi bằng
`QEMU_CPU` và `QEMU_MEM` như runner cũ. Runner mới tắt card mạng vì demo không
dùng mạng; không lấy chênh lệch giữa hai runner làm kết quả tối ưu kernel.

U-Boot đóng gói sẵn có thể in cảnh báo environment CRC (dùng environment mặc
định), thông báo Bloblist và thử EFI trước khi tìm extlinux. Trong lượt kiểm tra,
các thông báo này không ngăn boot; dấu hiệu thành công là đọc `/boot/Image`,
mount ext4, hiện READY và vào shell. Shell tối giản vẫn báo chưa có job control.

## Kết quả kiểm tra và cách hiểu số đo

Log kiểm tra lưu tại `analysis/boot-uboot-disk.log`. Đã kiểm tra:

- U-Boot tự tìm cấu hình extlinux và nạp kernel từ ổ đĩa.
- Linux chạy ARM64, rootfs `/dev/vda1` được mount ext4 ở chế độ đọc/ghi.
- Service báo READY; shell BusyBox nhận lệnh.
- File ghi ở lần boot trước còn sau khi khởi động lại.
- Đọc/ghi file mới, dọn file kiểm tra, remount rootfs read-only và tắt máy thành công.

Một lượt kiểm tra ghi nhận khoảng **3,77 giây từ lúc chạy process đến READY**,
trong khi `/proc/uptime` tại READY là **1,13 giây**. Một lượt tương tác trước đó
có uptime tại READY là 1,85 giây. Đây là kiểm tra chức năng, chưa phải benchmark;
không kết luận tăng/giảm hiệu năng từ các số này.

`/proc/uptime` và timestamp kernel chỉ tính từ phía Linux, không tính giai đoạn
U-Boot. Thời gian đo trên host còn gồm khởi động process QEMU, U-Boot, countdown,
đọc kernel, Linux và user space. Khi so sánh cần báo riêng các mốc và giữ cùng
bootloader, countdown, rootfs, phần cứng ảo và cách ghi log.

Đây là mô hình gần thiết bị nhúng hơn về **trình tự boot**, chưa đại diện cho
thời gian boot của bo mạch thật. Service vẫn là chương trình in marker hiện có,
chưa khởi tạo giao diện đồ họa. Bản này mở rộng phạm vi thiết kế ban đầu; không
phải kernel Custom và không tạo ra bằng chứng tối ưu kernel.

Tham khảo: [U-Boot trên QEMU ARM](https://docs.u-boot.org/en/stable/board/emulation/qemu-arm.html),
[QEMU ARM virt](https://www.qemu.org/docs/master/system/arm/virt.html).
