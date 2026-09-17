const std = @import("std");

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

const PT_INTERP: u32 = 3;
const ELF_MAGIC = [_]u8{ 0x7f, 'E', 'L', 'F' };

pub fn readInterp(host_path: []const u8, buf: []u8) ?[]const u8 {
    const file = std.fs.cwd().openFile(host_path, .{}) catch return null;
    defer file.close();

    var ehdr: Elf64_Ehdr = undefined;
    const ehdr_bytes = std.mem.asBytes(&ehdr);
    const n = file.read(ehdr_bytes) catch return null;
    if (n < @sizeOf(Elf64_Ehdr)) return null;
    if (!std.mem.eql(u8, ehdr.e_ident[0..4], &ELF_MAGIC)) return null;
    if (ehdr.e_ident[4] != 2) return null;

    var i: u16 = 0;
    while (i < ehdr.e_phnum) : (i += 1) {
        const off = ehdr.e_phoff + @as(u64, i) * ehdr.e_phentsize;
        file.seekTo(off) catch return null;

        var phdr: Elf64_Phdr = undefined;
        const ph_bytes = std.mem.asBytes(&phdr);
        const m = file.read(ph_bytes) catch return null;
        if (m < @sizeOf(Elf64_Phdr)) return null;

        if (phdr.p_type == PT_INTERP) {
            if (phdr.p_filesz > buf.len) return null;
            file.seekTo(phdr.p_offset) catch return null;
            const r = file.read(buf[0..@intCast(phdr.p_filesz)]) catch return null;
            if (r == 0) return null;
            var end = r;
            while (end > 0 and buf[end - 1] == 0) end -= 1;
            return buf[0..end];
        }
    }
    return null;
}
