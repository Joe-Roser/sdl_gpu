const std = @import("std");
const ShaderBuilder = @import("shader_tools").ShaderBuilder;

pub fn build(b: *std.Build) void {
    const io = b.graph.io;
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});

    // const with_shaders = b.option(bool, "sh", "Build with shaders") orelse false;
    // const build_shaders = b.addSystemCommand(&.{ "zig", "run", "build_shaders.zig" });

    const translate_c = b.addTranslateC(.{
        .link_libc = true,
        .optimize = opt,
        .target = target,
        .root_source_file = b.path("src/translate.c"),
    });
    translate_c.linkSystemLibrary("SDL3", .{});
    translate_c.linkSystemLibrary("SDL3_image", .{});

    const zul = b.dependency("zul", .{});
    const zalg = b.dependency("zalg", .{});

    const shader_builder: ShaderBuilder = .init(.{});
    const shader_flag = b.option(bool, "sh", "build shaders") orelse false;
    if (shader_flag) {
        shader_builder.build_dir(io, b.allocator, "assets/shaders/src/", "assets/shaders/out/") catch return;
    }

    const assets = b.createModule(.{
        .root_source_file = b.path("assets/assets.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = opt,
            .imports = &.{
                .{ .module = zul.module("zul"), .name = "zul" },
                .{ .module = zalg.module("zalgebra"), .name = "zalg" },
                .{ .module = assets, .name = "assets" },
                .{ .module = translate_c.createModule(), .name = "c" },
            },
        }),
    });
    // exe.addIncludePath(b.path("assets/"));
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);

    // Building shaders depends on compile flag
    // if (with_shaders) exe.step.dependOn(&build_shaders.step);

    const run_step = b.step("run", "run the app");
    const run_exe = b.addRunArtifact(exe);
    run_step.dependOn(&run_exe.step);

    const test_step = b.step("test", "test the app");
    const test_exe = b.addTest(.{ .root_module = exe.root_module });
    const test_run = b.addRunArtifact(test_exe);
    test_step.dependOn(&test_run.step);
}
