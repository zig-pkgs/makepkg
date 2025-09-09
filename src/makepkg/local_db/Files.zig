files: []const [:0]const u8,
backup: []const [:0]const u8,

const Formatter = @import("../formatter.zig").Formatter;
const Desc = @This();

pub fn fmt(value: Desc) Formatter(Desc, .desc) {
    return .{ .value = value };
}

pub const Parser = @import("../parser.zig").DescParser(Desc);

const std = @import("std");
const Files = @This();
