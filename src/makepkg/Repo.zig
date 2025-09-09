pub const Db = @import("Repo/Db.zig");
pub const Desc = @import("Repo/Desc.zig");

name: []const u8,
url: []const u8,
db: Db,

pub const Options = struct {
    name: []const u8,
    url: []const u8,
};

pub fn init(gpa: mem.Allocator, options: Options) !Repo {
    return .{
        .name = try std.fmt.allocPrint(gpa, "{s}.db.tar.gz", .{options.name}),
        .url = if (mem.endsWith(u8, options.url, "/"))
            try gpa.dupe(u8, options.url)
        else
            try std.fmt.allocPrint(gpa, "{s}/", .{options.url}),
        .db = undefined,
    };
}

pub fn deinit(self: *Repo, gpa: mem.Allocator) void {
    self.db.deinit();
    gpa.free(self.name);
    gpa.free(self.url);
}

const std = @import("std");
const mem = std.mem;
const Repo = @This();

test {
    _ = Desc;
    _ = Db;
}
