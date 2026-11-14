#!/bin/bash
# Build the kernel Image out-of-tree: scripts/build-linux.sh <baseline|custom>
#   baseline -> build/kernel-baseline  (config: src/linux arm64 defconfig = baseline reference)
#   custom   -> build/kernel-custom    (config: custom/defconfig)
# Change the custom config, then save it back:
#   make -C src/linux O=$PWD/build/kernel-custom ARCH=arm64 menuconfig
#   make -C src/linux O=$PWD/build/kernel-custom ARCH=arm64 savedefconfig
#   cp build/kernel-custom/defconfig custom/defconfig
set -eu
P="$(cd "$(dirname "$0")/.." && pwd)"
N="${1:?usage: $0 <baseline|custom>}"
case "$N" in baseline|custom) ;; *) echo "usage: $0 <baseline|custom>" >&2; exit 2 ;; esac
O="$P/build/kernel-$N"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p "$O"
if [ ! -f "$O/.config" ]; then
	case "$N" in
	baseline) make -C "$P/src/linux" O="$O" defconfig ;;
	custom) cp "$P/custom/defconfig" "$O/.config"; make -C "$P/src/linux" O="$O" olddefconfig ;;
	esac
fi
time make -C "$P/src/linux" O="$O" -j"$(nproc)" Image
