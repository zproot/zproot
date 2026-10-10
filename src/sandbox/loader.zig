const std = @import("std");
const linux = std.os.linux;

const AT_FDCWD: usize = @bitCast(@as(isize, -100));
const X_OK: usize = 1;
const F_OK: usize = 0;

pub fn exists(path: [*:0]const u8) bool {
    const ret = linux.syscall4(.faccessat, AT_FDCWD, @intFromPtr(path), F_OK, 0);
    const s: isize = @bitCast(ret);
    return s == 0;
}

pub fn isExecutable(path: [*:0]const u8) bool {
    const ret = linux.syscall4(.faccessat, AT_FDCWD, @intFromPtr(path), X_OK, 0);
    const s: isize = @bitCast(ret);
    return s == 0;
}

pub fn size(path: [*:0]const u8) ?u64 {
    var st: linux.Stat = undefined;
    const ret = linux.syscall4(
        .newfstatat,
        AT_FDCWD,
        @intFromPtr(path),
        @intFromPtr(&st),
        0,
    );
    const s: isize = @bitCast(ret);
    if (s < 0) return null;
    return @intCast(st.size);
}
