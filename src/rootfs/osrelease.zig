const std = @import("std");
const linux = std.os.linux;

const AT_FDCWD: usize = @bitCast(@as(isize, -100));

pub const Info = struct {
    buf: [512]u8 = undefined,
    name: []const u8 = "unknown",
    id: []const u8 = "unknown",
    version: []const u8 = "unknown",
};

fn openRead(path: [*:0]const u8) ?i32 {
    const fd = linux.syscall3(.openat, AT_FDCWD, @intFromPtr(path), @as(usize, 0));
    const s: isize = @bitCast(fd);
    if (s < 0) return null;
    return @intCast(s);
}

fn closeFd(fd: i32) void {
    _ = linux.syscall1(.close, @intCast(fd));
}

fn readAll(fd: i32, buf: []u8) usize {
    var total: usize = 0;
    while (total < buf.len) {
        const ret = linux.syscall3(
            .read,
            @intCast(fd),
            @intFromPtr(buf.ptr) + total,
            buf.len - total,
        );
        const s: isize = @bitCast(ret);
        if (s <= 0) break;
        total += @intCast(s);
    }
    return total;
}

fn field(data: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            var v = line[key.len..];
            if (v.len >= 2 and v[0] == '"' and v[v.len - 1] == '"') {
                v = v[1 .. v.len - 1];
            }
            return v;
        }
    }
    return null;
}

pub fn read(info: *Info) bool {
    const fd = openRead("/etc/os-release") orelse return false;
    defer closeFd(fd);

    const n = readAll(fd, &info.buf);
    if (n == 0) return false;
    const data = info.buf[0..n];

    if (field(data, "NAME=")) |v| info.name = v;
    if (field(data, "ID=")) |v| info.id = v;
    if (field(data, "VERSION_ID=")) |v| info.version = v;
    return true;
}
