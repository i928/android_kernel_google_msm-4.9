# KernelSU-Next + SUSFS for Pixel 3 XL (crosshatch), LineageOS 22.2

Adds KernelSU-Next and SUSFS to `kernel/google/msm-4.9` (4.9.337, **non-GKI**).

**Confirmed working on device.** The KernelSU Next manager reports Working
(LEGACY), Version 12798, Hook mode Manual, Mount system Magic_Mount, SuSFS
Supported | v1.5.5 (NON-GKI). Build side: 183 `ksu_*` and 82 `susfs_*` symbols
in `vmlinux`.

Lives in the kernel repo itself (`ksu_susfs/` at the kernel root) on branch
`pixel3xl-ksu-susfs`, versioned alongside the tree it patches.
`~/lin22/ksu_susfs` is a symlink to it.

Note `repo sync` checks out whatever revision the manifest names — currently
`pixel3xl-add-exfat`, which does **not** carry this branch. So after a sync,
`git checkout pixel3xl-ksu-susfs` first, then run the script. Point the manifest
at `pixel3xl-ksu-susfs` if you want KSU restored by sync alone.

## Use

```bash
~/lin22/ksu_susfs/add_ksu_susfs.sh            # install
~/lin22/ksu_susfs/add_ksu_susfs.sh --clean    # remove

cd ~/lin22 && source build/envsetup.sh && breakfast crosshatch && mka bootimage
# -> out/target/product/crosshatch/boot.img
```

Kernel edits do **not** survive `repo sync`, so re-run the script after any sync.
It is idempotent and fully offline — everything is vendored here (536 KB), which
matters on a metered connection.

Override the target tree with `KERNEL_ROOT=/path/to/kernel`.

## What it installs

| Component | Source | Pin |
|---|---|---|
| KernelSU-Next | `i928/KSU-Next` branch `next-susfs_v1.5.5-v1.5.7` | commit `a08c7bd`, `KSU_VERSION=12798` |
| SUSFS | `gitlab.com/simonpunk/susfs4ksu` branch `kernel-4.9` | commit `41ba0b5`, v1.5.5 NON-GKI |

Exact provenance is in `VERSIONS.txt`.

## Why these versions

- susfs4ksu's `kernel-4.9` branch is **v1.5.5, VARIANT "NON-GKI"**, and the
  KSU-Next branch `next-susfs_v1.5.5-v1.5.7` is written against exactly that
  API. It keeps the flat `kernel/` layout susfs expects (KSU-Next v3.x split
  into `core/`+`hook/`+`feature/`, which susfs's patch does not target).
- That KSU-Next branch **already ships the susfs KSU-side**, so
  `kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch` is deliberately
  **not** applied — doing so would double-patch.

## Non-obvious things this handles

**Manual hooks, not kprobes.** `b1c1_defconfig` has no `CONFIG_KPROBES`, and
KSU-Next's `CONFIG_KSU_KPROBES_HOOK` depends on it, so the five hooks are called
directly (`apply_manual_hooks.py`):

| File | Function | Hook |
|---|---|---|
| `fs/open.c` | `SYSCALL_DEFINE3(faccessat)` | `ksu_handle_faccessat` |
| `fs/stat.c` | `vfs_fstatat` | `ksu_handle_stat` |
| `fs/read_write.c` | `vfs_read` | `ksu_handle_vfs_read` |
| `fs/exec.c` | `do_execveat_common` | `ksu_handle_execveat` |
| `drivers/input/input.c` | `input_handle_event` | `ksu_handle_input_handle_event` |

All insertions go after the enclosing function's declarations
(`-Wdeclaration-after-statement`). `input_handle_event` additionally needs its
`int disposition = input_get_disposition(...)` declaration split, because the
hook must run before that call but cannot precede a declaration.

**`path_umount` link failure (`apply_tree_fixups.py`).** 4.9 predates
`path_umount()` (added upstream in 5.9). KSU-Next's `kernel/Makefile` injects it
into `fs/namespace.c`, but *too late*: kbuild compiles `core-y` (including
`fs/`) before it descends into `drivers/` to parse that Makefile, so
`namespace.o` is built without it and `vmlinux` fails with
`undefined reference to 'path_umount'`. The fix pre-injects `can_umount()` and
`path_umount()` before the build; the Makefile's own greps (`^static int
can_umount`, `^int path_umount`) then find them and skip.

**`fs/notify/fdinfo.c` hunk 4 (`apply_tree_fixups.py`).** This is the one
expected reject from `50_add_susfs_in_kernel-4.9.patch`. LineageOS's msm-4.9
carries a backported inotify fdinfo that uses `inotify_mark_user_mask(mark)` and
prints a literal `ignored_mask:0`, while the patch expects the older
`u32 mask = mark->mask & IN_ALL_EVENTS` with `mark->ignored_mask`. Hunk 4 is
hand-ported with susfs behaviour preserved. Any *other* reject aborts the script.

**No network at build time.** KSU-Next's Makefile normally derives `KSU_VERSION`
from `git rev-list --count` and runs `git fetch --unshallow` to do it. That is
removed from the vendored copy and the version hardcoded to 12798
(= 10000 + 2598 commits + 200), which is the value a full clone would produce.

**`cred.usage` is `atomic_t` here.** Unlike the sunfish msm-4.14 tree (where it
was widened to `atomic_long_t` and broke the `get_cred_rcu()` injection), this
kernel needs no such fix — the stock `atomic_inc_not_zero()` injection is
correct.

## Options

`CONFIG_KSU=y` plus the SUSFS set (SUS_PATH, SUS_MOUNT, SUS_KSTAT,
SUS_OVERLAYFS, TRY_UMOUNT, SPOOF_UNAME, SPOOF_CMDLINE_OR_BOOTCONFIG,
OPEN_REDIRECT, HIDE_KSU_SUSFS_SYMBOLS, magic mount, auto-add variants).

`CONFIG_KSU_SUSFS_SUS_SU` is left **off**: it is the kprobe-based `su` path and
this kernel has no `CONFIG_KPROBES`. The manual sucompat hooks cover it.

`CONFIG_KSU` depends on `CONFIG_OVERLAY_FS`, already `=y` in this defconfig; the
script asserts this.

## Manager app

Use a KernelSU-**Next** manager matching kernel `KSU_VERSION=12798`. The stock
KernelSU manager is a different project and will not pair with this.

## Status

Built, flashed, and booted. Manager pairs with the kernel and susfs reports
v1.5.5 (NON-GKI).

Note the ROM zip built on 2026-08-12 predates this and carries the pre-KSU
kernel. To ship a zip with KSU baked in, rebuild with `mka bacon` after running
this script; otherwise flash `boot.img` on top of that ROM.
