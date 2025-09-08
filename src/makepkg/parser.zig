pub fn DescParser(comptime T: type) type {
    return struct {
        const Section = std.meta.FieldEnum(T);
        const max_section_name = blk: {
            var max: usize = 0;
            for (std.meta.fieldNames(T)) |name| {
                max = @max(name.len, max);
            }
            break :blk max;
        };

        pub fn parse(arena: mem.Allocator, r: *std.Io.Reader) !T {
            var desc: T = .{};
            var section_buf: [max_section_name]u8 = undefined;
            var section_writer: std.Io.Writer = .fixed(&section_buf);
            while (try getSection(r)) |section_str| {
                if (section_str.len == 0) continue;
                _ = section_writer.consumeAll();
                for (section_str) |c| {
                    try section_writer.writeByte(std.ascii.toLower(c));
                }
                section_writer.flush() catch unreachable;
                if (std.meta.stringToEnum(Section, section_writer.buffered())) |section| {
                    try parseSection(&desc, arena, r, section);
                } else {
                    std.log.err("unknown section: {s}", .{section_writer.buffered()});
                    return error.UnknownSection;
                }
            }
            return desc;
        }

        fn parseSection(self: *T, arena: mem.Allocator, r: *std.Io.Reader, section: Section) !void {
            outer: while (try nextLine(r)) |val_str| {
                if (val_str.len == 0) continue;
                switch (section) {
                    inline else => |tag| {
                        const field_name = @tagName(tag);
                        const val = @field(self, field_name);
                        switch (@typeInfo(@TypeOf(val))) {
                            .int => {
                                const int = try std.fmt.parseInt(@TypeOf(val), val_str, 10);
                                @field(self, field_name) = int;
                                break :outer;
                            },
                            .@"enum" => {
                                const val_enum = std.meta.stringToEnum(@TypeOf(val), val_str) orelse
                                    return error.UnknownEnumValue;
                                @field(self, field_name) = val_enum;
                                break :outer;
                            },
                            .pointer => |pointer| {
                                // Try to parse as a string
                                const item: ?type = switch (@typeInfo(pointer.child)) {
                                    .array => |array| array.child,
                                    else => if (pointer.size == .slice) pointer.child else null,
                                };
                                if (item == u8 and (pointer.sentinel() == null or pointer.sentinel() == 0)) {
                                    @field(self, field_name) = try arena.dupeZ(u8, val_str);
                                    break :outer;
                                }
                                comptime unreachable;
                            },
                            .optional => |o| {
                                switch (@typeInfo(o.child)) {
                                    .pointer => |pointer| {
                                        // Try to parse as a string
                                        const item: ?type = switch (@typeInfo(pointer.child)) {
                                            .array => |array| array.child,
                                            else => if (pointer.size == .slice) pointer.child else null,
                                        };
                                        if (item == u8 and (pointer.sentinel() == null or pointer.sentinel() == 0)) {
                                            @field(self, field_name) = try arena.dupeZ(u8, val_str);
                                            break :outer;
                                        }

                                        switch (pointer.size) {
                                            .slice => {
                                                var vals: std.ArrayList(pointer.child) = try .initCapacity(arena, 1);
                                                defer vals.deinit(arena);
                                                vals.appendAssumeCapacity(try arena.dupeZ(u8, val_str));
                                                inner: while (try nextLine(r)) |item_str| {
                                                    if (item_str.len == 0) continue :inner;
                                                    try vals.append(arena, try arena.dupeZ(u8, item_str));
                                                }
                                                @field(self, field_name) = try vals.toOwnedSlice(arena);
                                                break :outer;
                                            },
                                            else => comptime unreachable,
                                        }
                                    },
                                    else => comptime unreachable,
                                }
                            },
                            else => comptime unreachable,
                        }
                    },
                }
            }
        }

        fn nextLine(r: *std.Io.Reader) !?[]const u8 {
            const prefix = r.peekByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => |e| return e,
            };
            if (prefix == '%') return null;
            const line = try r.takeDelimiterExclusive('\n');
            const line_trimmed = std.mem.trimRight(u8, line, " \t");
            return line_trimmed;
        }

        fn getSection(r: *std.Io.Reader) !?[]const u8 {
            const line = r.takeDelimiterExclusive('\n') catch |err| switch (err) {
                error.EndOfStream => return null,
                else => |e| return e,
            };

            const line_trimmed = std.mem.trimRight(u8, line, " \t");
            if (line_trimmed.len > 2 and line_trimmed[0] == '%' and line_trimmed[line_trimmed.len - 1] == '%') {
                return line_trimmed[1 .. line_trimmed.len - 1];
            } else {
                return &.{};
            }
        }
    };
}

const std = @import("std");
const tar = std.tar;
const mem = std.mem;
const testing = std.testing;
const common = @import("common.zig");
