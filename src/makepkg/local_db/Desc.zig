name: [:0]const u8,
version: [:0]const u8,
base: [:0]const u8,
desc: [:0]const u8,
url: [:0]const u8,
arch: common.Arch,
builddate: i64,
installdate: i64,
packager: [:0]const u8,
size: u64,
reason: u8 = @intFromEnum(common.InstallReason.explicit),

validation: common.Validation = .none,

license: ?[]const [:0]const u8 = null,
groups: ?[]const [:0]const u8 = null,
depends: ?[]const [:0]const u8 = null,
optdepends: ?[]const [:0]const u8 = null,
replaces: ?[]const [:0]const u8 = null,
conflicts: ?[]const [:0]const u8 = null,
provides: ?[]const [:0]const u8 = null,

xdata: []const common.ExtraData,

const Formatter = @import("../formatter.zig").Formatter;
const Desc = @This();

pub fn fmt(value: Desc) Formatter(Desc, .desc) {
    return .{ .value = value };
}

pub const Parser = @import("../parser.zig").DescParser(Desc);

const std = @import("std");
const common = @import("../common.zig");
