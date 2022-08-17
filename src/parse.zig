const std = @import("std");

pub fn Cursor(SourceCharacter: type, Event: type) type {
    return struct {
        source: []const SourceCharacter,
        events: *std.MultiArrayList(Event),
        source_index: SourceIndex,
        events_index: EventIndex,

        pub const EventIndex = struct {
            index: u32,
        };

        pub const SourceIndex = struct {
            index: u32,
        };

        pub fn copy(this: @This()) @This() {
            return @This(){
                .source = this.source,
                .events = this.events,
                .source_index = this.source_index,
                .events_index = this.events_index,
            };
        }

        /// Sets this cursor to equal the other cursors index and out
        pub fn commit(this: *@This(), other: @This()) void {
            this.source_index = other.source_index;
            this.events_index = other.events_index;
        }

        pub fn append(this: *@This(), allocator: std.mem.Allocator, event: Event) !EventIndex {
            const index = this.events_index;
            this.events_index.index += 1;

            try this.events.resize(allocator, index.index + 1);

            this.events.set(index.index, event);
            return index;
        }

        pub fn slice(this: *@This(), low: SourceIndex, high: SourceIndex) []const SourceCharacter {
            return this.source[low.index..high.index];
        }
    };
}

pub fn next(T: type, source: []const T, index: *usize) ?T {
    if (index.* < source.len) {
        const t = source[index.*];
        index.* += 1;
        return t;
    } else {
        return null;
    }
}

pub fn IndexedSlice(T: type) type {
    return struct {
        source: []const T,
        start: usize,
        end: usize,
    };
}

pub fn expect(T: type, source: []const T, index: *usize, expected: T) ?IndexedSlice(T) {
    const start = index.*;
    if (next(T, source, index) == expected) {
        index.* += 1;
        return IndexedSlice(T){
            .source = source,
            .start = start,
            .end = index.*,
        };
    }
    return null;
}

pub fn expectInRange(T: type, source: []const T, index: *usize, low: T, high: T) ?IndexedSlice(T) {
    const start = index.*;
    const t = next(T, source, index) orelse return null;
    if (low <= t and t <= high) {
        index.* += 1;
        return IndexedSlice(T){
            .source = source,
            .start = start,
            .end = index.*,
        };
    }
    return null;
}

pub fn expectInList(T: type, source: []const T, index: *usize, list: []const T) ?IndexedSlice(T) {
    const start = index.*;
    const t = next(T, source, index) orelse return null;
    if (std.mem.indexOfScalar(u8, list, t)) |_| {
        index.* += 1;
        return IndexedSlice(T){
            .source = source,
            .start = start,
            .end = index.*,
        };
    }
    return null;
}

pub fn expectString(T: type, source: []const T, parent_index: *usize, string: []const T) ?IndexedSlice(T) {
    const start = parent_index.*;
    var index = parent_index.*;

    for (string) |t| {
        expect(source, &index, t) orelse return null;
    }

    parent_index.* = index;
    return IndexedSlice(T){
        .source = source,
        .start = start,
        .end = index,
    };
}
