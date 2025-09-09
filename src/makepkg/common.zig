pub const Arch = enum {
    any,
    x86_64,
    aarch64,
};

pub const Options = union(enum) {
    strip: bool,
    docs: bool,
    libtool: bool,
    staticlibs: bool,
    emptydirs: bool,
    zipman: bool,
    ccache: bool,
    distcc: bool,
    buildflags: bool,
    makeflags: bool,
    debug: bool,
    lto: bool,
};

pub const Source = union(enum) {
    pub const Local = struct {
        path: []const u8,
    };

    pub const Remote = struct {
        name: ?[]const u8 = null,
        url: []const u8,
    };

    local: Local,
    remote: Remote,
};

pub const Sources = []const Source;

pub const PackageMetadata = struct {
    source_file: std.Build.LazyPath,
    parsed: PkgBuild.ParseResult,
};

/// The value for a dependency is either an alpm-package-name or an alpm-comparison (e.g. example or example>=1.0.0).
pub const Dependency = union(Arch) {
    any: [:0]const u8,
    x86_64: [:0]const u8,
    aarch64: [:0]const u8,
};

pub const License = @import("license.zig").License;

pub const BuildStyle = enum {
    makefile,
    cmake,
    configure,

    // TODO: support more build styles
};

pub const InstallReason = enum(u8) {
    explicit = 0,
    dependency = 1,
};

pub const ExtraData = union(enum) {
    pkgtype: PkgType,
};

pub const PkgType = enum {
    debug,
    pkg,
    src,
    split,
};

pub const Validation = enum {
    none,
    md5,
    sha256,
    pgp,
};

pub const pkg_extension = ".pkg.tar.zst";

pub const Repositories = struct {
    core: [:0]const u8,
    extra: [:0]const u8,
    alarm: ?[:0]const u8 = null,
};

pub const BootstrapOptions = struct {
    rootdir: [:0]const u8,
    targets: []const [:0]const u8,
    repos: Repositories,
};

pub const GeneratePkgOptions = struct {
    destdir: []const u8,
    pkgdir: []const u8,
    buildinfo: []const u8,
    pkginfo: []const u8,
    pkgname: []const u8,
};

const PkgBuild = @import("PkgBuild.zig");
const std = @import("std");
