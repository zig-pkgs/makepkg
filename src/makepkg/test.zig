const std = @import("std");
const zon = std.zon;
const testing = std.testing;
const makepkg = @import("../root.zig");
const Sha256 = std.crypto.hash.sha2.Sha256;

test {
    var tmpdir = testing.tmpDir(.{});
    defer tmpdir.cleanup();

    const pkgbuild_file = @embedFile("PkgBuild/PKGBUILD.zon");
    var pkgbuild_reader = std.Io.Reader.fixed(pkgbuild_file);

    const result = try makepkg.PkgBuild.parse(testing.allocator, &pkgbuild_reader);
    defer result.deinit(testing.allocator);

    var pkg_dir = try tmpdir.dir.makeOpenPath("pkg", .{ .iterate = true });
    defer pkg_dir.close();

    {
        var bin_dir = try pkg_dir.makeOpenPath("usr/bin", .{});
        defer bin_dir.close();
        var script = try bin_dir.createFile("helloworld.sh", .{});
        defer script.close();
        try script.chmod(0o755);
        try script.writeAll("#!/bin/sh\necho \"hello world!\"");

        try bin_dir.symLink("helloworld.sh", "helloworld", .{});
    }

    try makepkg.preparePkg(testing.allocator, .{
        .pkg_dir = pkg_dir,
        .builddir = "/builddir",
        .pkgbuild_parsed = &result,
    });

    const pkg_name = try result.pkgName(testing.allocator, .x86_64);
    defer testing.allocator.free(pkg_name);

    _ = try makepkg.mtree.writeDir(testing.allocator, pkg_dir);
    _ = try makepkg.package.writeDir(testing.allocator, .{
        .dest_dir = tmpdir.dir,
        .pkg_name = pkg_name,
        .pkg_dir = pkg_dir,
    });
}
