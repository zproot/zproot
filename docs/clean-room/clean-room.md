# Clean-room

zproot is a clean-room reimplementation of [PRoot](https://github.com/proot-me/proot). This document records what sources were consulted, what was deliberately avoided, and how the clean-room boundary is maintained. It exists so that the MIT license on zproot remains legally valid.

## What "clean-room" means here

A clean-room reimplementation is one written from specifications and public documentation, without reading the source code of the original. The goal is to arrive at the same behavior through independent work rather than translation of an existing implementation.

For zproot, the original is PRoot and its derivatives. PRoot is licensed GPL-2.0. Any code derived from it would inherit that license, which would prevent zproot from being distributed under MIT. The clean-room process is what allows the MIT license to apply.

## Clean-room boundary

Established on ***2026-09-12***.

The boundary is the date on which development of zproot began, with no prior exposure to the source code of any GPL project listed under Sources avoided below. All commits after that date were written without consulting those sources.

The original git history was later reset to remove restructuring noise. The clean-room date remains valid because no GPL-derived code was ever introduced into the working tree. Earlier commits, if recovered, will confirm this.

## Sources consulted (allowed)

These are the primary sources from which the implementation is derived.

### Linux man pages

- [`ptrace(2)`](https://man7.org/linux/man-pages/man2/ptrace.2.html) — the syscall at the core of the tracer
- [`seccomp(2)`] — the seccomp filter mechanism
- [`execve(2)`], execveat(2) — program loading
- [`openat(2)`], openat2(2) — path opening
- [`statx(2)`], newfstatat(2) — file metadata
- [`readlinkat(2)`], faccessat(2) — path queries
- [`clone(2)`] — process creation
- [`sigaction(2)`](https://man7.org/linux/man-pages/man2/sigaction.2.html) — signal handling
- [`process_vm_readv(2)`](https://man7.org/linux/man-pages/man2/process_vm_readv.2.html), [`process_vm_writev(2)`](https://man7.org/linux/man-pages/man2/process_vm_writev.2.html) — cross-process memory
- [`wait4(2)`](https://man7.org/linux/man-pages/man2/wait4.2.html), waitid(2) — child process status

### Linux kernel source

- `arch/arm64/include/asm/unistd.h` — aarch64 syscall numbers
- `arch/x86/entry/syscalls/syscall_64.tbl` — x86_64 syscall numbers
- `include/uapi/linux/ptrace.h` — ptrace request constants
- `include/uapi/linux/elf.h` — ELF structures
- `include/uapi/asm-generic/siginfo.h` — signal info layout

### Academic and design documents

- G. Monni, PRoot: A Step Forward for QEMU-User (2015) — the paper describing PRoot's design and approach
- [ELF specification](https://refspecs.linuxfoundation.org/elf/elf.pdf) (TIS ELF 1.2, System V ABI)
- [AArch64 ELF ABI](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst)
- [x86-64 System V ABI](https://gitlab.com/x86-psABIs/x86-64-ABI)

### Public documentation

- PRoot man pages
- `proot --help` output
- PRoot-related blog posts and usage guides
- Android NDK documentation on W^X, SELinux, and app sandboxing
- Termux wiki on ptrace and Android restrictions

### Language and toolchain

- [Zig standard library](https://codeberg.org/ziglang/zig/src/branch/master/lib/std) source (MIT-licensed)
- Zig language reference and release notes

## Sources avoided (not allowed)

None of the following were read, copied, paraphrased, or used as reference during development:

- [proot-me/proot](https://github.com/proot-me/proot) source code
- [termux/termux-proot](https://github.com/termux/termux-proot) source code (including patches)
- [termux/proot](https://github.com/termux/proot-distro) distro scripts
- [oonid/pr](https://github.com/oonid/pr) source code
- Any fork, patch, or derivative of the above

If a contributor has read any of these sources, they must disclose it in their pull request. Contributions from readers of the GPL sources are declined for the same reason.

How the boundary is maintained

### For contributors

Every pull request must contain a statement such as:

> I have not read the source code of proot, termux-proot, proot-distro, or oonid/pr. This contribution is written from the Linux man pages, the ELF specification, and the public PRoot documentation.

If a contributor has read any of those sources, they should say so. The contribution can still be merged if the code is clearly independent, but the maintainer must record the disclosure.

### For reviewers

Reviewers should check that:

- No variable names, comments, or code structure match the upstream GPL projects
- No commit message references a specific upstream commit
- No test fixture is copied from an upstream project's test suite

If a match is found, the file is removed and rewritten from the specifications.

### For new contributors

The [contributing guide](https://github.com/zproot/zproot/tree/master/docs/contributing) points here first. Anyone touching the tracer, the loader, or the path translation logic should read this document before submitting code.

### What this allows

Because zproot is a clean-room implementation:

- It can be released under the [MIT license](https://github.com/zproot/zproot/blob/master/LICENSE)
- It can be vendored into proprietary applications
- It can be dual-licensed without upstream consent
- It can be used in contexts where GPL is not acceptable

None of those rights would be available if any portion of the tracer were derived from PRoot's source.

### What this does not allow

- Copying code from PRoot, termux-proot, or proot-distro at any future date
- Porting a function from PRoot by reading it and rewriting it in Zig (that is not clean-room)
- Using PRoot's test suite as a reference for expected behavior
- Taking the `--change-id`, `--link2symlink`, or similar flag designs directly from PRoot's source without reimplementing them from the man page

Design concepts and interface conventions are not copyrightable. The implementations are. The distinction matters.

### Declaration

zproot's core tracer, path translator, seccomp handler, and `PT_INTERP` loader were written from scratch. The implementation is based on the Linux kernel interface (man pages, syscall tables, ELF specification), the PRoot academic paper, and public usage documentation.

No source code from any GPL-licensed PRoot project was read, copied, or translated during the development of zproot.

Related documents

Document Description
README.md Project overview
docs/architecture/ Architecture and design notes
docs/adr/ Architecture Decision Records
LICENSE MIT license text

Links used in this document

Label URL
PRoot https://github.com/proot-me/proot
termux-proot https://github.com/termux/termux-proot
proot-distro https://github.com/termux/proot-distro
oonid/pr https://github.com/oonid/pr
Zig https://github.com/ziglang/zig
Linux kernel https://github.com/torvalds/linux
ptrace(2) https://man7.org/linux/man-pages/man2/ptrace.2.html
seccomp(2) https://man7.org/linux/man-pages/man2/seccomp.2.html
execve(2) https://man7.org/linux/man-pages/man2/execve.2.html
execveat(2) https://man7.org/linux/man-pages/man2/execveat.2.html
openat(2) https://man7.org/linux/man-pages/man2/openat.2.html
openat2(2) https://man7.org/linux/man-pages/man2/openat2.2.html
statx(2) https://man7.org/linux/man-pages/man2/statx.2.html
clone(2) https://man7.org/linux/man-pages/man2/clone.2.html
sigaction(2) https://man7.org/linux/man-pages/man2/sigaction.2.html
process_vm_readv(2) https://man7.org/linux/man-pages/man2/process_vm_readv.2.html
wait4(2) https://man7.org/linux/man-pages/man2/wait4.2.html
ELF specification https://refspecs.linuxfoundation.org/elf/elf.pdf
AArch64 ELF ABI https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst
x86-64 System V ABI https://gitlab.com/x86-psABIs/x86-64-ABI
