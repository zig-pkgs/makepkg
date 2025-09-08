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

pub const pkg_extension = ".pkg.tar.zst";

const PkgBuild = @import("PkgBuild.zig");
const std = @import("std");
