const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});
var gpa = GPA{};

pub fn main() !void {
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const dir = try std.fs.cwd().openDir("src/shaders/src/", .{ .iterate = true });
    var it = dir.iterate();

    while (try it.next()) |file| {
        if (file.kind != .file) continue;

        const source = try std.fmt.allocPrint(alloc, "src/shaders/src/{s}", .{file.name});
        const sink = try std.fmt.allocPrint(alloc, "src/shaders/out/{s}.spv", .{file.name});
        defer alloc.free(source);
        defer alloc.free(sink);

        var cmd = std.process.Child.init(&[_][]const u8{ "glslc", source, "-o", sink }, std.heap.page_allocator);
        try cmd.spawn();

        _ = try cmd.wait();
    }
}
