const std = @import("std");

pub const Options = struct {
    rootfs: ?[]const u8 = null,
    loader: ?[]const u8 = null,
    patched: ?[]const u8 = null,
    program: []const u8,
    program_args: []const []const u8,
};

pub const Error = error{
    MissingValue,
    MissingProgram,
    UnknownFlag,
};

pub fn parse(args: []const []const u8) Error!Options {
    var i: usize = 1;
    var opts: Options = undefined;

    while (i < args.len) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--rootfs")) {
            if (i + 1 >= args.len) return error.MissingValue;
            opts.rootfs = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, a, "--loader")) {
            if (i + 1 >= args.len) return error.MissingValue;
            opts.loader = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, a, "--patched")) {
            if (i + 1 >= args.len) return error.MissingValue;
            opts.patched = args[i + 1];
            i += 2;
        } else if (a.len > 0 and a[0] == '-') {
            return error.UnknownFlag;
        } else {
            break;
        }
    }

    if (i >= args.len) return error.MissingProgram;
    opts.program = args[i];
    opts.program_args = args[i..];
    return opts;
}
