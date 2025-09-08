pub const Map = std.StringHashMap(Desc);

filename: [:0]const u8 = &.{},
name: [:0]const u8 = &.{},
base: [:0]const u8 = &.{},
version: [:0]const u8 = &.{},
desc: [:0]const u8 = &.{},
csize: usize = 0,
isize: usize = 0,
md5sum: ?[:0]const u8 = null,
sha256sum: [:0]const u8 = &.{},
pgpsig: [:0]const u8 = &.{},
url: [:0]const u8 = &.{},
license: ?[]const [:0]const u8 = null,
arch: common.Arch = .any,
builddate: i64 = 0,
packager: [:0]const u8 = &.{},

groups: ?[]const [:0]const u8 = null,
checkdepends: ?[]const [:0]const u8 = null,
depends: ?[]const [:0]const u8 = null,
optdepends: ?[]const [:0]const u8 = null,
makedepends: ?[]const [:0]const u8 = null,
replaces: ?[]const [:0]const u8 = null,
conflicts: ?[]const [:0]const u8 = null,
provides: ?[]const [:0]const u8 = null,

const std = @import("std");
const tar = std.tar;
const mem = std.mem;
const testing = std.testing;
const common = @import("../common.zig");
const Formatter = @import("../formatter.zig").Formatter;
const Desc = @This();

pub fn fmt(value: Desc) Formatter(Desc, .desc) {
    return .{ .value = value };
}

pub const Parser = @import("../parser.zig").DescParser(Desc);

test {
    const desc_buf = @embedFile("Desc/desc.txt");
    const expected = @embedFile("Desc/desc.zon");

    var reader: std.Io.Reader = .fixed(desc_buf);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const desc = try Parser.parse(arena.allocator(), &reader);
    {
        var allocating: std.Io.Writer.Allocating = .init(testing.allocator);
        defer allocating.deinit();
        try std.zon.stringify.serialize(desc, .{}, &allocating.writer);
        try allocating.writer.writeByte('\n');
        try allocating.writer.flush();

        try testing.expectEqualStrings(expected, allocating.written());
    }
    {
        var allocating: std.Io.Writer.Allocating = .init(testing.allocator);
        defer allocating.deinit();
        try allocating.writer.print("{f}\n", .{fmt(desc)});
        try allocating.writer.flush();
        var reader_new: std.Io.Reader = .fixed(allocating.written());
        const desc_new = try Parser.parse(arena.allocator(), &reader_new);

        try testing.expectEqualDeep(desc, desc_new);
    }
}
