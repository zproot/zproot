const std = @import("std");
const builtin = @import("builtin");

pub const is_android: bool = builtin.abi == .android;

pub fn isNativeLibPath(path: []const u8) bool {
    if (!is_android) return false;
    return std.mem.indexOf(u8, path, "/lib/arm64/") != null or
        std.mem.indexOf(u8, path, "/lib/arm/") != null or
        std.mem.indexOf(u8, path, "/lib/x86_64/") != null or
        std.mem.indexOf(u8, path, "/lib/x86/") != null;
}

pub fn isAppPrivatePath(path: []const u8) bool {
    if (!is_android) return false;
    return std.mem.startsWith(u8, path, "/data/data/") or
        std.mem.startsWith(u8, path, "/data/user/");
}

pub fn isPassthroughRoot(path: []const u8) bool {
    const roots = [_][]const u8{
        "/proc", "/sys",    "/dev",          "/system",
        "/apex", "/vendor", "/linkerconfig",
    };
    for (roots) |r| {
        if (std.mem.startsWith(u8, path, r)) {
            if (path.len == r.len or path[r.len] == '/') return true;
        }
    }
    return false;
}
