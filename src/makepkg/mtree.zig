/// write mtree format v2 defined by alpm
pub const Options = struct {
    pkg_dir: std.fs.Dir,
    build_info: std.fs.File,
    pkg_info: std.fs.File,
};

pub fn writeDirWithMetadata(gpa: mem.Allocator, options: Options) !void {
    var write_buffer: [8 * 1024]u8 = undefined;
    var read_buffer: [8 * 1024]u8 = undefined;
    var writer: archive.Writer = try .init(gpa, &write_buffer, .{
        .dir = options.pkg_dir,
        .sub_path = ".MTREE",
        .flags = .{},
        .filter = .zstd,
        .format = .mtree,
        .fakeroot = true,
        .opts = &.{
            "!all", "use-set", "type", "uid",    "gid",
            "mode", "time",    "size", "sha256", "link",
        },
    });
    defer writer.deinit();

    {
        var file_reader = options.pkg_info.reader(&read_buffer);
        const st = try posix.fstat(options.pkg_info.handle);
        try writer.writerHeader(.{
            .stat = &st,
            .path = ".PKGINFO",
        });
        try writer.writeFile(&file_reader.interface);
    }

    {
        var file_reader = options.build_info.reader(&read_buffer);
        const st = try posix.fstat(options.build_info.handle);
        try writer.writerHeader(.{
            .stat = &st,
            .path = ".BUILDINFO",
        });
        try writer.writeFile(&file_reader.interface);
    }

    _ = try writer.writeDir(gpa, options.pkg_dir);
    return;
}

pub fn writeDir(gpa: mem.Allocator, dir: std.fs.Dir) !usize {
    var buffer: [8 * 1024]u8 = undefined;
    var writer: archive.Writer = try .init(gpa, &buffer, .{
        .dir = dir,
        .sub_path = ".MTREE",
        .flags = .{},
        .filter = .zstd,
        .format = .mtree,
        .fakeroot = true,
        .opts = &.{
            "!all", "use-set", "type", "uid",    "gid",
            "mode", "time",    "size", "sha256", "link",
        },
    });
    defer writer.deinit();
    return try writer.writeDir(gpa, dir);
}

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const archive = @import("archive");
