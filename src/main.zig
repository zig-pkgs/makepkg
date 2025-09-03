const std = @import("std");
const mem = std.mem;
const makepkg = @import("makepkg");

const usage =
    \\Usage: pkggen [options]
    \\
    \\Options:
    \\  --dest-dir DEST_DIR
    \\  --pkg-dir PKG_DIR
    \\  --build-info BUILDINFO
    \\  --pkg-info PKGINFO
    \\  --pkg-name FULL_PKG_NAME
    \\
;

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa = arena.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    var opt_dest_dir: ?[]const u8 = null;
    var opt_pkg_dir: ?[]const u8 = null;
    var opt_pkg_info: ?[]const u8 = null;
    var opt_build_info: ?[]const u8 = null;
    var opt_pkg_name: ?[]const u8 = null;

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, "-h", arg) or std.mem.eql(u8, "--help", arg)) {
            try std.fs.File.stdout().writeAll(usage);
            return std.process.cleanExit();
        } else if (mem.eql(u8, arg, "--dest-dir")) {
            opt_dest_dir = args.next() orelse fatal("expected arg after '{s}'\n", .{arg});
        } else if (mem.eql(u8, arg, "--pkg-dir")) {
            opt_pkg_dir = args.next() orelse fatal("expected arg after '{s}'\n", .{arg});
        } else if (mem.eql(u8, arg, "--pkg-name")) {
            opt_pkg_name = args.next() orelse fatal("expected arg after '{s}'\n", .{arg});
        } else if (mem.eql(u8, arg, "--pkg-info")) {
            opt_pkg_info = args.next() orelse fatal("expected arg after '{s}'\n", .{arg});
        } else if (mem.eql(u8, arg, "--build-info")) {
            opt_build_info = args.next() orelse fatal("expected arg after '{s}'\n", .{arg});
        } else {
            fatal("unrecognized arg: '{s}'\n", .{arg});
        }
    }

    const dest_dir_path = opt_dest_dir orelse fatal("missing --dest-dir\n", .{});

    const pkg_dir_path = opt_pkg_dir orelse fatal("missing --pkg-dir\n", .{});

    const pkg_name = opt_pkg_name orelse fatal("missing --pkg-name\n", .{});

    const pkg_info_path = opt_pkg_info orelse fatal("missing --pkg-info\n", .{});

    const build_info_path = opt_build_info orelse fatal("missing --build-info\n", .{});

    var pkg_dir = try std.fs.cwd().openDir(pkg_dir_path, .{ .iterate = true });
    defer pkg_dir.close();

    var dest_dir = try std.fs.cwd().openDir(dest_dir_path, .{});
    defer dest_dir.close();

    var pkg_info = try std.fs.cwd().openFile(pkg_info_path, .{});
    defer pkg_info.close();

    var build_info = try std.fs.cwd().openFile(build_info_path, .{});
    defer build_info.close();

    _ = try makepkg.mtree.writeDirWithMetadata(gpa, .{
        .pkg_dir = pkg_dir,
        .pkg_info = pkg_info,
        .build_info = build_info,
    });
    _ = try makepkg.package.writeDirWithMetadata(gpa, .{
        .dest_dir = dest_dir,
        .pkg_name = pkg_name,
        .pkg_dir = pkg_dir,
        .pkg_info = pkg_info,
        .build_info = build_info,
    });
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
