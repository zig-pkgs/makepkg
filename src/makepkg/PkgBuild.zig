pkgname: [:0]const u8,
pkgbase: ?[:0]const u8 = null,
pkgver: [:0]const u8,
pkgrel: u64,
url: [:0]const u8,
arch: []const common.Arch,
epoch: u64 = 0,
pkgdesc: [:0]const u8,

build_style: common.BuildStyle,
configure_args: ?[]const [:0]const u8 = null,

sources: common.Sources,

license: ?[]const License = null,
groups: ?[]const [:0]const u8 = null,
backup: ?[]const [:0]const u8 = null,
depends: ?[]const common.Dependency = null,
makedepends: ?[]const common.Dependency = null,
checkdepends: ?[]const common.Dependency = null,
optdepends: ?[]const common.Dependency = null,
conflicts: ?[]const common.Dependency = null,
provides: ?[]const common.Dependency = null,
replaces: ?[]const common.Dependency = null,

options: ?[]const common.Options = null,

subpackages: ?[]const PkgBuild = null,

pub fn selectArch(self: PkgBuild, build_arch: common.Arch) error{UnsupportedArch}!common.Arch {
    // This package supports for all arch
    std.debug.assert(build_arch != .any);
    if (self.arch[0] == .any) return .any;
    for (self.arch) |arch| {
        if (arch == build_arch) return build_arch;
    }
    return error.UnsupportedArch;
}

pub const ParseResult = struct {
    hash: [Sha256.digest_length * 2]u8,
    pkgbuild: PkgBuild,
    version: [:0]const u8,

    pub fn deinit(self: *const ParseResult, gpa: mem.Allocator) void {
        gpa.free(self.version);
        zon.parse.free(gpa, self.pkgbuild);
    }

    pub fn pkgName(self: *const ParseResult, gpa: mem.Allocator, arch: common.Arch) ![]const u8 {
        const pkg_name = try std.mem.join(gpa, "-", &.{
            self.pkgbuild.pkgname,
            self.version,
            @tagName(try self.pkgbuild.selectArch(arch)),
        });
        return pkg_name;
    }
};

pub fn parse(gpa: mem.Allocator, reader: *std.Io.Reader) !ParseResult {
    var allocating: std.Io.Writer.Allocating = .init(gpa);
    defer allocating.deinit();
    _ = try reader.streamRemaining(&allocating.writer);
    try allocating.writer.flush();

    var diag: zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);

    const pkgbuild_src = try allocating.toOwnedSliceSentinel(0);
    defer gpa.free(pkgbuild_src);

    @setEvalBranchQuota(2000);
    const pkgbuild = try zon.parse.fromSliceAlloc(PkgBuild, gpa, pkgbuild_src, &diag, .{});

    var pkgbuild_digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(pkgbuild_src, &pkgbuild_digest, .{});

    return .{
        .pkgbuild = pkgbuild,
        .version = try pkgbuild.parseVersion(gpa),
        .hash = std.fmt.bytesToHex(pkgbuild_digest, .lower),
    };
}

fn parseVersion(self: *const PkgBuild, gpa: mem.Allocator) ![:0]const u8 {
    var allocating: std.Io.Writer.Allocating = .init(gpa);
    defer allocating.deinit();
    if (self.epoch == 0)
        try allocating.writer.print("{s}-{d}", .{
            self.pkgver,
            self.pkgrel,
        })
    else
        try allocating.writer.print("{d}:{s}-{d}", .{
            self.epoch,
            self.pkgver,
            self.pkgrel,
        });
    try allocating.writer.flush();
    return allocating.toOwnedSliceSentinel(0);
}

test {
    _ = @import("PkgBuild/test.zig");
}

const std = @import("std");
const zon = std.zon;
const mem = std.mem;
const common = @import("common.zig");
const License = @import("license.zig").License;
const Sha256 = std.crypto.hash.sha2.Sha256;
const PkgBuild = @This();
