const std = @import("std");
const linux = std.os.linux;

const PT_LOAD: u32 = 1;
const PT_INTERP: u32 = 3;

const O_RDONLY: usize = 0;
const O_WRONLY: usize = 1;
const O_CREAT: usize = 0x40;
const O_TRUNC: usize = 0x200;
const O_CLOEXEC: usize = 0x80000;

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

pub const InterpInfo = struct {
    phdr_offset: u64,
    interp_offset: u64,
    interp_size: u64,
    last_load_end: u64,
};

pub const PatchResult = struct {
    used_new_location: bool,
    new_offset: u64,
};

fn openRead(path: [*:0]const u8) !i32 {
    const fd = linux.syscall3(.openat, AT_FDCWD, @intFromPtr(path), O_RDONLY | O_CLOEXEC);
    const s: isize = @bitCast(fd);
    if (s < 0) return error.OpenFailed;
    return @intCast(s);
}

fn openWrite(path: [*:0]const u8) !i32 {
    const fd = linux.syscall4(
        .openat,
        AT_FDCWD,
        @intFromPtr(path),
        O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC,
        @as(usize, 0o755),
    );
    const s: isize = @bitCast(fd);
    if (s < 0) return error.CreateFailed;
    return @intCast(s);
}

fn closeFd(fd: i32) void {
    _ = linux.syscall1(.close, @intCast(fd));
}

fn preadFd(fd: i32, buf: []u8, off: u64) !usize {
    const ret = linux.syscall6(.pread64, @intCast(fd), @intFromPtr(buf.ptr), buf.len, off, 0, 0);
    const s: isize = @bitCast(ret);
    if (s < 0) return error.ReadFailed;
    return @intCast(s);
}

fn pwriteFd(fd: i32, buf: []const u8, off: u64) !usize {
    const ret = linux.syscall6(.pwrite64, @intCast(fd), @intFromPtr(buf.ptr), buf.len, off, 0, 0);
    const s: isize = @bitCast(ret);
    if (s < 0) return error.WriteFailed;
    return @intCast(s);
}

fn ftruncate(fd: i32, size: u64) !void {
    const ret = linux.syscall2(.ftruncate, @intCast(fd), size);
    const s: isize = @bitCast(ret);
    if (s < 0) return error.TruncateFailed;
}

pub fn locate(path: [*:0]const u8) !InterpInfo {
    const fd = try openRead(path);
    defer closeFd(fd);

    var ehdr: Elf64_Ehdr = undefined;
    if (try preadFd(fd, std.mem.asBytes(&ehdr), 0) != @sizeOf(Elf64_Ehdr))
        return error.BadElf;
    if (ehdr.e_ident[0] != 0x7f or ehdr.e_ident[1] != 'E' or
        ehdr.e_ident[2] != 'L' or ehdr.e_ident[3] != 'F')
        return error.NotElf;
    if (ehdr.e_phnum == 0) return error.NoPhdr;

    var ph_i: u16 = 0;
    var interp_found = false;
    var interp_phdr_off: u64 = 0;
    var interp_off: u64 = 0;
    var interp_size: u64 = 0;
    var last_end: u64 = 0;

    while (ph_i < ehdr.e_phnum) : (ph_i += 1) {
        var ph: Elf64_Phdr = undefined;
        const off = ehdr.e_phoff + @as(u64, ph_i) * @sizeOf(Elf64_Phdr);
        if (try preadFd(fd, std.mem.asBytes(&ph), off) != @sizeOf(Elf64_Phdr))
            return error.BadPhdr;

        if (ph.p_type == PT_INTERP) {
            interp_phdr_off = off;
            interp_off = ph.p_offset;
            interp_size = ph.p_filesz;
            interp_found = true;
        }
        if (ph.p_type == PT_LOAD) {
            const end = ph.p_offset + ph.p_filesz;
            if (end > last_end) last_end = end;
        }
    }

    if (!interp_found) return error.NoInterp;

    return .{
        .phdr_offset = interp_phdr_off,
        .interp_offset = interp_off,
        .interp_size = interp_size,
        .last_load_end = last_end,
    };
}

pub fn patch(
    src: [*:0]const u8,
    dst: [*:0]const u8,
    info: InterpInfo,
    new_interp: []const u8,
) !PatchResult {
    const src_fd = try openRead(src);
    defer closeFd(src_fd);
    const dst_fd = try openWrite(dst);
    defer closeFd(dst_fd);

    var buf: [65536]u8 = undefined;
    var off: u64 = 0;
    while (true) {
        const n = try preadFd(src_fd, &buf, off);
        if (n == 0) break;
        if (try pwriteFd(dst_fd, buf[0..n], off) != n) return error.WriteFailed;
        off += n;
    }
    const file_size = off;

    if (new_interp.len + 1 <= info.interp_size) {
        var slot: [512]u8 = [_]u8{0} ** 512;
        @memcpy(slot[0..new_interp.len], new_interp);
        if (try pwriteFd(dst_fd, slot[0..@intCast(info.interp_size)], info.interp_offset) != info.interp_size)
            return error.WriteFailed;
        return .{ .used_new_location = false, .new_offset = info.interp_offset };
    }

    const append_off = (info.last_load_end + 0xfff) & ~@as(u64, 0xfff);
    var slot: [512]u8 = [_]u8{0} ** 512;
    @memcpy(slot[0..new_interp.len], new_interp);
    const new_size = new_interp.len + 1;
    if (try pwriteFd(dst_fd, slot[0..new_size], append_off) != new_size)
        return error.WriteFailed;

    var ph: Elf64_Phdr = undefined;
    if (try preadFd(dst_fd, std.mem.asBytes(&ph), info.phdr_offset) != @sizeOf(Elf64_Phdr))
        return error.BadPhdr;
    ph.p_offset = append_off;
    ph.p_filesz = new_size;
    ph.p_memsz = new_size;
    if (try pwriteFd(dst_fd, std.mem.asBytes(&ph), info.phdr_offset) != @sizeOf(Elf64_Phdr))
        return error.WriteFailed;

    const needed = append_off + new_size;
    if (needed > file_size) try ftruncate(dst_fd, needed);

    return .{ .used_new_location = true, .new_offset = append_off };
}
