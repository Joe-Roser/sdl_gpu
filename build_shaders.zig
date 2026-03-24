const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});
var gpa = GPA{};

const shader_path = @import("assets/assets.zig").shaders.path;

pub fn main() !void {
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const dir = try std.fs.cwd().openDir(shader_path ++ "src/", .{ .iterate = true });
    var it = dir.iterate();

    while (try it.next()) |file| {
        if (file.kind != .file) continue;

        const src = try std.fmt.allocPrint(alloc, shader_path ++ "src/{s}", .{file.name});
        const spv = try std.fmt.allocPrint(alloc, shader_path ++ "out/{s}.spv", .{file.name});
        defer alloc.free(src);
        defer alloc.free(spv);

        var glslc_cmd = std.process.Child.init(&[_][]const u8{ "glslc", src, "-O", "-Werror", "-o", spv }, std.heap.page_allocator);
        try glslc_cmd.spawn();
        _ = try glslc_cmd.wait();
    }
}
