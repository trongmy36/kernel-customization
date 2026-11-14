# Linux Kernel Customization and Fast Boot Optimization for an Automotive Display System

> **Đề xuất project cuối kỳ — Linux Open Source Operating Systems (Linux OSS)**  
> **Nhóm:** 3 sinh viên  
> **Nền tảng:** Linux Kernel ARM64 + BusyBox/initramfs + QEMU (`virt`)  
> **Trọng tâm duy nhất:** **Fast Boot / Early Service Startup**, kèm tinh giản hệ thống để phục vụ mục tiêu này.  
> **Trạng thái:** Phương án thiết kế dự kiến; chưa có số đo thực nghiệm.

> **Thử nghiệm bổ sung:** Đã thêm chế độ boot qua U-Boot và rootfs ext4 trên ổ
> đĩa ảo để quan sát chuỗi boot đầy đủ hơn. Xem [hướng dẫn chạy](QEMU_UBOOT_DISK.md).
> Đây là phần mở rộng ngoài phạm vi bootloader của đề xuất ban đầu; chưa phải
> kết quả benchmark Baseline/Custom.

> **Hướng mô phỏng thiết bị chạy Ubuntu:** Có thêm [Ubuntu ARM64 trên QEMU](QEMU_UBUNTU_ARM64.md),
> dùng rootfs Ubuntu, kernel Ubuntu và systemd service để tạo baseline user space
> đầy đủ hơn. Bản này độc lập với BusyBox; chưa tích hợp kernel tự build.

## 1. Bối cảnh

Trên ô tô, người lái muốn **thấy thông tin quan trọng trên màn hình trung tâm càng sớm càng tốt**, thay vì chờ toàn bộ phần mềm giải trí, mạng và tính năng phụ khởi động xong. Các chức năng phụ có thể khởi động sau, miễn là không phải điều kiện bắt buộc để hiển thị màn hình trạng thái ban đầu.

**Vấn đề kỹ thuật:** Một Linux tổng quát mang theo nhiều driver và bước khởi tạo không cần cho nhiệm vụ hiển thị ban đầu; nếu service ưu tiên phải chờ các tác vụ không liên quan, thời điểm "sẵn sàng" bị kéo dài.

**Nhu cầu:** Thiết kế một Linux chuyên dụng đưa service hiển thị trạng thái lên sớm, chỉ giữ thành phần cần thiết, và đo được thời gian từ lúc boot đến khi service sẵn sàng.

> Đây là **tình huống mô phỏng** dựa trên một loại nhu cầu thực tế, không phải phát triển hay kiểm chứng hệ thống ô tô thương mại, không phải BSP của hãng nào, và không tuyên bố đáp ứng tiêu chuẩn an toàn ô tô. Thời gian đo là **thời gian boot của hệ thống mô phỏng QEMU theo mốc đo đã quy ước** (QEMU nạp kernel trực tiếp, không có Boot ROM/bootloader).

## 2. Nhóm mô phỏng điều gì?

Không mô phỏng cả xe hay giao diện giải trí. Chỉ mô phỏng hành vi khởi động quan trọng nhất:

```text
QEMU ARM64 bắt đầu boot
        |
        v
   Linux Kernel
        |
        v
  init (initramfs)
        |
        +----> early-display-service ----> "AUTOMOTIVE DISPLAY READY" + timestamp
        |
        +----> Background tasks (chạy sau READY, nếu không phụ thuộc)
```

### Tầng ứng dụng: `early-display-service`

Đây là một **chương trình nhỏ tự viết**, đóng vai app màn hình ô tô, mục đích chính là **tạo mốc đo dễ đọc trong log**. Không cần network hay socket (tránh kéo thêm `virtio-net` làm nhiễu số đo).

- Khi chạy, in một màn hình trạng thái text đơn giản (tiêu đề `AUTOMOTIVE DISPLAY`, vài thông số giả lập) và dòng `AUTOMOTIVE DISPLAY READY` kèm uptime đọc từ `/proc/uptime` ra console.
- Ghi thêm cùng dòng đó vào `/dev/kmsg`, để marker READY nằm **cùng dòng thời gian với log kernel trong `dmesg`**. Nhờ đó đọc được boot-to-ready bằng một lệnh.
- Viết bằng C, link static cho aarch64.
- Các tác vụ nền giả lập là vài process chạy sau READY; phải là thành phần tự nhiên có trong baseline, **không thêm delay nhân tạo để thể hiện tăng tốc**.

**Giao diện:** text trên console QEMU (`-nographic`), không dùng đồ họa để giữ kernel tối giản.

## 3. Mục tiêu và các việc phải làm

**Mục tiêu tổng quát:** xây dựng và tùy chỉnh một hệ thống Linux ARM64 mô phỏng để rút ngắn thời gian boot đến khi service sẵn sàng, qua kernel configuration và tối ưu quy trình boot.

1. **Baseline boot được:** tải Linux kernel và BusyBox, cross-compile ARM64, đóng gói initramfs, boot QEMU, service báo `READY`. Lưu `.config`, version nguồn, tham số QEMU.
2. **Phân tích và tùy chỉnh kernel:** boot với `initcall_debug`, dùng `scripts/bootgraph.pl` để xác định initcall nào tốn thời gian trên critical path. Dựa vào đó dùng `menuconfig` loại driver/subsystem không dùng, giữ lại console, interrupt, timer, initramfs. Thử thêm các kỹ thuật boot: `quiet`, `CONFIG_MODULES=n` (build-in tất cả), kiểu nén kernel/initramfs (none/lz4/gzip). Ghi **config diff + lý do + bằng chứng initcall** cho bản Custom cuối cùng.
3. **(Tùy chọn) Tối ưu đường khởi động:** nếu còn thời gian, loại bước init không phục vụ chức năng ưu tiên và chuyển tác vụ phụ ra sau `READY`; kiểm tra không mất chức năng cần thiết.
4. **Benchmark:** script chạy từng phiên bản với cùng cấu hình QEMU, nhiều lượt, lưu log thô, thống kê trung vị và độ dao động; tách rõ phần cải thiện do kernel và do init/rootfs.

Mức cải thiện là **mục tiêu nghiên cứu**, không cam kết phần trăm trước khi có baseline.

### Vì sao tinh giản?

Tinh giản chỉ là phương pháp hỗ trợ Fast Boot, không phải mục tiêu độc lập. **Giảm kích thước kernel không đồng nghĩa boot nhanh hơn**: nhiều option chỉ ảnh hưởng dung lượng chứ không nằm trên critical boot path. Vì vậy nhóm đo riêng kernel init time, thời gian từ `init` đến `READY` và kích thước file để tìm đúng nguyên nhân.

## 4. Nguồn mã và công cụ

| Thành phần | Nguồn / công cụ | Vai trò |
|---|---|---|
| Linux Kernel | [kernel.org](https://www.kernel.org/) | Kernel ARM64, `menuconfig`, rebuild (khóa một phiên bản) |
| QEMU | [QEMU ARM `virt`](https://www.qemu.org/docs/master/system/arm/virt.html) | Máy ARM64 ảo |
| BusyBox | [busybox.net](https://busybox.net/) | Tiện ích user space, shell tối giản |
| Cross-compiler | GCC AArch64 trên Ubuntu | Biên dịch kernel và ứng dụng |
| Boot profiling | `initcall_debug`, `scripts/bootgraph.pl` (có sẵn trong kernel source) | Tìm initcall tốn thời gian, làm căn cứ chỉnh `.config` |
| Initramfs | Nhóm tự đóng gói (không dùng Buildroot) | Rootfs, init, service |
| `early-display-service` | Nhóm tự viết (C) | Mô phỏng app màn hình, tạo mốc đo |
| Benchmark scripts | Nhóm tự viết | Chạy QEMU, ghi log, xuất bảng/biểu đồ |

## 5. Hai phiên bản so sánh

| Phiên bản | Kernel | Init/service | Mục đích |
|---|---|---|---|
| **Baseline** | Kernel gốc (`defconfig` arm64, boot được) | Rootfs chung | Lấy mốc ban đầu |
| **Custom** | Kernel đã tùy chỉnh bằng `menuconfig` / tham số boot | Rootfs chung | Kết quả sau tùy chỉnh |

Hai phiên bản dùng **cùng một rootfs, cùng service** và cùng cấu hình QEMU (CPU/RAM/machine), nên khác biệt đo được chủ yếu do kernel. Mức độ tùy chỉnh của bản Custom làm đến đâu thì **ghi lại đến đó** bằng config diff kèm lý do; không cần build riêng một bản cho từng thay đổi. Nếu còn thời gian mới tinh giản thêm init/rootfs, và khi đó phải báo riêng.

## 6. Yêu cầu và tiêu chí đo

| Mã | Yêu cầu | Minh chứng |
|---|---|---|
| FR-01 | Hệ thống ARM64 boot được trên QEMU | Console và boot log |
| FR-02 | Service tự chạy và báo `READY` | Log có timestamp |
| FR-03 | Kernel tùy chỉnh vẫn đủ chức năng | Test sau rebuild |
| FR-04 | Tác vụ nền chạy sau `READY` và vẫn hoàn tất | Thứ tự timestamp |
| FR-05 | Chạy lại được benchmark | Script và log nhiều lần chạy |

| Chỉ số | Vai trò |
|---|---|
| **Boot-to-service-ready** | Chỉ số chính: từ mốc boot đã định nghĩa đến khi service báo sẵn sàng |
| **Kernel initialization time** | Tách phần kernel khỏi phần user space |
| **Kernel image / initramfs size** | Chỉ số phụ |

**Lưu ý phép đo:** host x86 chạy QEMU aarch64 bằng TCG (emulation) nên số đo có nhiễu. Giữ môi trường nhất quán, chạy nhiều lần, báo cáo trung vị và dao động.

## 7. Kịch bản demo

1. **Màn hình sẵn sàng:** chạy QEMU, quan sát tiến trình boot và `AUTOMOTIVE DISPLAY READY` cùng timestamp trên console; xác nhận service đang chạy.
2. **Tùy chỉnh kernel có căn cứ:** trình bày biểu đồ `bootgraph` trước/sau, so sánh `.config`, giải thích vì sao QEMU ARM64 không cần các thành phần đã bỏ; boot bản custom chứng minh không mất chức năng.
3. **So sánh Fast Boot:** chạy Baseline và Custom (hoặc phát lại log đã đo nhiều lần), hiển thị bảng/biểu đồ boot-to-ready và kernel init time; giải thích phần nào giảm thời gian thật, phần nào chỉ giảm dung lượng.

## 8. Phạm vi

**Bắt buộc:** kernel ARM64 từ source; QEMU; BusyBox/initramfs; service giả lập; profiling bằng `initcall_debug`; kernel configuration/rebuild; boot optimization; benchmark; test chức năng.

**Không làm:** soft real-time/PREEMPT_RT; scheduler optimization; mô phỏng cả ô tô; board vật lý; Buildroot; bootloader; viết driver/module kernel; ứng dụng giải trí đầy đủ.

**Không làm thêm:** giao diện đồ họa (framebuffer/DRM).

## 9. Sản phẩm bàn giao

1. Kernel baseline và custom, kèm `.config` và bản so sánh cấu hình.
2. Initramfs và mã nguồn `early-display-service`.
3. Script build, chạy QEMU, benchmark; biểu đồ `bootgraph` của các phiên bản.
4. Log boot Baseline và Custom, bảng đo và biểu đồ.
5. Minh chứng kiểm thử chức năng.
6. Báo cáo cuối kỳ và slide tiếng Anh; video demo dự phòng.

## 10. Rủi ro và biện pháp

| Rủi ro | Cách xử lý |
|---|---|
| Tắt nhầm option làm kernel không boot | Giữ baseline; khi tinh giản, đổi dần và boot thử trong quá trình làm (không cần lưu từng bước), chỉ ghi lại bản cuối |
| Kernel nhỏ hơn nhưng không boot nhanh hơn | Đo kernel init và service ready riêng; giải thích đúng kết quả |
| Số đo QEMU bị nhiễu | Môi trường nhất quán, nhiều lượt, thống kê dao động |
| Nhanh chỉ vì dời việc ra sau `READY` | Kiểm tra tác vụ nền vẫn hoàn tất; báo riêng thời gian sẵn sàng chức năng chính và toàn hệ thống |

## 11. Kết luận

Một màn hình ô tô không cần chờ toàn bộ dịch vụ mới hiển thị trạng thái ban đầu. Nhóm xây dựng Linux ARM64 mô phỏng có service ưu tiên, tùy chỉnh kernel cho đúng thành phần cần thiết, sắp xếp boot sequence để service sẵn sàng sớm, rồi đo và kiểm chứng. Phần tạo giá trị là **cơ chế boot, cấu hình kernel, tính tái lập của benchmark và kết quả kiểm chứng**.

---

### Tài liệu nền tảng

- Linux Kernel: https://www.kernel.org/
- QEMU ARM64 `virt`: https://www.qemu.org/docs/master/system/arm/virt.html
- BusyBox: https://busybox.net/
- Initramfs: https://docs.kernel.org/filesystems/ramfs-rootfs-initramfs.html

*Tài liệu là phương án triển khai dự kiến, chưa phải kết quả nghiệm thu.*
