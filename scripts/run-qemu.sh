#!/bin/bash
# Boot a kernel in QEMU ARM64 "virt" with the project initramfs.
# Usage: scripts/run-qemu.sh <baseline|custom> [extra kernel cmdline args]
# Exit QEMU: Ctrl-A then X
set -eu

P="$(cd "$(dirname "$0")/.." && pwd)"
N="${1:?usage: $0 <baseline|custom> [kernel cmdline args]}"
shift
case "$N" in baseline|custom) ;; *) echo "usage: $0 <baseline|custom> [kernel cmdline args]" >&2; exit 2 ;; esac

KERNEL="$P/build/kernel-$N/arch/arm64/boot/Image"
INITRD="$P/build/initramfs.cpio.gz"

for f in "$KERNEL" "$INITRD"; do
	[ -f "$f" ] || { echo "missing: ${f#"$P"/}" >&2; missing=1; }
done
[ -z "${missing:-}" ] || exit 1

exec qemu-system-aarch64 \
	-machine virt -cpu "${QEMU_CPU:-cortex-a72}" -smp 1 -m "${QEMU_MEM:-512M}" \
	-nographic -no-reboot \
	-kernel "$KERNEL" -initrd "$INITRD" \
	-append "console=ttyAMA0 rdinit=/init panic=-1 $*"
