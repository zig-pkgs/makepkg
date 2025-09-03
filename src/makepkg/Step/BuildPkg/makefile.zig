pub fn build(_: @This(), bp: *BuildPkg) !void {
    const b = bp.step.owner;
    const gpa = b.allocator;

    const make_exe = try b.findProgram(&.{"make"}, &.{});

    const build_root = bp.getBuildRoot();
    const builddir = build_root.path(b, "builddir");
    const builddir_str = try builddir.getPath3(b, &bp.step).toString(gpa);

    var argv_list: std.ArrayList([]const u8) = .{};
    defer argv_list.deinit(gpa);
    try argv_list.appendSlice(gpa, &.{
        make_exe, "-C", builddir_str, "install", "PREFIX=../pkg/usr",
    });

    var code: u8 = undefined;
    _ = try b.runAllowFail(argv_list.items, &code, .Inherit);
}

const std = @import("std");
const BuildPkg = @import("../BuildPkg.zig");
