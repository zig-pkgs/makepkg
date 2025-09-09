cache_dir: []const u8,
repos: std.StringHashMap(Repo),

pub fn init(gpa: mem.Allocator, cache_dir: []const u8) !SyncDbs {
    return .{
        .repos = .init(gpa),
        .cache_dir = try gpa.dupe(u8, cache_dir),
    };
}

pub const RegisterOptions = struct {
    name: []const u8,
    url: []const u8,
};

pub fn register(self: *SyncDbs, options: RegisterOptions) !void {
    const gpa = self.repos.allocator;

    const repo: Repo = try .init(gpa, .{
        .name = options.name,
        .url = options.url,
    });

    try self.repos.put(std.fs.path.stem(repo.name), repo);
}

pub fn update(self: *SyncDbs) !void {
    const gpa = self.repos.allocator;

    var wg: std.Thread.WaitGroup = .{};

    var cache_dir = try std.fs.cwd().openDir(self.cache_dir, .{});
    defer cache_dir.close();

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = gpa });
    defer thread_pool.deinit();

    var it = self.repos.iterator();
    while (it.next()) |entry| {
        thread_pool.spawnWg(&wg, fetchDb, .{
            gpa,
            entry.value_ptr,
            cache_dir,
        });
    }

    thread_pool.waitAndWork(&wg);
}

fn fetchDb(gpa: mem.Allocator, repo: *Repo, cache_dir: std.fs.Dir) void {
    fetchDbAllowFail(gpa, repo, cache_dir) catch |err| {
        std.log.err("fetch db: {t}", .{err});
        return;
    };
}

fn fetchDbAllowFail(gpa: mem.Allocator, repo: *Repo, cache_dir: std.fs.Dir) !void {
    var client: std.http.Client = .{ .allocator = gpa };
    defer client.deinit();

    const base_url = try std.Uri.parse(repo.url);
    var buf = try gpa.alloc(u8, 8 * 1024);
    defer gpa.free(buf);
    @memcpy(buf[0..repo.name.len], repo.name);
    var aux_buf = buf;

    var file = try cache_dir.createFile(repo.name, .{ .read = true });
    defer file.close();

    var buffer: [8 * 1024]u8 = undefined;
    var file_writer = file.writer(&buffer);

    const uri = try base_url.resolveInPlace(repo.name.len, &aux_buf);
    _ = try client.fetch(.{
        .response_writer = &file_writer.interface,
        .location = .{ .uri = uri },
    });

    try file_writer.interface.flush();

    var file_reader = file.reader(&buffer);

    repo.db = try .parse(gpa, &file_reader.interface);
}

pub fn deinit(self: *SyncDbs) void {
    const gpa = self.repos.allocator;
    gpa.free(self.cache_dir);
    var it = self.repos.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit(gpa);
    }
    self.repos.deinit();
}

const DependencyReq = struct {
    name: []const u8,
    mod: std.math.CompareOperator,
    version: ?[]const u8,
};

fn parseDependencyReq(dep_string: []const u8) DependencyReq {
    if (mem.indexOf(u8, dep_string, ">=")) |idx| {
        return .{
            .name = dep_string[0..idx],
            .mod = .gte,
            .version = dep_string[idx + 2 ..],
        };
    } else if (mem.indexOf(u8, dep_string, "<=")) |idx| {
        return .{
            .name = dep_string[0..idx],
            .mod = .lte,
            .version = dep_string[idx + 2 ..],
        };
    } else if (mem.indexOf(u8, dep_string, "=")) |idx| {
        return .{
            .name = dep_string[0..idx],
            .mod = .eq,
            .version = dep_string[idx + 1 ..],
        };
    } else if (mem.indexOf(u8, dep_string, ">")) |idx| {
        return .{
            .name = dep_string[0..idx],
            .mod = .gt,
            .version = dep_string[idx + 1 ..],
        };
    } else if (mem.indexOf(u8, dep_string, "<")) |idx| {
        return .{
            .name = dep_string[0..idx],
            .mod = .lt,
            .version = dep_string[idx + 1 ..],
        };
    }
    return .{
        .name = dep_string,
        .mod = .eq,
        .version = null,
    };
}

const VersionParseError = error{
    InvalidVersion,
} || std.fmt.ParseIntError;

/// The final, correct implementation.
/// Checks if a package's version satisfies a dependency requirement.
fn pkgSatisfiesReq(pkg_version_str: []const u8, req: DependencyReq) !bool {
    // A dependency with no version constraint is always satisfied by name.
    if (req.version == null) return true;

    const pkg_version = try AlpmVersion.parse(pkg_version_str);
    const req_version = try AlpmVersion.parse(req.version.?);

    return pkg_version.order(req_version).compare(req.mod);
}

const ResolveError = error{
    UnsatisfiedDependency,
    DependencyCycle,
    TargetNotFound,
} || VersionParseError || mem.Allocator.Error;

/// Phase 1, Step A (Core Logic): Find the best package satisfying a dependency request struct.
fn findPackageForReq(self: *const SyncDbs, req: DependencyReq) ResolveError!?*const Repo.Desc {
    // The logic is the same as the old findPackageFor, but we no longer need to parse.
    var it = self.repos.valueIterator();
    while (it.next()) |repo| {
        if (repo.db.pkg_map.getPtr(req.name)) |pkg| {
            if (try pkgSatisfiesReq(pkg.version, req)) return pkg;
        }
        if (repo.db.provide_map.get(req.name)) |list| {
            for (list.items) |provider| {
                if (try pkgSatisfiesReq(provider.version orelse "0.0.0", req)) {
                    return repo.db.pkg_map.getPtr(provider.pkg_name);
                }
            }
        }
    }
    return null;
}

/// Phase 1, Step A (Wrapper): Find the best package satisfying a dependency string.
fn findPackageFor(self: *const SyncDbs, dep_string: []const u8) ResolveError!?*const Repo.Desc {
    const req = parseDependencyReq(dep_string);
    return self.findPackageForReq(req);
}

/// Phase 1, Step B: Recursively build the complete, unordered set of packages.
fn resolve(self: *const SyncDbs, dep_string: []const u8, resolved_set: *Repo.Desc.RefMap) ResolveError!void {
    const req = parseDependencyReq(dep_string);
    if (resolved_set.contains(req.name)) return;

    const pkg = try self.findPackageForReq(req) orelse {
        std.log.err("cannot resolve dependency '{s}'", .{dep_string});
        return error.UnsatisfiedDependency;
    };
    if (resolved_set.contains(pkg.name)) return;

    try resolved_set.put(pkg.name, pkg);

    if (pkg.depends) |dependencies| {
        for (dependencies) |dep| try self.resolve(dep, resolved_set);
    }
}

/// Phase 2: Topologically sort the resolved set of packages.
fn topologicalSort(
    self: *const SyncDbs,
    pkg_set: *const Repo.Desc.RefMap,
    sorted_list: *std.ArrayList([]const u8),
    visiting: *std.BufSet,
    finished: *std.BufSet,
    pkg_name: []const u8,
) ResolveError!void {
    const gpa = self.repos.allocator;

    if (finished.contains(pkg_name)) return;
    if (visiting.contains(pkg_name)) {
        // NOTE: pacman simply warn dependency cycle then continue
        // return error.DependencyCycle;
        return;
    }

    try visiting.insert(pkg_name);

    const pkg = pkg_set.get(pkg_name).?;
    if (pkg.depends) |dependencies| {
        for (dependencies) |dep_str| {
            const satisfier = (try self.findPackageFor(dep_str)) orelse continue;
            if (pkg_set.contains(satisfier.name)) {
                try self.topologicalSort(
                    pkg_set,
                    sorted_list,
                    visiting,
                    finished,
                    satisfier.name,
                );
            }
        }
    }

    _ = visiting.remove(pkg_name);
    try finished.insert(pkg_name);
    try sorted_list.append(gpa, pkg_name);
}

/// Public API: Resolve and sort dependencies for a target package.
pub fn resolveDependencies(self: *const SyncDbs, targets: []const []const u8) ResolveError![]const []const u8 {
    const gpa = self.repos.allocator;

    // =========================================================================
    // Phase 0: Target Expansion (Packages and Groups)
    // =========================================================================
    var expanded_targets_set = std.BufSet.init(gpa);
    defer expanded_targets_set.deinit();

    for (targets) |target_str| {
        var found_as_package = false;
        var repo_it = self.repos.valueIterator();
        while (repo_it.next()) |repo| {
            if (repo.db.pkg_map.contains(target_str)) {
                try expanded_targets_set.insert(target_str);
                found_as_package = true;
                break; // Found it as a package, no need to check other repos for this target
            }
        }

        if (found_as_package) {
            continue; // Move to the next target string from the user
        }

        // If we got here, it wasn't a package. Now check if it's a group.
        var found_as_group = false;
        repo_it = self.repos.valueIterator();
        while (repo_it.next()) |repo| {
            if (repo.db.group_map.get(target_str)) |group_members| {
                for (group_members.items) |member_pkg_name| {
                    try expanded_targets_set.insert(member_pkg_name);
                }
                found_as_group = true;
                break; // Found the group, no need to check other repos
            }
        }

        // If it was neither a package nor a group, the target is invalid.
        if (!found_as_group) {
            std.log.err("target not found: '{s}'", .{target_str});
            return error.TargetNotFound;
        }
    }

    // =========================================================================
    // Phase 1: Aggregation (Using the expanded list of packages)
    // =========================================================================
    var resolved_set: Repo.Desc.RefMap = .init(gpa);
    defer resolved_set.deinit();

    var target_it = expanded_targets_set.iterator();
    while (target_it.next()) |target| {
        // Resolve this target into the shared set.
        try self.resolve(target.*, &resolved_set);
    }

    // Phase 2: Topological Sort
    var sorted_list: std.ArrayList([]const u8) = .{};
    defer sorted_list.deinit(gpa);
    var visiting = std.BufSet.init(gpa);
    defer visiting.deinit();
    var finished = std.BufSet.init(gpa);
    defer finished.deinit();

    var it = resolved_set.keyIterator();
    while (it.next()) |pkg_name| {
        try self.topologicalSort(
            &resolved_set,
            &sorted_list,
            &visiting,
            &finished,
            pkg_name.*,
        );
    }

    return try sorted_list.toOwnedSlice(gpa);
}

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Repo = @import("Repo.zig");
const testing = std.testing;
const AlpmVersion = @import("AlpmVersion.zig");
const SyncDbs = @This();

test {
    _ = Repo;

    var tmpdir = testing.tmpDir(.{});
    defer tmpdir.cleanup();

    const cachedir = try tmpdir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(cachedir);

    var sync_dbs = try init(testing.allocator, cachedir);
    defer sync_dbs.deinit();

    try sync_dbs.register(.{
        .name = "core",
        .url = "http://mirrors.ustc.edu.cn/archlinux/core/os/x86_64",
    });

    try sync_dbs.register(.{
        .name = "extra",
        .url = "http://mirrors.ustc.edu.cn/archlinux/extra/os/x86_64",
    });

    try sync_dbs.update();

    const pkgs = try sync_dbs.resolveDependencies(&.{ "base", "gnome" });
    defer testing.allocator.free(pkgs);
}
