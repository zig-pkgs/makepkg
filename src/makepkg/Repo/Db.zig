pkg_map: Desc.Map,
group_map: std.StringHashMap(std.ArrayList([:0]const u8)),
arena: *std.heap.ArenaAllocator,

pub fn parse(gpa: mem.Allocator, reader: *std.Io.Reader) !Db {
    const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
    errdefer gpa.destroy(arena_ptr);
    arena_ptr.* = .init(gpa);

    const arena = arena_ptr.allocator();

    var pkg_map: Desc.Map = .init(gpa);
    errdefer pkg_map.deinit();

    var group_map: std.StringHashMap(std.ArrayList([:0]const u8)) = .init(gpa);
    errdefer group_map.deinit();

    var flate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(reader, .gzip, &flate_buffer);

    var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var it: tar.Iterator = .init(&decompress.reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
        .diagnostics = null,
    });

    while (try it.next()) |file| {
        switch (file.kind) {
            .file => {
                var allocating: std.Io.Writer.Allocating = .init(gpa);
                defer allocating.deinit();
                try it.streamRemaining(file, &allocating.writer);
                var line_reader: std.Io.Reader = .fixed(allocating.written());
                const desc = try Desc.Parser.parse(arena, &line_reader);
                try allocating.writer.flush();
                if (desc.groups) |groups| {
                    for (groups) |group| {
                        if (group_map.getPtr(group)) |list| {
                            try list.append(arena, desc.name);
                        } else {
                            var list: std.ArrayList([:0]const u8) = try .initCapacity(arena, 1);
                            list.appendAssumeCapacity(desc.name);
                            try group_map.put(group, list);
                        }
                    }
                }
                try pkg_map.put(desc.name, desc);
            },
            else => {},
        }
    }

    return .{
        .arena = arena_ptr,
        .pkg_map = pkg_map,
        .group_map = group_map,
    };
}

pub fn deinit(self: *Db) void {
    const allocator = self.arena.child_allocator;
    self.pkg_map.deinit();
    self.group_map.deinit();
    self.arena.deinit();
    allocator.destroy(self.arena);
}

const std = @import("std");
const tar = std.tar;
const mem = std.mem;
const testing = std.testing;
const common = @import("../common.zig");
const Desc = @import("Desc.zig");
const Db = @This();

test "db parsing" {
    const db_file = @embedFile("Db/core.db.tar.gz");
    const expected = @embedFile("Desc/desc.zon");

    var db_file_reader: std.Io.Reader = .fixed(db_file);

    var db = try parse(testing.allocator, &db_file_reader);
    defer db.deinit();

    const shadow = db.pkg_map.get("shadow");
    try testing.expect(shadow != null);

    var allocating: std.Io.Writer.Allocating = .init(testing.allocator);
    defer allocating.deinit();
    try std.zon.stringify.serialize(shadow.?, .{}, &allocating.writer);
    try allocating.writer.writeByte('\n');
    try allocating.writer.flush();

    try testing.expectEqualStrings(expected, allocating.written());
}

test "db group" {
    const db_file = @embedFile("Db/extra.db.tar.gz");

    var db_file_reader: std.Io.Reader = .fixed(db_file);

    var db = try parse(testing.allocator, &db_file_reader);
    defer db.deinit();

    const gnome = db.group_map.get("gnome").?;
    for (gnome.items) |pkg| {
        try testing.expect(pkg.len > 0);
    }
}
