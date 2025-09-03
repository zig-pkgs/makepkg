//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const mem = std.mem;
const Build = std.Build;
pub const Step = @import("makepkg/Step.zig");
pub const common = @import("makepkg/common.zig");
pub const PkgInfo = @import("makepkg/PkgInfo.zig");
pub const BuildInfo = @import("makepkg/BuildInfo.zig");
pub const PkgBuild = @import("makepkg/PkgBuild.zig");
pub const package = @import("makepkg/package.zig");
pub const mtree = @import("makepkg/mtree.zig");

const default_packager = "Unknown Packager";

pub const PreparePkgOptions = struct {
    pkg_dir: std.fs.Dir,
    pkgbuild_parsed: *const PkgBuild.ParseResult,
    packager: ?[:0]const u8 = null,
    builddir: []const u8,
};

/// Prepares a package, which generates .PKGINFO and .BUILDINFO based on
/// the PKGBUILD.zon parsed.
pub fn preparePkg(gpa: mem.Allocator, options: PreparePkgOptions) !void {
    var buffer: [8 * 1024]u8 = undefined;

    const pkgbuild = options.pkgbuild_parsed.pkgbuild;
    const pkgbase = if (pkgbuild.pkgbase) |pkgbase| pkgbase else pkgbuild.pkgname;

    const pkg_dir = options.pkg_dir;

    const dir_size = try dirSize(gpa, pkg_dir);
    const builddate = std.time.timestamp();
    const packager = if (options.packager) |p| p else default_packager;

    const start_dir = try std.fs.cwd().realpathAlloc(gpa, ".");
    defer gpa.free(start_dir);

    const build_info: BuildInfo = .{
        .pkgbase = pkgbase,
        .pkgname = pkgbuild.pkgname,
        .pkgver = options.pkgbuild_parsed.version,
        .pkgarch = pkgbuild.arch,
        .pkgbuild_sha256sum = &options.pkgbuild_parsed.hash,
        .packager = packager,
        .builddate = builddate,
        .builddir = options.builddir,
        .startdir = start_dir,
        .buildtool = "devtools",
        .buildtoolver = "1:1.0.4-1-any",
    };

    {
        var build_info_file = try pkg_dir.createFile(".BUILDINFO", .{});
        defer build_info_file.close();

        var file_writer = build_info_file.writer(&buffer);
        const writer = &file_writer.interface;
        try writer.print("{f}", .{BuildInfo.fmt(build_info)});
        try writer.flush();
    }

    const pkg_info: PkgInfo = .{
        .pkgbase = pkgbase,
        .pkgname = pkgbuild.pkgname,
        .size = dir_size,
        .builddate = builddate,
        .pkgdesc = pkgbuild.pkgdesc,
        .url = pkgbuild.url,
        .pkgver = options.pkgbuild_parsed.version,
        .arch = pkgbuild.arch,
        .packager = packager,
        .xdata = &.{
            .{ .pkgtype = .pkg },
        },
    };

    {
        var pkg_info_file = try pkg_dir.createFile(".PKGINFO", .{});
        defer pkg_info_file.close();

        var file_writer = pkg_info_file.writer(&buffer);
        const writer = &file_writer.interface;
        try writer.print("{f}", .{PkgInfo.fmt(pkg_info)});
        try writer.flush();
    }
}

fn dirSize(gpa: mem.Allocator, dir: std.fs.Dir) !usize {
    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var total_size: usize = 0;

    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                total_size += (try entry.dir.statFile(entry.basename)).size;
            },
            else => {},
        }
    }

    return total_size;
}

test {
    _ = PkgInfo;
    _ = BuildInfo;
    _ = PkgBuild;
    _ = @import("makepkg/test.zig");
}
