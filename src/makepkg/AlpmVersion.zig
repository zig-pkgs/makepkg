epoch: u64 = 0,
pkgver: []const u8 = &.{},
pkgrel: ?u64 = null, // Default pkgrel is 1 if not specified.

// Parses a full version string (e.g., "2:1.2.3-4") into its components.
pub fn parse(version_str: []const u8) !AlpmVersion {
    var result: AlpmVersion = .{};
    var rest = version_str;

    // 1. Parse the epoch
    if (mem.indexOfScalar(u8, rest, ':')) |colon_idx| {
        result.epoch = try std.fmt.parseInt(u64, rest[0..colon_idx], 10);
        rest = rest[colon_idx + 1 ..];
    }

    // 2. Parse the pkgrel from the end of the string
    if (mem.lastIndexOfScalar(u8, rest, '-')) |dash_idx| {
        // Ensure the dash is not part of a negative number in pkgver
        if (mem.indexOfAny(u8, rest[dash_idx + 1 ..], ".-") == null) {
            result.pkgrel = try std.fmt.parseInt(u64, rest[dash_idx + 1 ..], 10);
            result.pkgver = rest[0..dash_idx];
            return result;
        }
    }

    // If we reach here, there was no valid pkgrel.
    result.pkgver = rest;
    return result;
}

/// A faithful Zig implementation of the RPM version comparison algorithm.
/// This correctly compares version strings segment by segment.
fn rpmVerCmp(a: []const u8, b: []const u8) std.math.Order {
    if (mem.eql(u8, a, b)) return .eq;

    var cur_a: usize = 0;
    var cur_b: usize = 0;

    while (cur_a < a.len and cur_b < b.len) {
        // Skip all non-alphanumeric characters
        while (cur_a < a.len and !std.ascii.isAlphanumeric(a[cur_a])) cur_a += 1;
        while (cur_b < b.len and !std.ascii.isAlphanumeric(b[cur_b])) cur_b += 1;

        if (cur_a >= a.len or cur_b >= b.len) break;

        const start_a = cur_a;
        const start_b = cur_b;

        const is_num = std.ascii.isDigit(a[start_a]);
        // The C code has a bug where it doesn't check if b is also a digit.
        // If they differ in type, numeric is always greater.
        if (is_num != std.ascii.isDigit(b[start_b])) {
            return if (is_num) .gt else .lt;
        }

        if (is_num) {
            while (cur_a < a.len and std.ascii.isDigit(a[cur_a])) cur_a += 1;
            while (cur_b < b.len and std.ascii.isDigit(b[cur_b])) cur_b += 1;
        } else {
            while (cur_a < a.len and std.ascii.isAlphabetic(a[cur_a])) cur_a += 1;
            while (cur_b < b.len and std.ascii.isAlphabetic(b[cur_b])) cur_b += 1;
        }

        var seg_a = a[start_a..cur_a];
        var seg_b = b[start_b..cur_b];

        if (is_num) {
            // Trim leading zeros for numeric comparison
            seg_a = mem.trimStart(u8, seg_a, "0");
            seg_b = mem.trimStart(u8, seg_b, "0");

            // Whichever number has more digits wins
            if (seg_a.len != seg_b.len) {
                return std.math.order(seg_a.len, seg_b.len);
            }
        }

        // Compare segments. This works for both alpha and numeric of same length.
        const cmp = mem.order(u8, seg_a, seg_b);
        if (cmp != .eq) return cmp;
    }

    // If one string has remaining segments, it is considered newer.
    if (cur_a < a.len) return .gt;
    if (cur_b < b.len) return .lt;

    return .eq;
}

/// Compares two full AlpmVersion structs using the rpmVerCmp logic.
/// This is the Zig equivalent of `alpm_pkg_vercmp`.
pub fn order(a: AlpmVersion, b: AlpmVersion) std.math.Order {
    // 1. Compare epochs first
    if (a.epoch != b.epoch) {
        return std.math.order(a.epoch, b.epoch);
    }

    // 2. Compare pkgver strings using the correct algorithm
    const ver_cmp = rpmVerCmp(a.pkgver, b.pkgver);
    if (ver_cmp != .eq) {
        return ver_cmp;
    }

    if (a.pkgrel != null and b.pkgrel != null) {
        // 3. Compare pkgrel if both exist
        return std.math.order(a.pkgrel.?, b.pkgrel.?);
    }
    return ver_cmp;
}

const std = @import("std");
const mem = std.mem;
const AlpmVersion = @This();
