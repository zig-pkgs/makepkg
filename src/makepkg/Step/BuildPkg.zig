step: Step,
arch: common.Arch,
pkg_source: Build.LazyPath,
local_sources: std.ArrayList(Build.LazyPath),
result: PkgBuild.ParseResult,

generated_dir: std.Build.GeneratedFile,

pub const base_id: Step.Id = .custom;

pub const Options = struct {
    arch: common.Arch,
    package_metadata: common.PackageMetadata,
    first_ret_addr: ?usize = null,
};

pub fn create(owner: *Build, options: Options) *BuildPkg {
    const build_pkg = owner.allocator.create(BuildPkg) catch @panic("OOM");
    const pkg_source = options.package_metadata.source_file.dupe(owner);
    const result = options.package_metadata.parsed;
    const name = owner.fmt("build package {s}", .{result.pkgbuild.pkgname});

    build_pkg.* = .{
        .step = .init(.{
            .id = base_id,
            .name = name,
            .owner = owner,
            .makeFn = make,
            .first_ret_addr = options.first_ret_addr orelse @returnAddress(),
        }),
        .arch = options.arch,
        .result = result,
        .pkg_source = pkg_source,
        .local_sources = .{},
        .generated_dir = .{ .step = &build_pkg.step },
    };

    const pkg_source_dir = pkg_source.path(owner, "..");
    for (options.package_metadata.parsed.pkgbuild.sources) |src| {
        switch (src) {
            .local => |local_src| {
                const local_file = pkg_source_dir.path(owner, local_src.path);
                local_file.addStepDependencies(&build_pkg.step);
                build_pkg.local_sources.append(owner.allocator, local_file) catch @panic("OOM");
            },
            .remote => {},
        }
    }

    build_pkg.pkg_source.addStepDependencies(&build_pkg.step);
    return build_pkg;
}

pub fn getBuildRoot(p: *BuildPkg) std.Build.LazyPath {
    return .{ .generated = .{ .file = &p.generated_dir } };
}

fn make(step: *Step, options: Step.MakeOptions) !void {
    const b = step.owner;

    const build_pkg: *BuildPkg = @fieldParentPtr("step", step);

    const arena = b.allocator;

    const node_name = b.fmt("building package {s}", .{build_pkg.result.pkgbuild.pkgname});
    const build_pkg_node = options.progress_node.start(node_name, 1);

    defer {
        build_pkg_node.completeOne();
        build_pkg_node.end();
    }

    if (!step.inputs.populated()) {
        try step.addWatchInput(build_pkg.pkg_source);
        for (build_pkg.local_sources.items) |path| try step.addWatchInput(path);
    }

    const pkgbuild_path = build_pkg.pkg_source.getPath3(b, step);

    var man = b.graph.cache.obtain();
    defer man.deinit();

    // Random bytes to make ConfigHeader unique. Refresh this with new
    // random bytes when ConfigHeader implementation is modified in a
    // non-backwards-compatible way.
    man.hash.add(@as(u32, 0x677eba6f));
    _ = try man.addFilePath(pkgbuild_path, null);
    for (build_pkg.local_sources.items) |path| {
        const p = path.getPath3(b, step);
        _ = try man.addFilePath(p, null);
    }

    if (try step.cacheHit(&man)) {
        const digest = man.final();
        build_pkg.generated_dir.path = try b.cache_root.join(arena, &.{ "o", &digest });
        return;
    }

    const digest = man.final();
    // If output_path has directory parts, deal with them.  Example:
    // output_dir is zig-cache/o/HASH
    // output_path is libavutil/avconfig.h
    // We want to open directory zig-cache/o/HASH/libavutil/
    // but keep output_dir as zig-cache/o/HASH for -I include
    const sub_path_builddir = b.pathJoin(&.{ "o", &digest, "builddir" });
    const sub_path_pkgdir = b.pathJoin(&.{ "o", &digest, "pkg" });
    b.cache_root.handle.makePath(sub_path_builddir) catch |err| {
        return step.fail("unable to make path '{f}{s}': {s}", .{
            b.cache_root, sub_path_builddir, @errorName(err),
        });
    };

    for (build_pkg.local_sources.items) |path| {
        const p = path.getPath3(b, step);
        const path_str = try p.toString(b.graph.arena);
        const symlink_path = b.pathJoin(&.{ sub_path_builddir, std.fs.path.basename(path_str) });
        try b.cache_root.handle.atomicSymLink(path_str, symlink_path, .{});
    }

    b.cache_root.handle.makePath(sub_path_pkgdir) catch |err| {
        return step.fail("unable to make path '{f}{s}': {s}", .{
            b.cache_root, sub_path_pkgdir, @errorName(err),
        });
    };

    build_pkg.generated_dir.path = try b.cache_root.join(arena, &.{ "o", &digest });

    switch (build_pkg.result.pkgbuild.build_style) {
        inline else => |style| {
            const style_name = @tagName(style);
            const s = @unionInit(BuildStyle, style_name, .{});
            try @field(s, style_name).build(build_pkg);
        },
    }

    try man.writeManifest();
}

const BuildStyle = union(common.BuildStyle) {
    makefile: @import("BuildPkg/makefile.zig"),
    cmake: @import("BuildPkg/cmake.zig"),
    configure: @import("BuildPkg/configure.zig"),
};

const std = @import("std");
const mem = std.mem;
const Build = std.Build;
const Step = Build.Step;
const assert = std.debug.assert;
const common = @import("../common.zig");
const PkgBuild = @import("../PkgBuild.zig");
const BuildInfo = @import("../BuildInfo.zig");
const PkgInfo = @import("../PkgInfo.zig");
const BuildPkg = @This();
