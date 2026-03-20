const std = @import("std");
const zalg = @import("zalg");

const Vec2 = zalg.Vec2;
const Vec3 = zalg.Vec3;

pub const Obj = struct {
    positions: []Vec3,
    uvs: []Vec2,
    faces: []ObjFaceIndex,

    alloc: std.mem.Allocator,

    pub fn from_file(alloc: std.mem.Allocator, filename: []const u8) !Obj {
        const obj_file = try std.fs.cwd().openFile(filename, .{});
        defer obj_file.close();

        var buf: [1024]u8 = undefined;
        var reader = obj_file.reader(&buf);
        const r = &reader.interface;

        return from_reader(alloc, r);
    }

    pub fn from_reader(alloc: std.mem.Allocator, r: *std.Io.Reader) !Obj {
        var positions = try std.ArrayList(Vec3).initCapacity(alloc, 128);
        var uvs = try std.ArrayList(Vec2).initCapacity(alloc, 128);
        var faces = try std.ArrayList(ObjFaceIndex).initCapacity(alloc, 128);
        errdefer {
            positions.deinit(alloc);
            uvs.deinit(alloc);
            faces.deinit(alloc);
        }

        while (true) {
            const line = r.takeDelimiterInclusive('\n') catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            const idx = std.mem.indexOf(u8, line, " ") orelse continue;
            const cmd = line[0..idx];

            switch (idx) {
                0 => continue,
                1 => switch (cmd[0]) {
                    'v' => {
                        const pos = try parse_pos(line);
                        try positions.append(alloc, pos);
                    },
                    'f' => {
                        const face = try parse_faces(line);
                        try faces.appendSlice(alloc, &face);
                    },
                    'g' => {},
                    '#' => continue,
                    else => {},
                },
                2 => switch (cmd[0]) {
                    'v' => switch (cmd[1]) {
                        'n' => {},
                        't' => {
                            const uv = try parse_uv(line);
                            try uvs.append(alloc, uv);
                        },
                        else => {},
                    },
                    else => {},
                },
                6 => {
                    if (std.mem.eql(u8, cmd, "usemtl")) {} else if (std.mem.eql(u8, cmd, "mtllib")) {}
                },
                else => {},
            }
        }
        positions.shrinkAndFree(alloc, positions.items.len);
        uvs.shrinkAndFree(alloc, uvs.items.len);
        faces.shrinkAndFree(alloc, faces.items.len);

        return .{
            .positions = positions.items,
            .uvs = uvs.items,
            .faces = faces.items,

            .alloc = alloc,
        };
    }

    pub fn deinit(self: Obj) void {
        self.alloc.free(self.positions);
        self.alloc.free(self.uvs);
        self.alloc.free(self.faces);
    }
};

pub const ObjFaceIndex = struct {
    pos: u32,
    uv: u32,

    fn parse(str: []const u8) !ObjFaceIndex {
        var it = std.mem.splitAny(u8, str, "/");

        var u = it.next() orelse return error.InvalidFormat;
        const v1 = try std.fmt.parseInt(u32, u, 10) - 1;

        u = it.next() orelse return error.InvalidFormat;
        const v2 = try std.fmt.parseInt(u32, u, 10) - 1;

        u = it.next() orelse return error.InvalidFormat;

        if (it.next()) |_| return error.InvalidFormat;

        return .{
            .pos = v1,
            .uv = v2,
        };
    }
};

fn parse_pos(line: []const u8) !Vec3 {
    const s1 = 2 + (std.mem.indexOf(u8, line[2..line.len], " ") orelse return error.InvalidFormat);
    const s2 = s1 + 1 + (std.mem.indexOf(u8, line[(s1 + 1)..line.len], " ") orelse return error.InvalidFormat);
    const s3 = s2 + 1 + (std.mem.indexOf(u8, line[(s2 + 1)..line.len], " ") orelse return error.InvalidFormat);

    const x = try std.fmt.parseFloat(f32, line[2..s1]);
    const y = try std.fmt.parseFloat(f32, line[(s1 + 1)..s2]);
    const z = try std.fmt.parseFloat(f32, line[(s2 + 1)..s3]);

    return .fromSlice(&.{ x, y, z });
}

fn parse_uv(line: []const u8) !Vec2 {
    const s1 = 3 + (std.mem.indexOf(u8, line[3..line.len], " ") orelse return error.InvalidFormat);

    const x = try std.fmt.parseFloat(f32, line[3..s1]);
    const y = try std.fmt.parseFloat(f32, line[(s1 + 1)..(line.len - 2)]);

    return .fromSlice(&.{ x, y });
}

fn parse_faces(line: []const u8) ![3]ObjFaceIndex {
    const s1 = 2 + (std.mem.indexOf(u8, line[2..line.len], " ") orelse return error.InvalidFormat);
    const s2 = s1 + 1 + (std.mem.indexOf(u8, line[(s1 + 1)..line.len], " ") orelse return error.InvalidFormat);

    const f1: ObjFaceIndex = try .parse(line[2..s1]);
    const f2: ObjFaceIndex = try .parse(line[(s1 + 1)..s2]);
    const f3: ObjFaceIndex = try .parse(line[(s2 + 1)..(line.len - 2)]);

    return .{ f1, f2, f3 };
}
