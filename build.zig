const std = @import("std");

const android_targets = [_]std.Target.Query{
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .android },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .android },
    .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .android, .arm = .{ .mode = .thumb } },
    .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .android },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tracer = b.addExecutable(.{
        .name = "zproot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
            .pic = true,
        }),
    });
    tracer.pie = true;

    const loader = b.addExecutable(.{
        .name = "zproot-loader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/loader/main.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .link_libc = false,
            .pic = true,
        }),
    });
    loader.pie = true;

    b.installArtifact(tracer);
    b.installArtifact(loader);

    const all_step = b.step("all", "Build for all Android ABIs");

    for (android_targets) |query| {
        const rt = b.resolveTargetQuery(query);
        const t = b.addExecutable(.{
            .name = "zproot",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = rt,
                .optimize = optimize,
                .link_libc = false,
                .pic = true,
            }),
        });
        t.pie = true;

        const l = b.addExecutable(.{
            .name = "zproot-loader",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/loader/main.zig"),
                .target = rt,
                .optimize = .ReleaseSmall,
                .link_libc = false,
                .pic = true,
            }),
        });
        l.pie = true;

        const arch_name = @tagName(query.cpu_arch.?);
        const t_install = b.addInstallArtifact(t, .{
            .dest_sub_path = b.fmt("zproot-{s}", .{arch_name}),
        });
        const l_install = b.addInstallArtifact(l, .{
            .dest_sub_path = b.fmt("zproot-loader-{s}", .{arch_name}),
        });
        all_step.dependOn(&t_install.step);
        all_step.dependOn(&l_install.step);
    }
}
