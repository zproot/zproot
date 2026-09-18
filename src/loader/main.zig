const std = @import("std");
const linux = std.os.linux;

const PT_LOAD: u32 = 1;

const PROT_READ: u32 = 0x1;
const PROT_WRITE: u32 = 0x2;
const PROT_EXEC: u32 = 0x4;

const MAP_PRIVATE: u32 = 0x02;
const MAP_FIXED: u32 = 0x10;
const MAP_ANONYMOUS: u32 = 0x20;

const AT_NULL: u64 = 0;
const AT_BASE: u64 = 7;

const AT_FDCWD: usize = @bitCast(@as(isize, -100));

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

fn openRead(path: [*:0]const u8) ?i32 {
    const fd = linux.syscall3(.openat, AT_FDCWD, @intFromPtr(path), @as(usize, 0));
    const s: isize = @bitCast(fd);
    if (s < 0) return null;
    return @intCast(s);
}

fn preadFd(fd: i32, buf: []u8, off: u64) ?usize {
    const ret = linux.syscall6(.pread64, @intCast(fd), @intFromPtr(buf.ptr), buf.len, off, 0, 0);
    const s: isize = @bitCast(ret);
    if (s < 0) return null;
    return @intCast(s);
}

fn mmapFile(fd: i32, addr: usize, len: usize, prot: u32, off: u64) bool {
    const ret = linux.syscall6(
        .mmap,
        addr,
        len,
        prot,
        MAP_PRIVATE | MAP_FIXED,
        @intCast(fd),
        off,
    );
    const s: isize = @bitCast(ret);
    return s >= 0;
}

fn mmapAnon(addr: usize, len: usize, prot: u32) bool {
    const ret = linux.syscall6(
        .mmap,
        addr,
        len,
        prot,
        MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED,
        @as(usize, 0),
        0,
    );
    const s: isize = @bitCast(ret);
    return s >= 0;
}

fn findEnv(envp: [*]?[*:0]u8, key: []const u8) ?[*:0]const u8 {
    var i: usize = 0;
    while (envp[i]) |e| : (i += 1) {
        const s = std.mem.span(e);
        if (s.len > key.len and s[key.len] == '=' and
            std.mem.eql(u8, s[0..key.len], key))
        {
            return @ptrCast(e + key.len + 1);
        }
    }
    return null;
}

fn countEnv(envp: [*]?[*:0]u8) usize {
    var i: usize = 0;
    while (envp[i] != null) : (i += 1) {}
    return i;
}

fn stackArgc(sp: usize) usize {
    const p: [*]usize = @ptrFromInt(sp);
    return p[0];
}

fn stackEnvp(sp: usize) [*]?[*:0]u8 {
    const argc = stackArgc(sp);
    const p: [*]usize = @ptrFromInt(sp);
    return @ptrCast(@alignCast(&p[1 + argc + 1]));
}

fn stackAuxv(sp: usize) [*]u64 {
    const envp = stackEnvp(sp);
    const env_count = countEnv(envp);
    const after: [*]usize = @ptrCast(envp);
    return @ptrCast(@alignCast(&after[env_count + 1]));
}

export fn loaderMain(sp: usize) callconv(.c) noreturn {
    const envp = stackEnvp(sp);
    const real_interp = findEnv(envp, "ZPROOT_REAL_INTERP") orelse exitNow(127);

    const fd = openRead(real_interp) orelse exitNow(127);

    var ehdr: Elf64_Ehdr = undefined;
    if (preadFd(fd, std.mem.asBytes(&ehdr), 0) == null) exitNow(127);
    if (ehdr.e_ident[0] != 0x7f or ehdr.e_ident[1] != 'E' or
        ehdr.e_ident[2] != 'L' or ehdr.e_ident[3] != 'F') exitNow(127);
    if (ehdr.e_phnum == 0) exitNow(127);

    var load_base: u64 = 0;
    var found_base = false;

    var i: u16 = 0;
    while (i < ehdr.e_phnum) : (i += 1) {
        var ph: Elf64_Phdr = undefined;
        const off = ehdr.e_phoff + @as(u64, i) * @sizeOf(Elf64_Phdr);
        if (preadFd(fd, std.mem.asBytes(&ph), off) == null) exitNow(127);
        if (ph.p_type != PT_LOAD) continue;

        var prot: u32 = 0;
        if (ph.p_flags & 0x1 != 0) prot |= PROT_READ;
        if (ph.p_flags & 0x2 != 0) prot |= PROT_WRITE;
        if (ph.p_flags & 0x4 != 0) prot |= PROT_EXEC;

        const page: u64 = 0x1000;
        const offset_page = ph.p_offset & ~(page - 1);
        const map_addr: usize = @intCast(ph.p_vaddr - (ph.p_offset - offset_page));
        const map_len: usize = @intCast((ph.p_offset - offset_page) + ph.p_memsz);

        if (!found_base) {
            load_base = ph.p_vaddr - ph.p_offset;
            found_base = true;
        }

        if (ph.p_filesz > 0) {
            if (!mmapFile(fd, map_addr, map_len, prot, offset_page)) exitNow(127);
        } else {
            if (!mmapAnon(map_addr, map_len, prot)) exitNow(127);
        }
    }

    if (!found_base) exitNow(127);

    const auxv = stackAuxv(sp);
    var k: usize = 0;
    while (true) : (k += 2) {
        const key = auxv[k];
        if (key == AT_NULL) break;
        if (key == AT_BASE) {
            auxv[k + 1] = load_base;
            break;
        }
    }

    const entry: usize = @intCast(ehdr.e_entry);
    const entry_fn: *const fn () callconv(.c) noreturn = @ptrFromInt(entry);
    entry_fn();
}

const builtin = @import("builtin");
const arch = builtin.cpu.arch;

pub export fn _start() callconv(.naked) noreturn {
    if (arch == .aarch64) {
        asm volatile(
            \\ mov x0, sp
            \\ b loaderMain
        );
    } else if (arch == .x86_64) {
        asm volatile(
            \\ mov %rsp, %rdi
            \\ jmp loaderMain
        );
    } else if (arch == .arm) {
        asm volatile(
            \\ mov r0, sp
            \\ b loaderMain
        );
    } else if (arch == .x86) {
        asm volatile(
            \\ mov %esp, %eax
            \\ push %eax
            \\ call loaderMain
        );
    } else @compileError("unsupported arch for loader entry");
}
