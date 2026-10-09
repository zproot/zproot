# zproot

Android app that runs Linux distributions via a clean-room Zig reimplementation of [PRoot](https://github.com/proot-me/proot) — no root, no Termux required.

## What it does

- Install and run Linux distributions (Alpine, Debian, Ubuntu, and more) on any Android device
- Full package manager support: apk, apt-get, pacman
- Compile and run C, Rust, and other programs inside the guest
- MIT-licensed, small static binary, no GPL obligations inherited from upstream C
- targetSdk 35 (Android 15) — sideload / F-Droid friendly, no Play Store required

## Status

zproot is a work in progress. The core tracer is being written from scratch in Zig, with the following milestones:

| Milestone | Status |
|-----------|--------|
| M1: ptrace syscall loop | done |
| M2: Read syscall arguments | done |
| M3: Path rewriting (openat) | done |
| M4: Longer path via stack scratch | done |
| M5: openat2, statx | done |
| M6: Android seccomp / SIGSYS | done |
| M7: aarch64-linux-android build | done |
| M8: Android APK with path redirect | done |
| M9: Rootfs prefix, Alpine install | in progress |
| M10: PT_INTERP loader | in progress |

The APK lives at [zproot/zproot-android](https://github.com/zproot/zproot-android). If you need something usable today, use [pr](https://github.com/oonid/pr) or [Termux](https://github.com/termux/termux-app).

## Supported distributions (target)

Alpine, Debian, Ubuntu, Arch Linux, Fedora, OpenSUSE, Manjaro, Rocky Linux

## How it works

zproot sits between a Linux program and the Android kernel. It uses Linux `ptrace()` to intercept syscalls and translate filesystem paths, creating a virtual root filesystem without actual root privileges. When the guest calls `openat("/etc/passwd")`, zproot rewrites the syscall argument to point at `/data/data/com.zproot/files/rootfs/etc/passwd`. The kernel opens the real file. The guest sees `/etc/passwd`.

## What the app will bundle

- ***zproot-core*** (Zig) — clean-room reimplementation of the ptrace tracer, path translator, and Android compatibility layer
- ***zproot-cli*** (Zig) — install, login, remove, and manage distributions
- ***Android APK*** (Kotlin + Compose) — install/login/remove UI with embedded terminal

## Android compatibility (planned)

Android enforces several restrictions on app processes that a tracer must work around:

- ***W^X (Write-XOR-Execute)***: prevents executing files in app-writable directories
- ***SELinux***: blocks certain filesystem operations
- ***Zygote seccomp***: blocks 18+ syscalls via BPF filter

## How zproot will handle these

- ***SIGSYS handlers*** — intercept seccomp-blocked syscalls and emulate them in userspace
- ***Loader mechanism*** — stage the tracer's loader in nativeLibraryDir to bypass W^X
- ***Fake root (--change-id=0:0)*** — makes dpkg and apt-get work without real root
- ***CLONE_VM / CLONE_VFORK stripping*** — allows Rust's cargo build to run inside the guest

## Why Zig instead of C

The upstream proot is a mature but complex C codebase (~90 source files). Rewriting it in Zig gives us:

- ***Direct syscall control via std.os.linux*** and inline asm, without an FFI layer
- ***Built-in Android cross-compilation*** — zig build -Dtarget=aarch64-linux-android just works
- ***Compile-time code generation (comptime)*** for multi-architecture register handling
- ***Small static binary*** — no runtime, no libc baggage if we want it
- ***Clean-room licensing*** — MIT, because we own the copyright outright

## Building

Prerequisites

- ***Zig 0.16.0***
- ***Java 17+*** (for the APK, once it exists)

## Build steps (host, x86_64 Linux)

```bash
# Clone
git clone https://github.com/zproot/zproot
cd zproot

# Build the tracer
zig build

# Run against a test binary
./zig-out/bin/zproot /bin/true
```

## Cross-compile for Android

```bash
zig build -Dtarget=aarch64-linux-android
```

## Testing

Unit tests

```bash
zig build test
```

## Integration tests

Once a guest rootfs is wired up:

```bash
# On a connected Android device:
adb shell run-as com.zproot files/usr/bin/zproot-cli test alpine
adb shell run-as com.zproot files/usr/bin/zproot-cli test debian
```

## Project structure

```
zproot/
├── src/                       # Tracer source
│   ├── main.zig               # CLI entry, argument parsing, ptrace loop
│   ├── trace.zig              # ptrace loop, entering/exiting logic
│   ├── regs.zig               # Register access (x86_64, aarch64)
│   ├── memory.zig             # readCString, writeCString, process_vm_readv
│   ├── syscall.zig            # Syscall number tables per architecture
│   ├── path.zig               # Rootfs prefix, passthrough list
│   ├── exec.zig               # doFork, execvpZ
│   └── seccomp.zig            # SIGSYS handler
├── native/                    # Architecture-specific assembly and linker scripts
├── build/                     # Build system configs
├── scripts/                   # Automation scripts
├── test/                      # Tests
├── docs/                      # Documentation
├── examples/                  # Minimal usage examples
├── tools/                     # Custom developer tools
├── third-party/               # Vendored dependencies
├── patches/                   # Patches to dependencies
├── dist/                      # Distribution artifacts
├── releases/                  # Release management
├── assets/                    # Runtime assets
├── configs/                   # Editor and linter configs
├── .github/                   # GitHub configuration
├── build.zig                  # Build graph
├── LICENSE
└── README.md
```

Android frontend lives at [zproot/zproot-android](https://github.com/zproot/zproot-android).

## Documentation

| Document | Description |
|----------|-------------|
| docs/clean-room.md | What sources were consulted and what was avoided (required for MIT) |

## Clean-room statement

zproot is a clean-room reimplementation. No source code from proot, termux-proot, or proot-distro was read, copied, or translated during its development. The implementation is based on:

- The Linux ptrace(2) and seccomp(2) man pages
- The PRoot academic paper (G. Monni, 2015)
- Public PRoot usage documentation and help output
- Linux kernel syscall tables

This is what allows zproot to be released under the MIT license while the upstream C projects remain GPL.

## Credits

- [proot](https://github.com/proot-me/proot) — the original concept and design (GPL-2.0). Not used as source.
- [termux-proot](https://github.com/termux/termux-proot) — Android patch inspiration (GPL-2.0). Not used as source.
- [proot-distro](https://github.com/termux/proot-distro) — distribution plugin design (GPL-3.0). Not used as source.
- [Zig](https://codeberg.org/ziglang/zig) — the language and toolchain.

## License

[MIT](https://github.com/zproot/zproot/blob/master/LICENSE) — see LICENSE.

## Related repositories

- [zproot/zproot](https://github.com/zproot/zproot) — tracer core (this repo)
- [zproot/zproot-android](https://github.com/zproot/zproot-android) — Android frontend
- [zproot/.github](https://github.com/zproot/.github) — organization profile
