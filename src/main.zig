const std = @import("std");
const mem = std.mem;
const log = std.log;
const alpm = @import("alpm");
const container = @import("container");
const makepkg = @import("makepkg");
const common = makepkg.common;

const usage =
    \\Usage: pkggen <subcmds> [options]
    \\
    \\Subcmds:
    \\  genpkg
    \\  bootstrap
    \\
    \\Options:
    \\  --config CONFIG_FILE
    \\
;

const Subcmds = enum {
    genpkg,
    bootstrap,
};

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa = arena.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    var opt_config_file: ?[]const u8 = null;

    _ = args.skip();

    const subcmd_str = args.next() orelse fatal("missing subcmd\n", .{});

    const subcmd = std.meta.stringToEnum(Subcmds, subcmd_str) orelse fatal("unknown subcmd: '{s}'\n", .{subcmd_str});

    while (args.next()) |arg| {
        if (std.mem.eql(u8, "-h", arg) or std.mem.eql(u8, "--help", arg)) {
            try std.fs.File.stdout().writeAll(usage);
            return std.process.cleanExit();
        } else if (mem.eql(u8, arg, "--config")) {
            opt_config_file = args.next() orelse fatal("expected arg after '{s}'\n", .{arg});
        } else {
            fatal("unrecognized arg: '{s}'\n", .{arg});
        }
    }

    const config_file = opt_config_file orelse fatal("missing --config\n", .{});
    var config = try std.fs.cwd().openFile(config_file, .{});
    defer config.close();

    var buffer: [8 * 1024]u8 = undefined;
    var config_reader = config.reader(&buffer);
    switch (subcmd) {
        .genpkg => try handleGenpkg(gpa, &config_reader.interface),
        .bootstrap => try handleBootstrap(gpa, &config_reader.interface),
    }
}

fn handleBootstrap(gpa: mem.Allocator, r: *std.Io.Reader) !void {
    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);

    var allocating: std.Io.Writer.Allocating = .init(gpa);
    defer allocating.deinit();

    _ = try r.streamRemaining(&allocating.writer);

    try allocating.writer.flush();

    const config = try std.zon.parse.fromSliceAlloc(common.BootstrapOptions, gpa, try allocating.toOwnedSliceSentinel(0), &diag, .{});

    var chroot: alpm.Chroot = try .init(gpa);
    defer chroot.deinit();

    try chroot.unshareSetup(config.rootdir);
    defer chroot.unshareTeardown();

    const cachedir = try std.fs.path.joinZ(gpa, &.{
        config.rootdir,
        alpm.defaults.cachedir,
    });
    defer gpa.free(cachedir);

    const dbpath = try std.fs.path.joinZ(gpa, &.{
        config.rootdir,
        alpm.defaults.dbpath,
    });
    defer gpa.free(dbpath);

    const hookdir = try std.fs.path.joinZ(gpa, &.{
        config.rootdir,
        alpm.defaults.hookdir,
    });
    defer gpa.free(hookdir);

    const logfile = try std.fs.path.joinZ(gpa, &.{
        config.rootdir,
        alpm.defaults.logfile,
    });
    defer gpa.free(logfile);

    var handle: alpm.Handle = try .init(gpa, config.rootdir, dbpath);
    defer handle.deinit();

    handle.setFetchCallback();
    handle.setEventCallback();
    handle.setDownloadCallback();
    handle.setProgressCallback();
    handle.setParallelDownload(5);

    try handle.setLogFile(logfile);
    try handle.setCacheDirs(try .fromSlice(handle.arena.allocator(), &.{cachedir}));
    try handle.setGpgDir(alpm.defaults.gpgdir);
    try handle.addHookDir(hookdir);
    try handle.addArchitecture("x86_64");
    try handle.setDisableSandbox(true);

    var core_db = try handle.registerSyncDb("core", .{});
    try core_db.setUsage(alpm.Database.Usage.all);
    try core_db.addServer(config.repos.core);
    var extra_db = try handle.registerSyncDb("extra", .{});
    try extra_db.setUsage(alpm.Database.Usage.all);
    try extra_db.addServer(config.repos.extra);

    const sync_dbs = handle.getSyncDbs();
    _ = try handle.dbUpdate(sync_dbs, true);

    try handle.transactionInit(.{ .downloadonly = false });
    defer handle.transactionRelease();

    var local_db = handle.getLocalDb();

    for (config.targets) |target| {
        if (handle.findDbsSatisfier(sync_dbs, target)) |pkg| {
            try handle.addPackage(pkg);
        }
    }

    try handle.transactionPrepare();
    if (handle.getAddList().empty() and handle.getRemoveList().empty()) {
        log.info("There is nothing to do", .{});
        return;
    } else {
        var add_list = handle.getAddList();
        var it_add = add_list.iterator();
        while (it_add.next()) |pkg| {
            const name_cstr = pkg.getNameSentinel();
            const name = mem.span(name_cstr);
            if (local_db.getPackage(name)) |old_pkg| {
                switch (pkg.compareVersions(old_pkg)) {
                    .lt => {
                        log.debug("downgrading {s}", .{name});
                        try handle.downgrade_map.put(name, .none);
                    },
                    .eq => {
                        log.debug("reinstalling {s}", .{name});
                        try handle.reinstall_map.put(name, .none);
                    },
                    .gt => {
                        log.debug("upgrading {s}", .{name});
                        try handle.upgrade_map.put(name, .none);
                    },
                }
            } else {
                log.debug("installing {s}", .{name});
                try handle.install_map.put(name, .none);
            }
        }

        var remove_list = handle.getRemoveList();
        var it_remove = remove_list.iterator();
        while (it_remove.next()) |pkg| {
            const name_cstr = pkg.getNameSentinel();
            const name = mem.span(name_cstr);
            log.debug("removing {s}", .{name});
            try handle.remove_map.put(name, .none);
        }
    }
    try handle.transactionCommit();
}

fn handleGenpkg(gpa: mem.Allocator, r: *std.Io.Reader) !void {
    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);

    var allocating: std.Io.Writer.Allocating = .init(gpa);
    defer allocating.deinit();

    _ = try r.streamRemaining(&allocating.writer);

    try allocating.writer.flush();

    const config = try std.zon.parse.fromSliceAlloc(common.GeneratePkgOptions, gpa, try allocating.toOwnedSliceSentinel(0), &diag, .{});

    var pkg_dir = try std.fs.cwd().openDir(config.pkgdir, .{ .iterate = true });
    defer pkg_dir.close();

    var dest_dir = try std.fs.cwd().openDir(config.destdir, .{});
    defer dest_dir.close();

    var pkg_info = try std.fs.cwd().openFile(config.pkginfo, .{});
    defer pkg_info.close();

    var build_info = try std.fs.cwd().openFile(config.buildinfo, .{});
    defer build_info.close();

    _ = try makepkg.mtree.writeDirWithMetadata(gpa, .{
        .pkg_dir = pkg_dir,
        .pkg_info = pkg_info,
        .build_info = build_info,
    });
    _ = try makepkg.package.writeDirWithMetadata(gpa, .{
        .dest_dir = dest_dir,
        .pkg_name = config.pkgname,
        .pkg_dir = pkg_dir,
        .pkg_info = pkg_info,
        .build_info = build_info,
    });
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
