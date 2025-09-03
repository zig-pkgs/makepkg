/// write package format defined by alpm
pub const Options = struct {
    pkg_dir: std.fs.Dir,
    dest_dir: std.fs.Dir,
    pkg_name: []const u8,

    build_info: std.fs.File,
    pkg_info: std.fs.File,
};

pub fn writeDirWithMetadata(gpa: mem.Allocator, options: Options) !void {
    var write_buffer: [8 * 1024]u8 = undefined;
    var read_buffer: [8 * 1024]u8 = undefined;

    const pkg_file_name = try std.fmt.allocPrint(gpa, "{s}{s}", .{ options.pkg_name, common.pkg_extension });
    defer gpa.free(pkg_file_name);

    var writer: archive.Writer = try .init(gpa, &write_buffer, .{
        .dir = options.dest_dir,
        .sub_path = pkg_file_name,
        .flags = .{},
        .filter = .zstd,
        .format = .pax_restricted,
        .fakeroot = true,
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

pub const WritePkgOptions = struct {
    pkg_dir: std.fs.Dir,
    dest_dir: std.fs.Dir,
    pkg_name: []const u8,
};

pub fn writeDir(gpa: mem.Allocator, options: WritePkgOptions) !usize {
    var buffer: [8 * 1024]u8 = undefined;
    const pkg_file_name = try std.fmt.allocPrint(gpa, "{s}.pkg.tar.gz", .{options.pkg_name});
    defer gpa.free(pkg_file_name);
    var writer: archive.Writer = try .init(gpa, &buffer, .{
        .dir = options.dest_dir,
        .sub_path = pkg_file_name,
        .flags = .{},
        .filter = .zstd,
        .format = .pax_restricted,
        .fakeroot = true,
    });
    defer writer.deinit();
    return try writer.writeDir(gpa, options.pkg_dir);
}

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const common = @import("common.zig");
const archive = @import("archive");
