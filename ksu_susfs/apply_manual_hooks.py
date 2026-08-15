#!/usr/bin/env python3
"""
Insert KernelSU-Next manual (non-kprobe) hook call sites into the msm-4.9 tree.

This kernel has no CONFIG_KPROBES in b1c1_defconfig, and KSU-Next's
CONFIG_KSU_KPROBES_HOOK 'depends on KPROBES', so the kprobe path is unavailable
and the five hooks below must be called directly.

Every insertion goes AFTER the enclosing function's local declarations, because
the kernel builds with -Wdeclaration-after-statement.

Idempotent: re-running is a no-op. Use --revert to remove the hooks.
"""

import argparse
import re
import sys
from pathlib import Path

MARK = "KSU_MANUAL_HOOK"

# Each entry: file, extern declaration, anchor line to insert after, hook call.
# 'anchor' is matched literally (first occurrence after 'func' if given).
HOOKS = [
    dict(
        path="fs/open.c",
        func="SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)",
        anchor="\tunsigned int lookup_flags = LOOKUP_FOLLOW;",
        decl="int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n"
             "\t\t\t int *mode, int *flags);",
        call="\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);",
    ),
    dict(
        path="fs/stat.c",
        func="int vfs_fstatat(int dfd, const char __user *filename, struct kstat *stat,",
        anchor="\tunsigned int lookup_flags = 0;",
        decl="int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);",
        call="\tksu_handle_stat(&dfd, &filename, &flag);",
    ),
    dict(
        path="fs/read_write.c",
        func="ssize_t vfs_read(struct file *file, char __user *buf, size_t count, loff_t *pos)",
        anchor="\tssize_t ret;",
        decl="int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n"
             "\t\t\tsize_t *count_ptr, loff_t **pos);",
        call="\tksu_handle_vfs_read(&file, &buf, &count, &pos);",
    ),
    dict(
        path="fs/exec.c",
        func="static int do_execveat_common(int fd, struct filename *filename,",
        anchor="\tint retval;",
        decl="int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\n"
             "\t\t\tvoid *envp, int *flags);",
        call="\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);",
    ),
]


def find_include_anchor(text):
    """Return index just past the final #include block at the top of the file."""
    last = 0
    for m in re.finditer(r"^#include\s+[<\"].*[>\"]\s*$", text, re.M):
        last = m.end()
    if not last:
        sys.exit("could not locate an #include block")
    return last


def add_decl(text, decl):
    if f"{MARK} decl" in text:
        return text, False
    pos = find_include_anchor(text)
    block = f"\n\n/* {MARK} decl */\n#ifdef CONFIG_KSU\n{decl}\n#endif"
    return text[:pos] + block + text[pos:], True


def add_call(text, func, anchor, call):
    if f"{MARK} call" in text:
        return text, False
    fpos = text.find(func)
    if fpos < 0:
        sys.exit(f"function not found: {func[:60]}")
    apos = text.find(anchor, fpos)
    if apos < 0:
        sys.exit(f"anchor not found after {func[:40]}: {anchor.strip()}")
    end = text.index("\n", apos) + 1
    block = f"\n\t/* {MARK} call */\n#ifdef CONFIG_KSU\n{call}\n#endif\n"
    return text[:end] + block + text[end:], True


def patch_input_c(root, revert):
    """drivers/input/input.c needs the declaration split: the hook must run
    before input_get_disposition() but cannot precede a declaration."""
    p = root / "drivers/input/input.c"
    text = p.read_text()
    orig = "\tint disposition = input_get_disposition(dev, type, code, &value);"
    new = (
        "\tint disposition;\n"
        f"\t/* {MARK} call */\n"
        "#ifdef CONFIG_KSU\n"
        "\tksu_handle_input_handle_event(&type, &code, &value);\n"
        "#endif\n"
        "\tdisposition = input_get_disposition(dev, type, code, &value);"
    )
    if revert:
        if new not in text:
            return False
        text = text.replace(new, orig)
        text = re.sub(
            r"\n\n/\* " + MARK + r" decl \*/\n#ifdef CONFIG_KSU\n.*?\n#endif",
            "", text, flags=re.S)
        p.write_text(text)
        return True
    if MARK in text:
        return False
    if orig not in text:
        sys.exit("input_handle_event: expected declaration form not found")
    text = text.replace(orig, new, 1)
    text, _ = add_decl(
        text,
        "int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code,\n"
        "\t\t\t\t  int *value);",
    )
    p.write_text(text)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kernel_root")
    ap.add_argument("--revert", action="store_true")
    args = ap.parse_args()
    root = Path(args.kernel_root)

    changed = 0
    for h in HOOKS:
        p = root / h["path"]
        text = p.read_text()
        if args.revert:
            before = text
            text = re.sub(
                r"\n\n/\* " + MARK + r" decl \*/\n#ifdef CONFIG_KSU\n.*?\n#endif",
                "", text, flags=re.S)
            text = re.sub(
                r"\n\t/\* " + MARK + r" call \*/\n#ifdef CONFIG_KSU\n.*?\n#endif\n",
                "", text, flags=re.S)
            if text != before:
                p.write_text(text)
                print(f"  reverted {h['path']}")
                changed += 1
            continue
        text, d1 = add_decl(text, h["decl"])
        text, d2 = add_call(text, h["func"], h["anchor"], h["call"])
        if d1 or d2:
            p.write_text(text)
            print(f"  hooked {h['path']}")
            changed += 1

    if patch_input_c(root, args.revert):
        print(f"  {'reverted' if args.revert else 'hooked'} drivers/input/input.c")
        changed += 1

    print(f"manual hooks: {changed} file(s) {'reverted' if args.revert else 'patched'}"
          + ("" if changed else " (already in desired state)"))


if __name__ == "__main__":
    main()
