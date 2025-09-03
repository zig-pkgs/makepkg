pub fn Formatter(comptime T: type) type {
    return struct {
        value: T,
        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            var s: Serializer = .{
                .writer = writer,
            };
            inline for (comptime std.meta.fields(@TypeOf(self.value))) |field| {
                const val = @field(self.value, field.name);
                switch (@typeInfo(field.type)) {
                    .int => try s.int(field.name, val),
                    .pointer => |pointer| {
                        // Try to serialize as a string
                        const item: ?type = switch (@typeInfo(pointer.child)) {
                            .array => |array| array.child,
                            else => if (pointer.size == .slice) pointer.child else null,
                        };
                        if (item == u8 and
                            (pointer.sentinel() == null or pointer.sentinel() == 0))
                        {
                            try s.string(field.name, val);
                            continue;
                        }

                        // Serialize as either a tuple or as the child type
                        switch (pointer.size) {
                            .slice => try s.tupleArbitraryDepth(field.name, val),
                            .one => try s.valueArbitraryDepth(field.name, val.*),
                            else => comptime unreachable,
                        }
                    },
                    .enum_literal,
                    .@"enum",
                    => try s.writer.print("{s} = {s}\n", .{ field.name, @tagName(val) }),
                    .optional => if (val) |inner| {
                        try s.valueArbitraryDepth(field.name, inner);
                    },
                    else => comptime unreachable,
                }
            }
            try s.writer.flush();
        }
    };
}

pub const Serializer = struct {
    writer: *std.Io.Writer,

    pub fn int(self: *Serializer, name: []const u8, val: anytype) std.Io.Writer.Error!void {
        try self.writer.print("{s} = {d}\n", .{ name, val });
    }

    pub fn string(self: *Serializer, name: []const u8, val: anytype) std.Io.Writer.Error!void {
        try self.writer.print("{s} = {f}\n", .{ name, std.zig.fmtString(val) });
    }

    pub fn valueArbitraryDepth(self: *Serializer, name: []const u8, val: anytype) std.Io.Writer.Error!void {
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
                    return try self.string(name, val);
                }

                // Serialize as either a tuple or as the child type
                switch (pointer.size) {
                    .slice => try self.tupleArbitraryDepth(name, val),
                    .one => try self.valueArbitraryDepth(name, val.*),
                    else => comptime unreachable,
                }
            },
            .@"union" => try self.printUnion(name, val),
            .enum_literal,
            .@"enum",
            => try self.writer.print("{s} = {s}\n", .{ name, @tagName(val) }),
            else => comptime unreachable,
        }
    }

    pub fn printUnion(self: *Serializer, name: []const u8, val: anytype) std.Io.Writer.Error!void {
        assert(@typeInfo(@TypeOf(val)) == .@"union");
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

    pub fn tupleArbitraryDepth(self: *Serializer, name: []const u8, val: anytype) std.Io.Writer.Error!void {
        switch (@typeInfo(@TypeOf(val))) {
            .pointer, .array => {
                for (val) |item_val| {
                    try self.valueArbitraryDepth(name, item_val);
                }
            },
            else => comptime unreachable,
        }
    }
};

const std = @import("std");
const assert = std.debug.assert;
