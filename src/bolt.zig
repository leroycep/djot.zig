const std = @import("std");

pub fn Read(comptime T: type, comptime Index: type) type {
    return struct {
        source: []const T,
        index: Index,

        pub fn next(this: *@This()) ?T {
            return raw.next(T, Index, this.source, &this.index);
        }

        pub fn expect(this: *@This(), expected: T) ?Index {
            return raw.expect(T, Index, this.source, &this.index, expected);
        }

        pub fn expectInRange(this: *@This(), low: T, high: T) ?Index {
            return raw.expectInRange(T, Index, this.source, &this.index, low, high);
        }

        pub fn expectInList(this: *@This(), list: []const T) ?Index {
            return raw.expectInList(T, Index, this.source, &this.index, list);
        }

        pub fn expectString(this: *@This(), string: []const T) ?[2]Index {
            return raw.expectString(T, Index, this.source, &this.index, string);
        }
    };
}

pub const raw = struct {
    pub fn next(comptime T: type, comptime I: type, source: []const T, index: *I) ?T {
        if (index.* < source.len) {
            const t = source[index.*];
            index.* += 1;
            return t;
        } else {
            return null;
        }
    }

    pub fn expect(comptime T: type, comptime I: type, source: []const T, parent: *I, expected: T) ?I {
        const start = parent.*;
        var index = start;
        if (next(T, I, source, &index) == expected) {
            parent.* = index;
            return start;
        }
        return null;
    }

    pub fn expectInRange(comptime T: type, comptime I: type, source: []const T, parent: *I, low: T, high: T) ?I {
        const start = parent.*;
        var index = start;
        const t = next(T, I, source, &index) orelse return null;
        if (low <= t and t <= high) {
            parent.* = index;
            return start;
        }
        return null;
    }

    pub fn expectInList(comptime T: type, comptime I: type, source: []const T, parent: *I, list: []const T) ?I {
        const start = parent.*;
        var index = start;
        const t = next(T, I, source, &index) orelse return null;
        if (std.mem.indexOfScalar(T, list, t)) |_| {
            parent.* = index;
            return start;
        }
        return null;
    }

    pub fn expectString(comptime T: type, comptime I: type, source: []const T, parent_index: *I, string: []const T) ?[2]I {
        const start = parent_index.*;
        var index = parent_index.*;

        for (string) |t| {
            _ = expect(T, I, source, &index, t) orelse return null;
        }

        parent_index.* = index;
        return [2]I{ start, index };
    }
};
