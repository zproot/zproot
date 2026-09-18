const std = @import("std");

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
    loader.entry = .disabled;

    b.installArtifact(tracer);
    b.installArtifact(loader);
}
