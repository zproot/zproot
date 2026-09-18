const std = @import("std");
const linux = std.os.linux;

const types = @import("common/types.zig");
const status = @import("common/status.zig");
const ptrace = @import("trace/ptrace.zig");
const regs = @import("regs/regs.zig");
const memory_read = @import("memory/read.zig");
const memory_write = @import("memory/write.zig");
const seccomp = @import("seccomp/sigsys.zig");
const path = @import("path/prefix.zig");
const syscalls = @import("syscall/numbers.zig");
const sig = @import("signal/numbers.zig");
const fork = @import("exec/fork.zig");
const execve = @import("exec/execve.zig");
const interp = @import("exec/interp.zig");

fn rewriteEnvp(
    pid: types.pid_t,
    orig_envp: u64,
    scratch_top: u64,
    extra_var: []const u8,
) !u64 {
    var count: usize = 0;
    while (count < 256) : (count += 1) {
        const ptr_addr = orig_envp + count * 8;
        const w = memory_read.word(pid, ptr_addr) catch break;
        if (w == 0) break;
    }

    var extra_buf: [1024]u8 = undefined;
    if (extra_var.len + 1 > extra_buf.len) return error.EnvVarTooLong;
    @memcpy(extra_buf[0..extra_var.len], extra_var);
    extra_buf[extra_var.len] = 0;
    const extra_slice = extra_buf[0 .. extra_var.len + 1];

    try memory_write.cstring(pid, scratch_top, extra_slice[0..extra_var.len]);

    const extra_region: u64 = (extra_slice.len + 7) & ~@as(u64, 7);
    var ptr_array_addr = scratch_top + extra_region;
    ptr_array_addr = (ptr_array_addr + 7) & ~@as(u64, 7);

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const w = memory_read.word(pid, orig_envp + i * 8) catch 0;
        try memory_write.word(pid, ptr_array_addr + i * 8, w);
    }
    try memory_write.word(pid, ptr_array_addr + count * 8, scratch_top);
    try memory_write.word(pid, ptr_array_addr + (count + 1) * 8, 0);

    return ptr_array_addr;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.log.err("usage: zproot [--rootfs <path>] [--loader <path>] <program> [args...]", .{});
        return;
    }

    var start_idx: usize = 1;
    var loader_path: ?[]const u8 = null;

    while (start_idx < args.len) {
        if (std.mem.eql(u8, args[start_idx], "--rootfs")) {
            if (start_idx + 1 >= args.len) {
                std.log.err("--rootfs requires a path", .{});
                return;
            }
            if (!path.setRootfs(args[start_idx + 1])) {
                std.log.err("rootfs path too long", .{});
                return;
            }
            start_idx += 2;
        } else if (std.mem.eql(u8, args[start_idx], "--loader")) {
            if (start_idx + 1 >= args.len) {
                std.log.err("--loader requires a path", .{});
                return;
            }
            loader_path = args[start_idx + 1];
            start_idx += 2;
        } else {
            break;
        }
    }

    if (start_idx >= args.len) {
        std.log.err("no program specified", .{});
        return;
    }

    var argv_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer argv_arena.deinit();
    const aa = argv_arena.allocator();

    var child_args: std.ArrayList(?[*:0]const u8) = .empty;
    defer child_args.deinit(init.gpa);

    for (args[start_idx..]) |arg| {
        const z = try aa.dupeZ(u8, arg);
        try child_args.append(init.gpa, z.ptr);
    }
    try child_args.append(init.gpa, null);

    const child_argv: [*:null]const ?[*:0]const u8 =
        @ptrCast(child_args.items.ptr);

    const pid = fork.doFork() catch |e| {
        std.log.err("fork failed: {}", .{e});
        return;
    };

    if (pid == 0) {
        _ = ptrace.call(ptrace.PTRACE_TRACEME, 0, 0, 0);
        execve.execvpZ(child_args.items[0].?, child_argv);
    }

    var st: u32 = 0;
    _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&st), 0, 0);

    var entering = true;
    var path_buf: [4096]u8 = undefined;
    var new_path_buf: [4096]u8 = undefined;
    var patched_buf: [4096]u8 = undefined;
    var interp_buf: [512]u8 = undefined;
    var real_interp_buf: [1024]u8 = undefined;
    var env_buf: [1024]u8 = undefined;

    while (true) {
        _ = ptrace.call(ptrace.PTRACE_SYSCALL, pid, 0, 0);
        _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&st), 0, 0);

        if (status.WIFEXITED(st)) break;
        if (!status.WIFSTOPPED(st)) {
            entering = !entering;
            continue;
        }

        const s = status.WSTOPSIG(st);

        if (s == sig.SIGSYS) {
            seccomp.handle(pid) catch |e| {
                std.log.warn("SIGSYS failed: {}", .{e});
            };
            continue;
        }

        if (s != sig.SIGTRAP) {
            _ = ptrace.call(
                ptrace.PTRACE_SYSCALL,
                pid,
                0,
                @intCast(@as(u32, @intCast(s))),
            );
            _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&st), 0, 0);
            if (status.WIFEXITED(st)) break;
            if (!status.WIFSTOPPED(st)) {
                entering = !entering;
                continue;
            }
        }

        if (entering) {
            const r = regs.get(pid) catch {
                entering = !entering;
                continue;
            };
            const nr = r.nr();
            if (syscalls.isPath(nr)) {
                const idx = syscalls.pathArgIndex(nr);
                const path_addr = r.arg(idx);
                const p = memory_read.cstring(pid, path_addr, &path_buf) catch "<read failed>";

                if (path.rootfs_len > 0 and path.shouldPrefix(p)) {
                    if (path.build(&new_path_buf, p)) |new_path| {
                        var target_path: []const u8 = new_path;

                        if (nr == syscalls.SYS_EXECVE) {
                            const new_path_z: [*:0]const u8 = @ptrCast(new_path.ptr);
                            if (interp.locate(new_path_z)) |info| {
                               if (loader_path) |loader| {
                                   const suffix = ".zproot";
                                   if (new_path.len + suffix.len + 1 <= patched_buf.len) {
                                       @memcpy(patched_buf[0..new_path.len], new_path);
                                       @memcpy(patched_buf[new_path.len .. new_path.len + suffix.len], suffix);
                                       patched_buf[new_path.len + suffix.len] = 0;
                                       const patched_z: [*:0]const u8 = @ptrCast(&patched_buf);

                                       _ = interp.patch(new_path_z, patched_z, info, loader) catch |e| {
                                           std.log.warn("execve: patch failed: {}", .{e});
                                           entering = !entering;
                                           continue;
                                       };

                                       target_path = patched_buf[0 .. new_path.len + suffix.len];

                                       if (interp.readInterp(new_path_z, info, &interp_buf)) |interp_name| {
                                           if (std.fmt.bufPrint(&real_interp_buf, "{s}{s}", .{ path.rootfs(), interp_name })) |ri| {
                                               if (std.fmt.bufPrint(&env_buf, "ZPROOT_REAL_INTERP={s}", .{ri})) |es| {
                                                   const env_scratch = r.sp() - 65536;
                                                   const orig_envp = r.arg(2);
                                                   if (rewriteEnvp(pid, orig_envp, env_scratch, es)) |new_envp| {
                                                       regs.setArg(pid, 2, new_envp) catch {
                                                          std.log.warn("execve: setarg envp failed", .{});
                                                       };
                                                       std.log.info("execve: patched {s} interp={s}", .{ p, ri });
                                                   } else |e| {
                                                       std.log.warn("execve: envp rewrite failed: {}", .{e});
                                                   }
                                               } else |_| {
                                                   std.log.warn("execve: env too long", .{});
                                               }
                                           } else |_| {
                                               std.log.warn("execve: real interp path too long", .{});
                                           }
                                       } else |_| {
                                           std.log.warn("execve: could not read PT_INTERP string", .{});
                                       }
                                   } else {
                                       std.log.warn("execve: patched path too long", .{});
                                   }
                               } else {
                                   std.log.info("execve: dynamic binary, no --loader", .{});
                               }
                           } else |_| {
                               std.log.info("execve: static binary", .{});
                           }
                        }

                        const scratch = r.sp() - 8192;
                        memory_write.cstring(pid, scratch, target_path) catch {
                            std.log.err("write failed for {s}", .{p});
                            entering = !entering;
                            continue;
                        };
                        regs.setArg(pid, idx, scratch) catch {
                            std.log.err("setregs failed for {s}", .{p});
                            entering = !entering;
                            continue;
                        };
                    }
                }
            }
        }
        entering = !entering;
    }

    std.log.info("child exited with {d}", .{status.WEXITSTATUS(st)});
}
