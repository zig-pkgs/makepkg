format: u8 = @intFromEnum(Format.v2),
pkgname: [:0]const u8,
pkgbase: [:0]const u8,
pkgver: [:0]const u8,
pkgarch: []const common.Arch,
pkgbuild_sha256sum: []const u8,
packager: [:0]const u8,
builddate: i64,
builddir: []const u8,
startdir: []const u8,
buildtool: [:0]const u8,
buildtoolver: [:0]const u8,

buildenv: ?[]const [:0]const u8 = null,
options: ?[]const common.Options = null,
installed: ?[]const [:0]const u8 = null,

pub const Format = enum(u8) {
    v1 = 1,
    v2,
};

pub fn fmt(value: BuildInfo) Formatter(BuildInfo) {
    return .{ .value = value };
}

test {
    const expected = @embedFile("BuildInfo/BUILDINFO");

    var allocating: std.Io.Writer.Allocating = .init(testing.allocator);
    defer allocating.deinit();
    const build_info: BuildInfo = @import("BuildInfo/BUILDINFO.zon");

    const writer = &allocating.writer;
    try writer.print("{f}", .{fmt(build_info)});
    try writer.flush();
    try testing.expectEqualStrings(expected, writer.buffered());
}

const std = @import("std");
const testing = std.testing;
const common = @import("common.zig");
const Formatter = @import("formatter.zig").Formatter;
const PkgBuild = @import("PkgBuild.zig");
const BuildInfo = @This();
