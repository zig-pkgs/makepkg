// Mandatory Keywords (must be present exactly once)
pkgname: [:0]const u8,
pkgbase: [:0]const u8,
pkgver: [:0]const u8,
pkgdesc: [:0]const u8,
url: [:0]const u8,
builddate: i64,
packager: [:0]const u8,
size: usize,
arch: []const common.Arch,

// It is mandatory to have at least one xdata entry that defines the pkgtype.
xdata: []const ExtraData,

// The following keywords are optional and can be included zero or more times:
license: ?[]const Licence = null,
replaces: ?[]const [:0]const u8 = null,
group: ?[]const [:0]const u8 = null,
conflict: ?[]const [:0]const u8 = null,
provides: ?[]const [:0]const u8 = null,
backup: ?[]const [:0]const u8 = null,
depend: ?[]const [:0]const u8 = null,
optdepend: ?[]const [:0]const u8 = null,
makedepend: ?[]const [:0]const u8 = null,
checkdepend: ?[]const [:0]const u8 = null,

pub const ExtraData = union(enum) {
    pkgtype: PkgType,
};

pub const Licence = @import("license.zig").License;

pub const PkgType = enum {
    debug,
    pkg,
    src,
    split,
};

pub fn fmt(value: PkgInfo) Formatter(PkgInfo, .info) {
    return .{ .value = value };
}

test {
    const expected = @embedFile("PkgInfo/PKGINFO");

    var allocating: std.Io.Writer.Allocating = .init(testing.allocator);
    defer allocating.deinit();
    const pkg_info: PkgInfo = @import("PkgInfo/PKGINFO.zon");

    const writer = &allocating.writer;
    try writer.print("{f}", .{fmt(pkg_info)});
    try writer.flush();
    try testing.expectEqualStrings(expected, writer.buffered());
}

const std = @import("std");
const testing = std.testing;
const common = @import("common.zig");
const PkgInfo = @This();
const Formatter = @import("formatter.zig").Formatter;
