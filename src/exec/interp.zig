const std = @import("std");
const types = @import("../common/types.zig");
const regs_mod = @import("../regs/regs.zig");
const memory_read = @import("../memory/read.zig");
const memory_write = @import("../memory/write.zig");
const path = @import("../path/prefix.zig");
const elf = @import("../elf/elf.zig");

const STACK_SCRATCH: u64 = 16384;
const MAX_ARGV: usize = 512;

fn readU64(pid: types.pid_t, addr: u64) !u64 {
    var buf: [8]u8 = undefined;
    try memory_read.raw(pid, addr, &buf);
    return std.mem.readInt(u64, &buf, .little);
}

fn writeU64(pid: types.pid_t, addr: u64, val: u64) !void {
    const bytes = std.mem.asBytes(&val);
    try memory_write.raw(pid, addr, bytes);
}

pub fn handleExecve(
    pid: types.pid_t,
    r: regs_mod.Regs,
    path_addr: u64,
    guest_path: []const u8,
    interp_buf: []u8,
) !bool {
    if (path.rootfs_len == 0) return false;
    if (guest_path.len == 0 or guest_path[0] != '/') return false;
    if (!path.shouldPrefix(guest_path)) return false;

    var host_buf: [4096]u8 = undefined;
    if (path.rootfs_len + guest_path.len >= host_buf.len) return false;
    @memcpy(host_buf[0..path.rootfs_len], path.rootfs());
    @memcpy(host_buf[path.rootfs_len .. path.rootfs_len + guest_path.len], guest_path);
    const host_path = host_buf[0 .. path.rootfs_len + guest_path.len];

    const interp_rel = elf.readInterp(host_path, interp_buf) orelse return false;

    var interp_host_buf: [4096]u8 = undefined;
    if (path.rootfs_len + interp_rel.len >= interp_host_buf.len) return false;
    @memcpy(interp_host_buf[0..path.rootfs_len], path.rootfs());
    @memcpy(interp_host_buf[path.rootfs_len .. path.rootfs_len + interp_rel.len], interp_rel);
    const interp_host = interp_host_buf[0 .. path.rootfs_len + interp_rel.len];

    const argv_ptr = r.arg(1);
    var orig_argv: [MAX_ARGV]u64 = undefined;
    var n: usize = 0;
    while (n < MAX_ARGV) : (n += 1) {
        const val = readU64(pid, argv_ptr + n * 8) catch return false;
        if (val == 0) break;
        orig_argv[n] = val;
    }
    if (n == 0) return false;

    const sp = r.sp();
    if (sp < STACK_SCRATCH + 4096) return false;
    const scratch = sp - STACK_SCRATCH;

    memory_write.cstring(pid, scratch, interp_host) catch return false;
    const interp_addr = scratch;

    const argv_addr = scratch + interp_host.len + 1;
    var off: u64 = 0;

    try writeU64(pid, argv_addr + off, interp_addr);
    off += 8;

    try writeU64(pid, argv_addr + off, path_addr);
    off += 8;

    var i: usize = 1;
    while (i < n) : (i += 1) {
        try writeU64(pid, argv_addr + off, orig_argv[i]);
        off += 8;
    }

    try writeU64(pid, argv_addr + off, 0);

    regs_mod.setArg(pid, 0, interp_addr) catch return false;
    regs_mod.setArg(pid, 1, argv_addr) catch return false;

    std.log.info("execve {s} via {s}", .{ guest_path, interp_rel });
    return true;
}
