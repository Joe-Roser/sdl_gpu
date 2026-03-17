const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});

    const with_shaders = b.option(bool, "sh", "Build with shaders") orelse false;

    const zul = b.dependency("zul", .{});

    const zalg = b.dependency("zalg", .{});

    const build_shaders = b.addSystemCommand(&.{ "zig", "run", "build_shaders.zig" });

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = opt,
            .link_libc = true,
            .imports = &.{
                .{ .module = zul.module("zul"), .name = "zul" },
                .{ .module = zalg.module("zalgebra"), .name = "zalg" },
            },
        }),
    });
    exe.root_module.linkSystemLibrary("SDL3", .{});
    b.default_step.dependOn(&exe.step);

    // Building shaders depends on compile flag
    if (with_shaders) exe.step.dependOn(&build_shaders.step);

    const run_step = b.step("run", "run the app");
    const run_exe = b.addRunArtifact(exe);
    run_step.dependOn(&run_exe.step);

    const test_step = b.step("test", "test the app");
    const test_exe = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&test_exe.step);

    const shader_step = b.step("shaders", "build all shaders");
    shader_step.dependOn(&build_shaders.step);
}
