#!/usr/bin/env python3
"""
Hand-ported susfs hunks for places where LineageOS's msm-4.9 has diverged from
the tree susfs4ksu's kernel-4.9 patch was generated against.

fs/notify/fdinfo.c
    Hunk 4 of 50_add_susfs_in_kernel-4.9.patch rejects here. This tree carries a
    backported inotify fdinfo that calls inotify_mark_user_mask(mark) and prints
    a literal "ignored_mask:0", whereas the patch expects the older form with a
    local `u32 mask = mark->mask & IN_ALL_EVENTS` and mark->ignored_mask.
    The susfs behaviour is unchanged: for a non-root app process looking at an
    inode flagged INODE_STATE_SUS_KSTAT, report the re-resolved path's inode
    instead of the real one.

fs/namespace.c, fs/internal.h
    KernelSU-Next's kernel/Makefile injects can_umount()/path_umount() into
    fs/namespace.c at Makefile-parse time, because 4.9 predates path_umount()
    (added upstream in 5.9). That injection is too late: kbuild compiles core-y
    (which includes fs/) BEFORE it descends into drivers/, so fs/namespace.o is
    built without the function and vmlinux fails to link with
    "undefined reference to `path_umount'". Pre-injecting here fixes the
    ordering; the Makefile's own grep then finds it and skips.

Idempotent; --revert undoes it.
"""

import argparse
import sys
from pathlib import Path

MARK = "KSU_SUSFS_FDINFO_FIXUP"

ORIG = """\t\tseq_printf(m, "inotify wd:%x ino:%lx sdev:%x mask:%x ignored_mask:0 ",
\t\t\t   inode_mark->wd, inode->i_ino, inode->i_sb->s_dev,
\t\t\t   inotify_mark_user_mask(mark));
\t\tshow_mark_fhandle(m, inode);
\t\tseq_putc(m, '\\n');
\t\tiput(inode);
"""

NEW = """\t\t/* """ + MARK + """ */
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\t\tif (likely(current->susfs_task_state & TASK_STRUCT_NON_ROOT_USER_APP_PROC) &&
\t\t\t\tunlikely(inode->i_state & INODE_STATE_SUS_KSTAT)) {
\t\t\tstruct path path;
\t\t\tchar *pathname = kmalloc(PAGE_SIZE, GFP_KERNEL);
\t\t\tchar *dpath;

\t\t\tif (!pathname) {
\t\t\t\tgoto out_seq_printf;
\t\t\t}
\t\t\tdpath = d_path(&file->f_path, pathname, PAGE_SIZE);
\t\t\tif (!dpath) {
\t\t\t\tgoto out_free_pathname;
\t\t\t}
\t\t\tif (kern_path(dpath, 0, &path)) {
\t\t\t\tgoto out_free_pathname;
\t\t\t}
\t\t\tseq_printf(m, "inotify wd:%x ino:%lx sdev:%x mask:%x ignored_mask:0 ",
\t\t\t\t   inode_mark->wd, path.dentry->d_inode->i_ino,
\t\t\t\t   path.dentry->d_inode->i_sb->s_dev,
\t\t\t\t   inotify_mark_user_mask(mark));
\t\t\tshow_mark_fhandle(m, path.dentry->d_inode);
\t\t\tseq_putc(m, '\\n');
\t\t\tiput(inode);
\t\t\tpath_put(&path);
\t\t\tkfree(pathname);
\t\t\treturn;
out_free_pathname:
\t\t\tkfree(pathname);
\t\t}
out_seq_printf:
#endif
""" + ORIG


UMOUNT_ANCHOR = "static bool is_mnt_ns_file(struct dentry *dentry)"

# Must start at column 0 so KernelSU-Next's Makefile greps ("^static int
# can_umount", "^int path_umount") find these and skip its own injection.
UMOUNT_CODE = """static int can_umount(const struct path *path, int flags)
{
\tstruct mount *mnt = real_mount(path->mnt);

\tif (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))
\t\treturn -EINVAL;
\tif (!may_mount())
\t\treturn -EPERM;
\tif (path->dentry != path->mnt->mnt_root)
\t\treturn -EINVAL;
\tif (!check_mnt(mnt))
\t\treturn -EINVAL;
\tif (mnt->mnt.mnt_flags & MNT_LOCKED)
\t\treturn -EINVAL;
\tif (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))
\t\treturn -EPERM;
\treturn 0;
}

int path_umount(struct path *path, int flags)
{
\tstruct mount *mnt = real_mount(path->mnt);
\tint ret;

\tret = can_umount(path, flags);
\tif (!ret)
\t\tret = do_umount(mnt, flags);
\tdput(path->dentry);
\tmntput_no_expire(mnt);
\treturn ret;
}

"""

INTERNAL_ANCHOR = "extern void __init mnt_init(void);"
INTERNAL_DECL = "int path_umount(struct path *path, int flags);"


def patch_umount(root, revert):
    """Pre-inject path_umount so fs/namespace.o is built with it."""
    ns = root / "fs/namespace.c"
    ih = root / "fs/internal.h"
    t = ns.read_text()
    changed = False

    if revert:
        if UMOUNT_CODE in t:
            ns.write_text(t.replace(UMOUNT_CODE, "", 1))
            changed = True
        h = ih.read_text()
        if INTERNAL_DECL in h:
            ih.write_text(h.replace("\n" + INTERNAL_DECL, "", 1))
            changed = True
        print("  path_umount: " + ("reverted" if changed else "not present"))
        return

    if "int path_umount" in t:
        print("  path_umount: already present in fs/namespace.c")
    else:
        if UMOUNT_ANCHOR not in t:
            sys.exit("fs/namespace.c: anchor for path_umount injection not found")
        ns.write_text(t.replace(UMOUNT_ANCHOR, UMOUNT_CODE + UMOUNT_ANCHOR, 1))
        print("  path_umount: injected into fs/namespace.c (pre-build)")

    h = ih.read_text()
    if "int path_umount" in h:
        print("  path_umount: already declared in fs/internal.h")
    elif INTERNAL_ANCHOR in h:
        ih.write_text(h.replace(INTERNAL_ANCHOR,
                                INTERNAL_ANCHOR + "\n" + INTERNAL_DECL, 1))
        print("  path_umount: declared in fs/internal.h")
    else:
        sys.exit("fs/internal.h: mnt_init anchor not found")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kernel_root")
    ap.add_argument("--revert", action="store_true")
    a = ap.parse_args()

    patch_umount(Path(a.kernel_root), a.revert)

    p = Path(a.kernel_root) / "fs/notify/fdinfo.c"
    text = p.read_text()

    if a.revert:
        if MARK not in text:
            print("  fdinfo fixup: not present")
            return
        p.write_text(text.replace(NEW, ORIG, 1))
        print("  fdinfo fixup: reverted")
        return

    if MARK in text:
        print("  fdinfo fixup: already applied")
        return
    if ORIG not in text:
        sys.exit("fs/notify/fdinfo.c: expected inotify_fdinfo body not found - "
                 "the tree changed, re-port hunk 4 by hand")
    p.write_text(text.replace(ORIG, NEW, 1))
    # drop the .rej/.orig left by patch(1)
    for junk in ("fs/notify/fdinfo.c.rej", "fs/notify/fdinfo.c.orig"):
        (Path(a.kernel_root) / junk).unlink(missing_ok=True)
    print("  fdinfo fixup: applied (hand-ported hunk 4)")


if __name__ == "__main__":
    main()
