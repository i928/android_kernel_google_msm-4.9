#!/usr/bin/env bash
#
# Add KernelSU-Next + SUSFS to the Pixel 3 XL (crosshatch) msm-4.9 kernel.
#
# Kernel edits do not survive `repo sync`, so this script is re-runnable and
# self-contained: everything it installs is vendored under this directory and
# it never needs network access.
#
#   ./add_ksu_susfs.sh            install
#   ./add_ksu_susfs.sh --clean    remove
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL="${KERNEL_ROOT:-$HOME/lin22/kernel/google/msm-4.9}"
DEFCONFIG="$KERNEL/arch/arm64/configs/b1c1_defconfig"
SUSFS="$HERE/susfs_kernel_patches"
MARK="# KSU_SUSFS"

CONFIGS=(
  CONFIG_KSU=y
  CONFIG_KSU_SUSFS=y
  CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
  CONFIG_KSU_SUSFS_SUS_PATH=y
  CONFIG_KSU_SUSFS_SUS_MOUNT=y
  CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
  CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
  CONFIG_KSU_SUSFS_SUS_KSTAT=y
  CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
  CONFIG_KSU_SUSFS_TRY_UMOUNT=y
  CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_ENABLE_LOG=y
  CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
  CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
  CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
  # SUS_SU is left off: it is the kprobe-based su path, and this kernel has no
  # CONFIG_KPROBES. The manual hooks below cover sucompat instead.
  "# CONFIG_KSU_SUSFS_SUS_SU is not set"
)

die() { echo "error: $*" >&2; exit 1; }
[ -d "$KERNEL" ] || die "kernel tree not found: $KERNEL"
[ -f "$DEFCONFIG" ] || die "defconfig not found: $DEFCONFIG"

# ---------------------------------------------------------------- clean
if [ "${1:-}" = "--clean" ]; then
  echo "removing KernelSU-Next + SUSFS from $KERNEL"
  python3 "$HERE/apply_manual_hooks.py" "$KERNEL" --revert || true
  python3 "$HERE/apply_tree_fixups.py" "$KERNEL" --revert || true

  # susfs kernel-side patch
  if [ -f "$SUSFS/50_add_susfs_in_kernel-4.9.patch" ]; then
    (cd "$KERNEL" && patch -p1 -R --forward --silent \
        < "$SUSFS/50_add_susfs_in_kernel-4.9.patch" || true)
  fi

  rm -rf "$KERNEL/KernelSU-Next" "$KERNEL/drivers/kernelsu"
  rm -f "$KERNEL/fs/susfs.c" "$KERNEL/fs/sus_su.c"
  rm -f "$KERNEL/include/linux/susfs.h" "$KERNEL/include/linux/susfs_def.h" \
        "$KERNEL/include/linux/sus_su.h"

  sed -i "/$MARK/d" "$KERNEL/drivers/Makefile" "$KERNEL/drivers/Kconfig" 2>/dev/null || true
  sed -i '/obj-\$(CONFIG_KSU) += kernelsu\//d' "$KERNEL/drivers/Makefile"
  sed -i '/source "drivers\/kernelsu\/Kconfig"/d' "$KERNEL/drivers/Kconfig"
  sed -i '/^CONFIG_KSU/d;/^# CONFIG_KSU/d' "$DEFCONFIG"

  # get_cred_rcu is injected into cred.h by KernelSU-Next's Makefile at build time
  sed -i '/get_cred_rcu/,+8{/get_cred_rcu/,+8d}' "$KERNEL/include/linux/cred.h" 2>/dev/null || true

  echo "clean complete"
  exit 0
fi

# ---------------------------------------------------------------- install
echo "installing KernelSU-Next + SUSFS into $KERNEL"
cat "$HERE/VERSIONS.txt"
echo

# 1. KernelSU-Next driver
echo "[1/5] KernelSU-Next driver"
rm -rf "$KERNEL/KernelSU-Next"
cp -a "$HERE/KernelSU-Next" "$KERNEL/KernelSU-Next"
ln -sfn ../KernelSU-Next/kernel "$KERNEL/drivers/kernelsu"

grep -q 'obj-$(CONFIG_KSU)' "$KERNEL/drivers/Makefile" || \
  echo "obj-\$(CONFIG_KSU) += kernelsu/            $MARK" >> "$KERNEL/drivers/Makefile"

if ! grep -q 'drivers/kernelsu/Kconfig' "$KERNEL/drivers/Kconfig"; then
  # must land inside the top-level "menu Device Drivers" block
  python3 - "$KERNEL/drivers/Kconfig" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
i = t.rstrip().rfind("endmenu")
p.write_text(t[:i] + 'source "drivers/kernelsu/Kconfig"            # KSU_SUSFS\n\n' + t[i:])
PY
fi
echo "      installed (KSU_VERSION pinned 12798, no network at build time)"

# 2. susfs sources
echo "[2/5] susfs sources"
cp -a "$SUSFS/fs/susfs.c" "$SUSFS/fs/sus_su.c" "$KERNEL/fs/"
cp -a "$SUSFS/include/linux/." "$KERNEL/include/linux/"
echo "      fs/susfs.c fs/sus_su.c include/linux/{susfs.h,susfs_def.h,sus_su.h}"

# 3. susfs kernel-side patch
echo "[3/5] susfs kernel patch (50_add_susfs_in_kernel-4.9.patch)"
# The patch cannot be probed with `patch -R --dry-run`: hunk 4 of
# fs/notify/fdinfo.c always rejects on this tree, so the result is only ever
# partially applied and a reverse test never succeeds. Detect via a file the
# patch touches instead.
if grep -q susfs "$KERNEL/fs/namei.c" 2>/dev/null; then
  echo "      already applied, skipping"
else
  # clear stale rejects so the check below only sees this run's
  (cd "$KERNEL" && find . -name '*.rej' -not -path './fs/exfat/*' -delete)
  # Hunk 4 of fs/notify/fdinfo.c is expected to reject (this tree backported a
  # newer inotify fdinfo); apply_tree_fixups.py hand-ports it. Any other reject
  # is a real problem.
  (cd "$KERNEL" && patch -p1 --forward --fuzz=3 \
      < "$SUSFS/50_add_susfs_in_kernel-4.9.patch") || true
  rej=$(cd "$KERNEL" && find . -name '*.rej' -not -path './fs/exfat/*' | sed 's|^\./||' | sort)
  if [ -n "$rej" ] && [ "$rej" != "fs/notify/fdinfo.c.rej" ]; then
    die "unexpected patch rejects:
$rej"
  fi
fi
python3 "$HERE/apply_tree_fixups.py" "$KERNEL"
# NOTE: kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch is deliberately NOT
# applied. This KSU-Next branch (next-susfs_v1.5.5-v1.5.7) already ships the
# susfs KSU-side; applying it again would double-patch.

# 4. manual non-kprobe hooks
echo "[4/5] manual hooks (no CONFIG_KPROBES on this kernel)"
python3 "$HERE/apply_manual_hooks.py" "$KERNEL"

# 5. defconfig
echo "[5/5] defconfig"
sed -i '/^CONFIG_KSU/d;/^# CONFIG_KSU/d' "$DEFCONFIG"
for c in "${CONFIGS[@]}"; do
  [[ "$c" == \#* ]] && echo "$c" >> "$DEFCONFIG" || echo "$c" >> "$DEFCONFIG"
done
grep -q '^CONFIG_OVERLAY_FS=y' "$DEFCONFIG" || \
  die "CONFIG_OVERLAY_FS=y missing - KSU-Next's CONFIG_KSU depends on it"
echo "      $(grep -c '^CONFIG_KSU' "$DEFCONFIG") options added"

echo
echo "done. build with:"
echo "  cd ~/lin22 && source build/envsetup.sh && breakfast crosshatch && mka bootimage"
