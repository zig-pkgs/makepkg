pub fn Formatter(comptime T: type, comptime kind: Kind) type {
    return struct {
        value: T,
        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            var s: Serializer(kind) = .{
                .writer = writer,
            };
            inline for (comptime std.meta.fields(@TypeOf(self.value))) |field| {
                const val = @field(self.value, field.name);
                switch (@typeInfo(field.type)) {
                    .int => try s.int(field.name, val, true),
                    .pointer => |pointer| {
                        // Try to serialize as a string
                        const item: ?type = switch (@typeInfo(pointer.child)) {
                            .array => |array| array.child,
                            else => if (pointer.size == .slice) pointer.child else null,
                        };
                        if (item == u8 and
                            (pointer.sentinel() == null or pointer.sentinel() == 0))
                        {
                            try s.string(field.name, val, true);
                            continue;
                        }

                        // Serialize as either a tuple or as the child type
                        switch (pointer.size) {
                            .slice => try s.tupleArbitraryDepth(field.name, val, true),
                            .one => try s.valueArbitraryDepth(field.name, val.*, true),
                            else => comptime unreachable,
                        }
                    },
                    .@"enum" => try s.enumFmt(field.name, val, true),
                    .optional => if (val) |inner| {
                        try s.valueArbitraryDepth(field.name, inner, true);
                    },
                    else => comptime unreachable,
                }
            }
            try s.writer.flush();
        }
    };
}

pub const Kind = enum {
    info,
    desc,
};

pub fn Serializer(comptime kind: Kind) type {
    return struct {
        writer: *std.Io.Writer,

        pub fn int(self: *@This(), name: []const u8, val: anytype, root: bool) std.Io.Writer.Error!void {
            if (kind == .desc and root) try self.writeSection(name);
            switch (kind) {
                .info => try self.writer.print("{s} = {d}\n", .{ name, val }),
                .desc => try self.writer.print("{d}\n", .{val}),
            }
        }

        pub fn enumFmt(self: *@This(), name: []const u8, val: anytype, root: bool) std.Io.Writer.Error!void {
            if (kind == .desc and root) try self.writeSection(name);
            switch (kind) {
                .info => try self.writer.print("{s} = {s}\n", .{ name, @tagName(val) }),
                .desc => try self.writer.print("{s}\n", .{@tagName(val)}),
            }
        }

        pub fn string(self: *@This(), name: []const u8, val: anytype, root: bool) std.Io.Writer.Error!void {
            if (kind == .desc and root) try self.writeSection(name);
            switch (kind) {
                .info => try self.writer.print("{s} = {f}\n", .{ name, std.zig.fmtString(val) }),
                .desc => try self.writer.print("{f}\n", .{std.zig.fmtString(val)}),
            }
        }

        pub fn valueArbitraryDepth(self: *@This(), name: []const u8, val: anytype, root: bool) std.Io.Writer.Error!void {
            if (kind == .desc and root) try self.writeSection(name);
            switch (@typeInfo(@TypeOf(val))) {
                .int => try self.int(name, val),
                .pointer => |pointer| {
                    // Try to serialize as a string
                    const item: ?type = switch (@typeInfo(pointer.child)) {
                        .array => |array| array.child,
                        else => if (pointer.size == .slice) pointer.child else null,
                    };
                    if (item == u8 and
                        (pointer.sentinel() == null or pointer.sentinel() == 0))
                    {
                        return try self.string(name, val, false);
                    }

                    // Serialize as either a tuple or as the child type
                    switch (pointer.size) {
                        .slice => try self.tupleArbitraryDepth(name, val, false),
                        .one => try self.valueArbitraryDepth(name, val.*, false),
                        else => comptime unreachable,
                    }
                },
                .@"union" => try self.printUnion(name, val),
                .@"enum" => try self.enumFmt(name, val, false),
                else => comptime unreachable,
            }
        }

        pub fn printUnion(self: *@This(), name: []const u8, val: anytype) std.Io.Writer.Error!void {
            comptime assert(kind != .desc);
            switch (val) {
                inline else => |inner, tag| {
                    switch (@typeInfo(@TypeOf(inner))) {
                        .bool => {
                            try self.writer.print("{s} ={s}{s}\n", .{
                                name,
                                if (inner) " " else " !",
                                @tagName(tag),
                            });
                        },
                        .@"enum" => {
                            try self.writer.print("{s} = {s}={s}\n", .{
                                name,
                                @tagName(tag),
                                @tagName(inner),
                            });
                        },
                        else => comptime unreachable,
                    }
                },
            }
        }

        pub fn tupleArbitraryDepth(self: *@This(), name: []const u8, val: anytype, root: bool) std.Io.Writer.Error!void {
            if (kind == .desc and root) try self.writeSection(name);
            switch (@typeInfo(@TypeOf(val))) {
                .pointer, .array => {
                    for (val) |item_val| {
                        try self.valueArbitraryDepth(name, item_val, false);
                    }
                },
                else => comptime unreachable,
            }
        }

        pub fn writeSection(self: *@This(), name: []const u8) std.Io.Writer.Error!void {
            try self.writer.writeByte('%');
            for (name) |c| {
                try self.writer.writeByte(std.ascii.toUpper(c));
            }
            try self.writer.print("%\n", .{});
        }
    };
}

const std = @import("std");
const assert = std.debug.assert;
