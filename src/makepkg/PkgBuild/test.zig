test {
    const pkgbuild_file = @embedFile("PKGBUILD.zon");

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stderr().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(testing.allocator);

    const parsed = std.zon.parse.fromSliceAlloc(PkgBuild, testing.allocator, pkgbuild_file, &diag, .{}) catch |err| {
        try diag.format(stdout);
        try stdout.flush();
        return err;
    };
    defer std.zon.parse.free(testing.allocator, parsed);
}

const std = @import("std");
const PkgBuild = @import("../PkgBuild.zig");
const testing = std.testing;
