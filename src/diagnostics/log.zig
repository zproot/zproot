const std = @import("std");

var verbose_enabled: bool = false;

pub fn setVerbose(on: bool) void {
    verbose_enabled = on;
}

pub fn isVerbose() bool {
    return verbose_enabled;
}

pub fn trace(comptime fmt: []const u8, args: anytype) void {
    if (!verbose_enabled) return;
    std.log.debug(fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    std.log.warn(fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.log.err(fmt, args);
}
