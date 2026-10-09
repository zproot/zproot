const std = @import("std");

var syscall_count: u64 = 0;
var path_hit_count: u64 = 0;
var execve_count: u64 = 0;
var patch_count: u64 = 0;
var envp_rewrite_count: u64 = 0;

pub fn onSyscall() void {
    syscall_count +%= 1;
}

pub fn onPathHit() void {
    path_hit_count +%= 1;
}

pub fn onExecve() void {
    execve_count +%= 1;
}

pub fn onPatch() void {
    patch_count +%= 1;
}

pub fn onEnvpRewrite() void {
    envp_rewrite_count +%= 1;
}

pub fn dump() void {
    std.log.info(
        "stats: syscalls={d} paths={d} execve={d} patched={d} envp={d}",
        .{ syscall_count, path_hit_count, execve_count, patch_count, envp_rewrite_count },
    );
}

pub fn reset() void {
    syscall_count = 0;
    path_hit_count = 0;
    execve_count = 0;
    patch_count = 0;
    envp_rewrite_count = 0;
}
