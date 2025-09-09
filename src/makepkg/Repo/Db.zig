pkg_map: Desc.Map,
group_map: std.StringHashMap(std.ArrayList([:0]const u8)),
provide_map: std.StringHashMap([:0]const u8),
arena: *std.heap.ArenaAllocator,

pub fn parse(gpa: mem.Allocator, reader: *std.Io.Reader) !Db {
    const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
    errdefer gpa.destroy(arena_ptr);
    arena_ptr.* = .init(gpa);

    const arena = arena_ptr.allocator();

    var pkg_map: Desc.Map = .init(gpa);
    errdefer pkg_map.deinit();

    var group_map: std.StringHashMap(std.ArrayList([:0]const u8)) = .init(gpa);
    errdefer group_map.deinit();

    var provide_map: std.StringHashMap([:0]const u8) = .init(gpa);
    errdefer provide_map.deinit();

    var flate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(reader, .gzip, &flate_buffer);

    var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var it: tar.Iterator = .init(&decompress.reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
        .diagnostics = null,
    });

    while (try it.next()) |file| {
        switch (file.kind) {
            .file => {
                var allocating: std.Io.Writer.Allocating = .init(gpa);
                defer allocating.deinit();
                try it.streamRemaining(file, &allocating.writer);
                var line_reader: std.Io.Reader = .fixed(allocating.written());
                const desc = try Desc.Parser.parse(arena, &line_reader);
                try allocating.writer.flush();
                if (desc.groups) |groups| {
                    for (groups) |group| {
                        if (group_map.getPtr(group)) |list| {
                            try list.append(arena, desc.name);
                        } else {
                            var list: std.ArrayList([:0]const u8) = try .initCapacity(arena, 1);
                            list.appendAssumeCapacity(desc.name);
                            try group_map.put(group, list);
                        }
                    }
                }
                if (desc.provides) |provides| {
                    for (provides) |provide| {
                        try provide_map.put(provide, desc.name);
                    }
                }
                try pkg_map.put(desc.name, desc);
            },
            else => {},
        }
    }

    return .{
        .arena = arena_ptr,
        .pkg_map = pkg_map,
        .provide_map = provide_map,
        .group_map = group_map,
    };
}

pub fn deinit(self: *Db) void {
    const allocator = self.arena.child_allocator;
    self.pkg_map.deinit();
    self.group_map.deinit();
    self.provide_map.deinit();
    self.arena.deinit();
    allocator.destroy(self.arena);
}

// parseNameFromDepString and findPackageFor from your version are perfect.
// Let's keep them as they are.
fn parseNameFromDepString(dep: []const u8) []const u8 {
    var it = mem.splitAny(u8, dep, ">=<");
    return it.first();
}

fn findPackageFor(self: *const Db, dep_string: []const u8) ?*const Desc {
    if (self.provide_map.get(dep_string)) |concrete_name| {
        return self.pkg_map.getPtr(concrete_name);
    }
    const base_name = parseNameFromDepString(dep_string);
    if (self.pkg_map.getPtr(base_name)) |pkg| {
        return pkg;
    }
    if (self.provide_map.get(base_name)) |concrete_name| {
        return self.pkg_map.getPtr(concrete_name);
    }
    return null;
}

/// Robustly and recursively resolves dependencies using two sets to
/// prevent cycles and produce a topologically sorted list.
fn resolveRecursive(
    self: *const Db,
    gpa: mem.Allocator,
    dep_string: []const u8,
    resolved_list: *std.ArrayList([]const u8),
    visiting_set: *std.BufSet, // Tracks nodes in the current recursion path.
    finished_set: *std.BufSet, // Tracks nodes that are completely resolved.
) !void {
    // Step 1: Find the package that provides this dependency.
    const pkg = self.findPackageFor(dep_string) orelse {
        // Not found in our database, might be an AUR package or already installed.
        // We stop here for this dependency branch.
        std.debug.print("unresolved dep_string={s}\n", .{dep_string});
        return;
    };

    // Step 2: If this package has already been fully resolved, we're done.
    if (finished_set.contains(pkg.name)) {
        return;
    }

    // Step 3: **Cycle Detection**. If we encounter this package while already
    // in the process of visiting it, we have found a circular dependency.
    if (visiting_set.contains(pkg.name)) {
        // In a real application, you might want to return an error here.
        // For now, we'll just stop to prevent the stack overflow.
        // return error.CircularDependency;
        return;
    }

    // Step 4: Mark this package as "currently visiting".
    try visiting_set.insert(pkg.name);

    // Step 5: Recurse on all of its dependencies.
    if (pkg.depends) |dependencies| {
        for (dependencies) |dep| {
            try self.resolveRecursive(gpa, dep, resolved_list, visiting_set, finished_set);
        }
    }

    // Step 6: Now that we have visited all children, we can remove this package
    // from the "currently visiting" set...
    _ = visiting_set.remove(pkg.name);

    // ...and add it to the "fully finished" set.
    try finished_set.insert(pkg.name);

    // Step 7: Finally, add the package to our resolved list. Because this happens
    // *after* the recursion, dependencies will always appear before the packages
    // that need them. This is the topological sort.
    try resolved_list.append(gpa, pkg.name);
}

/// Resolves all dependencies for a given package or package group.
/// Returns an owned slice of package names in a topologically sorted order
/// suitable for installation.
pub fn resolveDependencies(self: *const Db, gpa: mem.Allocator, target: []const u8) ![]const []const u8 {
    var resolved_list: std.ArrayList([]const u8) = .{};
    errdefer resolved_list.deinit(gpa);

    // Set for tracking nodes in the current recursion path to detect cycles.
    var visiting_set = std.BufSet.init(gpa);
    defer visiting_set.deinit();

    // Set for tracking nodes that have been fully resolved to avoid re-processing.
    var finished_set = std.BufSet.init(gpa);
    defer finished_set.deinit();

    // Main logic to handle either a group or a single package.
    if (self.group_map.get(target)) |group_pkgs| {
        for (group_pkgs.items) |pkg_in_group| {
            try self.resolveRecursive(gpa, pkg_in_group, &resolved_list, &visiting_set, &finished_set);
        }
    } else {
        try self.resolveRecursive(gpa, target, &resolved_list, &visiting_set, &finished_set);
    }

    return resolved_list.toOwnedSlice(gpa);
}

const std = @import("std");
const tar = std.tar;
const mem = std.mem;
const testing = std.testing;
const common = @import("../common.zig");
const Desc = @import("Desc.zig");
const Db = @This();

test "db parsing" {
    const db_file = @embedFile("Db/core.db.tar.gz");
    const expected = @embedFile("Desc/desc.zon");

    var db_file_reader: std.Io.Reader = .fixed(db_file);

    var db = try parse(testing.allocator, &db_file_reader);
    defer db.deinit();

    const shadow = db.pkg_map.get("shadow");
    try testing.expect(shadow != null);

    var allocating: std.Io.Writer.Allocating = .init(testing.allocator);
    defer allocating.deinit();
    try std.zon.stringify.serialize(shadow.?, .{}, &allocating.writer);
    try allocating.writer.writeByte('\n');
    try allocating.writer.flush();

    try testing.expectEqualStrings(expected, allocating.written());

    const pkg_list = try db.resolveDependencies(testing.allocator, "base");
    defer testing.allocator.free(pkg_list);
    for (pkg_list) |pkg| {
        std.debug.print("{s}\n", .{pkg});
    }
}

test "db group" {
    const db_file = @embedFile("Db/extra.db.tar.gz");

    var db_file_reader: std.Io.Reader = .fixed(db_file);

    var db = try parse(testing.allocator, &db_file_reader);
    defer db.deinit();

    const gnome = db.group_map.get("gnome").?;
    for (gnome.items) |pkg| {
        try testing.expect(pkg.len > 0);
    }
}
