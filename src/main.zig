const std = @import("std");
const linux = std.os.linux;

const PT_LOAD: u32 = 1;

const PROT_READ: u32 = 0x1;
const PROT_WRITE: u32 = 0x2;
const PROT_EXEC: u32 = 0x4;

const MAP_PRIVATE: u32 = 0x02;
const MAP_FIXED: u32 = 0x10;
const MAP_ANONYMOUS: u32 = 0x20;

const Elf64_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

const Elf64_Phdr = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

fn exitNow(code: u8) noreturn {
    _ = linux.syscall1(.exit_group, @as(usize, code));
    unreachable;
}

fn openAt(path: [*:0]const u8, flags: usize) ?i32 {
    const fd = linux.syscall3(.openat, @as(usize, -100), @intFromPtr(path), flags);
    const signed: isize = @bitCast(fd);
    if (signed < 0) return null;
    return @intCast(signed);
}

fn mmapFile(fd: i32, addr: usize, len: usize, prot: u32, offset: u64) ?usize {
    const ret = linux.syscall6(
        .mmap,
        addr,
        len,
        prot,
        MAP_PRIVATE | MAP_FIXED,
        @intCast(fd),
        offset,
    );
    const signed: isize = @bitCast(ret);
    if (signed < 0) return null;
    return ret;
}

fn mmapAnon(addr: usize, len: usize, prot: u32) ?usize {
    const ret = linux.syscall6(
        .mmap,
        addr,
        len,
        prot,
        MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED,
        @as(usize, 0),
        0,
    );
    const signed: isize = @bitCast(ret);
    if (signed < 0) return null;
    return ret;
}

const StackView = struct {
    argc: usize,
    argv: [*]?[*:0]u8,
    envp: [*]?[*:0]u8,
};

/// The AArch64 Linux ABI places at SP:
///   [0]      : argc
///   [8..]    : argv[0..argc]
///   [..]     : NULL
///   [..]     : envp[0..]
///   [..]     : NULL
///   [..]     : auxv pairs, ended by (AT_NULL, 0)
fn parseStack(sp: usize) StackView {
    const p: [*]usize = @ptrFromInt(sp);
    const argc = p[0];
    const argv: [*]?[*:0]u8 = @ptrCast(@alignCast(&p[1]));
    const envp: [*]?[*:0]u8 = @ptrCast(@alignCast(&p[1 + argc + 1]));
    return .{ .argc = argc, .argv = argv, .envp = envp };
}

/// The loader's job:
///   1. Read ZPROOT_REAL_INTERP from envp.
///   2. Open the real interpreter from the rootfs.
///   3. Parse its ELF header, mmap PT_LOAD segments.
///   4. Read its entry point from e_entry.
///   5. Rebuild the stack with the same argc/argv/envp/auxv,
///      but AT_BASE updated to the interpreter's load base.
///   6. Jump to the interpreter's entry point.
///
/// Steps 1 and 2 are implemented here. Steps 3-6 are the work of M10.
fn loaderMain(sp: usize) noreturn {
    const stack = parseStack(sp);

    var real_interp: ?[*:0]const u8 = null;

    var i: usize = 0;
    while (stack.envp[i]) |e| : (i += 1) {
        const s = std.mem.span(e);
        if (std.mem.startsWith(u8, s, "ZPROOT_REAL_INTERP=")) {
            real_interp = @ptrCast(e + "ZPROOT_REAL_INTERP=".len);
            break;
        }
    }

    const path = real_interp orelse exitNow(127);

    const fd = openAt(path, 0) orelse exitNow(127);

    // Read the ELF header to find PT_LOAD segments.
    var ehdr: Elf64_Ehdr = undefined;
    const read_ret = linux.syscall6(
        .pread64,
        @intCast(fd),
        @intFromPtr(&ehdr),
        @sizeOf(Elf64_Ehdr),
        0,
        0,
        0,
    );
    const rs: isize = @bitCast(read_ret);
    if (rs < 0 or rs != @sizeOf(Elf64_Ehdr)) exitNow(127);

    if (ehdr.e_phnum == 0) exitNow(127);

    // mmap each PT_LOAD segment at its p_vaddr.
    var ph_i: u16 = 0;
    while (ph_i < ehdr.e_phnum) : (ph_i += 1) {
        var phdr: Elf64_Phdr = undefined;
        const off = ehdr.e_phoff + @as(u64, ph_i) * @sizeOf(Elf64_Phdr);
        const ph_ret = linux.syscall6(
            .pread64,
            @intCast(fd),
            @intFromPtr(&phdr),
            @sizeOf(Elf64_Phdr),
            off,
            0,
            0,
        );
        const phs: isize = @bitCast(ph_ret);
        if (phs < 0 or phs != @sizeOf(Elf64_Phdr)) exitNow(127);

        if (phdr.p_type != PT_LOAD) continue;

        const addr: usize = @intCast(phdr.p_vaddr);
        const len: usize = @intCast(phdr.p_memsz);
        const file_len: usize = @intCast(phdr.p_filesz);

        var prot: u32 = 0;
        if (phdr.p_flags & 0x1 != 0) prot |= PROT_READ;
        if (phdr.p_flags & 0x2 != 0) prot |= PROT_WRITE;
        if (phdr.p_flags & 0x4 != 0) prot |= PROT_EXEC;

        if (file_len > 0) {
            _ = mmapFile(fd, addr, len, prot, phdr.p_offset) orelse exitNow(127);
        } else {
            _ = mmapAnon(addr, len, prot) orelse exitNow(127);
        }
    }

    // Update AT_BASE in the auxv to the interpreter's load base.
    // The real interpreter uses AT_BASE to know where it was loaded.
    // auxv starts after envp terminator.
    const auxv_start: usize = @intFromPtr(stack.envp) + (@sizeOf(?[*:0]u8)) * (blk: {
        var j: usize = 0;
        while (stack.envp[j] != null) : (j += 1) {}
        break :blk j + 1;
    });
    const auxv: [*]usize = @ptrFromInt(auxv_start);

    var k: usize = 0;
    while (true) : (k += 2) {
        const key = auxv[k];
        if (key == 0) break;
        if (key == 7) {
            // AT_BASE = 7
            auxv[k + 1] = 0; // will be the interpreter base once we know it
            break;
        }
    }

    // Jump to the interpreter's entry point.
    // On success, this does not return.
    const entry: usize = @intCast(ehdr.e_entry);
    const entry_fn: *const fn () callconv(.C) noreturn = @ptrFromInt(entry);
    entry_fn();
}

export fn _start() callconv(.Naked) noreturn {
    asm volatile(
        \\ mov x0, sp
        \\ b loader_main
    );
}

comptime {
    @export(&loaderMain, .{ .name = "loader_main", .linkage = .strong });
}
