const std = @import("std");
const linux = std.os.linux;

const PT_LOAD: u32 = 1;
const PT_INTERP: u32 = 3;

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
    offset: u64,
    size: u64,
    text: [512]u8,
    text_len: usize,
};

fn openAt(path: [*:0]const u8) !i32 {
    const fd = linux.syscall3(.openat, @as(usize, -100), @intFromPtr(path), 0);
    const signed: isize = @bitCast(fd);
    if (signed < 0) return error.OpenFailed;
    return @intCast(signed);
}

fn close(fd: i32) void {
    _ = linux.syscall1(.close, @intCast(fd));
}

fn pread(fd: i32, buf: []u8, offset: u64) !usize {
    const ret = linux.syscall6(
        .pread64,
        @intCast(fd),
        @intFromPtr(buf.ptr),
        buf.len,
        offset,
        0,
        0,
    );
    const signed: isize = @bitCast(ret);
    if (signed < 0) return error.ReadFailed;
    return @intCast(signed);
}

/// Read the ELF at `path` and locate PT_INTERP.
/// Returns the file offset, the size, and the interpreter path string.
pub fn locate(path: [*:0]const u8) !InterpInfo {
    const fd = try openAt(path);
    defer close(fd);

    var ehdr: Elf64_Ehdr = undefined;
    const ehdr_bytes = std.mem.asBytes(&ehdr);
    if (try pread(fd, ehdr_bytes, 0) != @sizeOf(Elf64_Ehdr)) return error.BadElf;

    if (ehdr.e_ident[0] != 0x7f or ehdr.e_ident[1] != 'E' or
        ehdr.e_ident[2] != 'L' or ehdr.e_ident[3] != 'F')
    {
        return error.NotElf;
    }

    if (ehdr.e_phnum == 0) return error.NoPhdr;

    var i: u16 = 0;
    while (i < ehdr.e_phnum) : (i += 1) {
        var phdr: Elf64_Phdr = undefined;
        const off = ehdr.e_phoff + @as(u64, i) * @sizeOf(Elf64_Phdr);
        const phdr_bytes = std.mem.asBytes(&phdr);
        if (try pread(fd, phdr_bytes, off) != @sizeOf(Elf64_Phdr)) return error.BadPhdr;

        if (phdr.p_type == PT_INTERP) {
            if (phdr.p_filesz > 512) return error.InterpTooLong;

            var info: InterpInfo = .{
                .offset = phdr.p_offset,
                .size = phdr.p_filesz,
                .text = undefined,
                .text_len = 0,
            };

            const buf = info.text[0..@intCast(phdr.p_filesz)];
            if (try pread(fd, buf, phdr.p_offset) != phdr.p_filesz) return error.BadInterp;

            var len: usize = 0;
            while (len < buf.len and buf[len] != 0) : (len += 1) {}
            info.text_len = len;
            return info;
        }
    }

    return error.NoInterp;
}

/// Copy the ELF at `src` to `dst`, replacing the PT_INTERP string with `new_interp`.
/// `new_interp` must be at most `info.size` bytes, including the null terminator.
/// For a longer loader path, the program header offset must be relocated instead.
pub fn patch(
    src: [*:0]const u8,
    dst: [*:0]const u8,
    info: InterpInfo,
    new_interp: []const u8,
) !void {
    if (new_interp.len + 1 > info.size) return error.NewInterpTooLong;

    const src_fd = try openAt(src);
    defer close(src_fd);

    const dst_fd = linux.syscall4(
        .openat,
        @as(usize, -100),
        @intFromPtr(dst),
        @as(usize, 0x241),
        @as(usize, 0o755),
    );
    const signed: isize = @bitCast(dst_fd);
    if (signed < 0) return error.CreateFailed;
    const out_fd: i32 = @intCast(signed);
    defer close(out_fd);

    var buf: [65536]u8 = undefined;
    var offset: u64 = 0;
    while (true) {
        const n = try pread(src_fd, &buf, offset);
        if (n == 0) break;
        const w = linux.syscall3(
            .write,
            @intCast(out_fd),
            @intFromPtr(&buf),
            n,
        );
        const ws: isize = @bitCast(w);
        if (ws < 0) return error.WriteFailed;
        offset += n;
    }

    var interp_buf: [512]u8 = [_]u8{0} ** 512;
    @memcpy(interp_buf[0..new_interp.len], new_interp);

    const pwrite_ret = linux.syscall6(
        .pwrite64,
        @intCast(out_fd),
        @intFromPtr(&interp_buf),
        info.size,
        info.offset,
        0,
        0,
    );
    const ps: isize = @bitCast(pwrite_ret);
    if (ps < 0) return error.WriteFailed;
}
