step: Step,
arch: common.Arch,
packager: [:0]const u8,
pkg_build_root: Build.LazyPath,
pkggen_exe: *Step.Compile,
result: PkgBuild.ParseResult,

generated_dir: std.Build.GeneratedFile,

pub const base_id: Step.Id = .custom;
pub const default_packager = "Unknown Packager";

pub const Options = struct {
    arch: common.Arch,
    package_metadata: common.PackageMetadata,
    packager: ?[:0]const u8 = null,
    pkg_build_root: Build.LazyPath,
    pkggen_exe: *Step.Compile,
    first_ret_addr: ?usize = null,
};

pub fn create(owner: *Build, options: Options) *CreatePkg {
    const create_pkg = owner.allocator.create(CreatePkg) catch @panic("OOM");

    const pkg_build_root = options.pkg_build_root.dupe(owner);
    const result = options.package_metadata.parsed;
    const name = owner.fmt("create package {s}", .{result.pkgbuild.pkgname});

    create_pkg.* = .{
        .step = .init(.{
            .id = base_id,
            .name = name,
            .owner = owner,
            .makeFn = make,
            .first_ret_addr = options.first_ret_addr orelse @returnAddress(),
        }),
        .arch = options.arch,
        .result = result,
        .packager = options.packager orelse default_packager,
        .pkg_build_root = pkg_build_root,
        .pkggen_exe = options.pkggen_exe,
        .generated_dir = .{ .step = &create_pkg.step },
    };

    create_pkg.step.dependOn(&options.pkggen_exe.step);
    create_pkg.pkg_build_root.addStepDependencies(&create_pkg.step);
    return create_pkg;
}

fn make(step: *Step, options: Step.MakeOptions) !void {
    const b = step.owner;

    const gpa = b.allocator;
    const arena = b.allocator;

    const create_pkg: *CreatePkg = @fieldParentPtr("step", step);

    const node_name = b.fmt("creating package {s}", .{create_pkg.result.pkgbuild.pkgname});
    const create_pkg_node = options.progress_node.start(node_name, 1);

    defer {
        create_pkg_node.completeOne();
        create_pkg_node.end();
    }

    const pkg_path = create_pkg.pkg_build_root.path(b, "pkg");
    const buildir_path = create_pkg.pkg_build_root.path(b, "builddir");
    const buildir_path_str = try buildir_path.getPath3(b, step).toString(gpa);
    const pkg_path_str = try pkg_path.getPath3(b, step).toString(gpa);

    _ = try step.addDirectoryWatchInput(pkg_path);

    var man = b.graph.cache.obtain();
    defer man.deinit();

    // Random bytes to make CreatePkg unique. Refresh this with new
    // random bytes when CreatePkg implementation is modified in a
    // non-backwards-compatible way.
    man.hash.add(@as(u32, 0x3ea6afa7));
    const pkg_dir_size = try hashDirPath(create_pkg, &man, pkg_path);

    if (try step.cacheHit(&man)) {
        const digest = man.final();
        create_pkg.generated_dir.path = try b.cache_root.join(arena, &.{ "o", &digest });
        return;
    }

    const digest = man.final();

    const result = create_pkg.result;

    const pkgbuild = result.pkgbuild;
    const pkgbase = if (pkgbuild.pkgbase) |pkgbase| pkgbase else pkgbuild.pkgname;

    const builddate = std.time.timestamp();

    const start_dir = try std.fs.cwd().realpathAlloc(gpa, ".");
    defer gpa.free(start_dir);

    var aw: std.Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    const bw = &aw.writer;

    const build_info: BuildInfo = .{
        .pkgbase = pkgbase,
        .pkgname = pkgbuild.pkgname,
        .pkgver = result.version,
        .pkgarch = pkgbuild.arch,
        .pkgbuild_sha256sum = &result.hash,
        .packager = create_pkg.packager,
        .builddate = builddate,
        .builddir = buildir_path_str,
        .startdir = start_dir,
        .buildtool = "devtools",
        .buildtoolver = "1:1.0.4-1-any",
    };

    const build_info_bytes = formatPrint(bw, build_info) catch |err| {
        return step.fail("unable to create .BUILDINFO file for pkg '{s}': {s}", .{
            pkgbuild.pkgname, @errorName(err),
        });
    };

    const pkg_info: PkgInfo = .{
        .pkgbase = pkgbase,
        .pkgname = pkgbuild.pkgname,
        .size = pkg_dir_size,
        .builddate = builddate,
        .license = pkgbuild.license,
        .pkgdesc = pkgbuild.pkgdesc,
        .url = pkgbuild.url,
        .pkgver = result.version,
        .arch = pkgbuild.arch,
        .packager = create_pkg.packager,
        .xdata = &.{
            .{ .pkgtype = .pkg },
        },
        .group = pkgbuild.groups,
        .backup = pkgbuild.backup,
    };

    const pkg_info_bytes = formatPrint(bw, pkg_info) catch |err| {
        return step.fail("unable to create .PKGINFO file for pkg '{s}': {s}", .{
            pkgbuild.pkgname, @errorName(err),
        });
    };

    // If output_path has directory parts, deal with them.  Example:
    // output_dir is zig-cache/o/HASH
    // output_path is libavutil/avconfig.h
    // We want to open directory zig-cache/o/HASH/libavutil/
    // but keep output_dir as zig-cache/o/HASH for -I include
    const sub_path_dirname = b.pathJoin(&.{ "o", &digest });
    const sub_path_buildinfo = b.pathJoin(&.{ sub_path_dirname, ".BUILDINFO" });
    const sub_path_pkginfo = b.pathJoin(&.{ sub_path_dirname, ".PKGINFO" });

    const generated_dir = try b.cache_root.join(arena, &.{ "o", &digest });

    b.cache_root.handle.makePath(sub_path_dirname) catch |err| {
        return step.fail("unable to make path '{f}{s}': {s}", .{
            b.cache_root, sub_path_dirname, @errorName(err),
        });
    };

    b.cache_root.handle.writeFile(.{ .sub_path = sub_path_buildinfo, .data = build_info_bytes }) catch |err| {
        return step.fail("unable to write file '{f}{s}': {s}", .{
            b.cache_root, sub_path_buildinfo, @errorName(err),
        });
    };

    b.cache_root.handle.writeFile(.{ .sub_path = sub_path_pkginfo, .data = pkg_info_bytes }) catch |err| {
        return step.fail("unable to write file '{f}{s}': {s}", .{
            b.cache_root, sub_path_pkginfo, @errorName(err),
        });
    };

    const full_pkgname = try result.pkgName(gpa, create_pkg.arch);
    const pkggen_exe = create_pkg.pkggen_exe;
    const exe_path = pkggen_exe.installed_path orelse pkggen_exe.generated_bin.?.path.?;

    var argv_list: std.ArrayList([]const u8) = .{};
    defer argv_list.deinit(gpa);

    try argv_list.appendSlice(gpa, &.{
        exe_path,
        "--pkg-dir",
        pkg_path_str,
        "--pkg-info",
        try b.cache_root.join(gpa, &.{sub_path_pkginfo}),
        "--build-info",
        try b.cache_root.join(gpa, &.{sub_path_buildinfo}),
        "--pkg-name",
        full_pkgname,
        "--dest-dir",
        generated_dir,
    });

    var code: u8 = undefined;
    _ = try b.runAllowFail(argv_list.items, &code, .Inherit);

    create_pkg.generated_dir.path = generated_dir;

    try man.writeManifest();
}

pub fn getOutputDir(p: *CreatePkg) std.Build.LazyPath {
    return .{ .generated = .{ .file = &p.generated_dir } };
}

pub fn installPackage(p: *CreatePkg) void {
    const b = p.step.owner;
    const gpa = b.allocator;
    const out_dir = p.getOutputDir();
    const pkgname = p.result.pkgName(gpa, p.arch) catch @panic("OOM");
    const pkg_file_name = b.fmt("{s}{s}", .{ pkgname, common.pkg_extension });
    const pkg_path = out_dir.path(b, pkg_file_name);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(pkg_path, .{ .custom = "packages" }, pkg_file_name).step);
}

fn formatPrint(w: *std.Io.Writer, info: anytype) ![]u8 {
    var aw: *std.Io.Writer.Allocating = @fieldParentPtr("writer", w);
    const Info = @TypeOf(info);
    try w.print("{f}", .{Info.fmt(info)});
    try w.flush();
    const output = try aw.toOwnedSlice();
    aw.clearRetainingCapacity();
    return output;
}

fn hashDirPath(p: *CreatePkg, man: *Build.Cache.Manifest, pkg_path: Build.LazyPath) !usize {
    const b = p.step.owner;
    const gpa = b.allocator;

    const pkg_path_str = try pkg_path.getPath3(b, &p.step).toString(gpa);
    var dir = try b.build_root.handle.openDir(pkg_path_str, .{ .iterate = true });

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var total_size: usize = 0;

    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (mem.eql(u8, entry.basename, ".MTREE")) continue;
                const file_path = pkg_path.path(b, entry.path);
                _ = try man.addFilePath(file_path.getPath3(b, &p.step), null);
                total_size += (try entry.dir.statFile(entry.basename)).size;
            },
            else => {},
        }
    }

    return total_size;
}

const std = @import("std");
const mem = std.mem;
const Build = std.Build;
const Step = Build.Step;
const assert = std.debug.assert;
const common = @import("../common.zig");
const PkgBuild = @import("../PkgBuild.zig");
const BuildInfo = @import("../BuildInfo.zig");
const PkgInfo = @import("../PkgInfo.zig");
const CreatePkg = @This();
