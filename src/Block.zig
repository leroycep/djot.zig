const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");
const djot = @import("./djot.zig");
const parselib = @import("./parse.zig");

const Cursor = djot.Cursor;
const EventIndex = Cursor.EventIndex;
const Event = djot.Event;
const Error = djot.Error;

const Prefix = struct {
    prev: ?*const Prefix = null,
    token: Token.Kind,

    pub fn parsePrefix(this: @This(), parent: *Cursor) ?void {
        var cursor = parent.copy();
        if (this.prev) |prev| prev.parsePrefix(&cursor) orelse return null;
        _ = parseExpectToken(&cursor, this.token) orelse return null;
        parent.commit(cursor);
        return;
    }

    pub fn parsePrefixVisible(this: @This(), parent: *Cursor) ?void {
        var cursor = parent.copy();
        if (this.prev) |prev| prev.parsePrefix(&cursor) orelse return null;
        if (this.token == .space) {
            _ = parseExpectToken(&cursor, this.token);
        } else {
            _ = parseExpectToken(&cursor, this.token) orelse return null;
        }
        parent.commit(cursor);
        return;
    }

    pub fn dump(this: @This()) void {
        if (this.prev) |prev| {
            prev.dump();
        }
    }
};

pub fn parseBlocks(allocator: std.mem.Allocator, parent: *Cursor, prefix: ?*const Prefix) Error!bool {
    var cursor = parent.copy();

    var prev_index = cursor.source_index;
    var was_break = false;

    while (true) {
        var loop_cursor = cursor.copy();

        var peek_cursor = loop_cursor.copy();
        while (parseExpectToken(&peek_cursor, .space)) |_| {}
        const token = parseToken(&peek_cursor) orelse break;

        switch (token.kind) {
            .heading => _ = try parseHeading(allocator, &loop_cursor),
            .marker => _ = try parseList(allocator, &loop_cursor, prefix),
            .quote => _ = try parseQuote(allocator, &loop_cursor, prefix),

            .text => {
                if (was_break) {
                    _ = try loop_cursor.append(allocator, .{
                        .kind = .text_break,
                        .source = .{
                            .slice = cursor.source[0..0],
                        },
                    });
                    was_break = false;
                }
                _ = try parseText(allocator, &loop_cursor);
            },

            .newline => {},
            .space => {},
        }

        cursor.commit(loop_cursor);

        was_break = parseNewlinePrefix(&cursor, prefix) orelse break;

        if (cursor.source_index.index == prev_index.index) {
            std.debug.print("token({}) = {s} \"{}\"\n", .{ token.start.index, std.meta.tagName(token.kind), std.zig.fmtEscapes(cursor.source[token.start.index..token.end.index]) });
            return error.WouldLoop;
        }
        prev_index = cursor.source_index;
    }

    const was_content = cursor.events_index.index > parent.events_index.index;

    parent.commit(cursor);
    return was_content;
}

// Move past the prefix and any empty lines
pub fn parseNewlinePrefix(parent: *Cursor, prefix: ?*const Prefix) ?bool {
    var cursor = parent.copy();
    var was_empty_lines = false;

    // Parse empty lines
    while (true) {
        var loop_cursor = cursor.copy();
        if (prefix) |p| {
            p.parsePrefixVisible(&loop_cursor) orelse break;
        }
        while (parseExpectToken(&loop_cursor, .space)) |_| {}
        _ = parseExpectToken(&loop_cursor, .newline) orelse break;
        was_empty_lines = true;
        cursor.commit(loop_cursor);
    }

    if (prefix) |p| {
        p.parsePrefix(&cursor) orelse return null;
    }

    parent.commit(cursor);
    return was_empty_lines;
}

pub fn parseHeading(allocator: std.mem.Allocator, parent: *Cursor) Error!?void {
    var cursor = parent.copy();
    const token = parseExpectToken(&cursor, .heading) orelse return null;
    _ = parseExpectToken(&cursor, .space);

    _ = try cursor.append(allocator, .{
        .kind = .start_heading,
        .source = .{ .slice = cursor.slice(token.start, token.end) },
    });
    _ = try parseText(allocator, &cursor);
    _ = try cursor.append(allocator, .{
        .kind = .close_heading,
        .source = .{ .slice = cursor.slice(cursor.source_index, cursor.source_index) },
    });
    _ = parseExpectToken(&cursor, .newline);

    parent.commit(cursor);
}

pub fn parseQuote(allocator: std.mem.Allocator, parent: *Cursor, prefix: ?*const Prefix) Error!?void {
    var cursor = parent.copy();
    const quote_token = parseExpectToken(&cursor, .quote) orelse return null;
    _ = parseExpectToken(&cursor, .space) orelse return null;

    _ = try cursor.append(allocator, .{
        .kind = .start_quote,
        .source = .{ .slice = cursor.slice(quote_token.start, quote_token.end) },
    });
    _ = try parseBlocks(allocator, &cursor, &.{ .prev = &.{ .prev = prefix, .token = .quote }, .token = .space });
    _ = try cursor.append(allocator, .{
        .kind = .close_quote,
        .source = .{ .slice = cursor.slice(cursor.source_index, cursor.source_index) },
    });

    parent.commit(cursor);
}

pub fn parseList(allocator: std.mem.Allocator, parent: *Cursor, prefix: ?*const Prefix) Error!?void {
    var cursor = parent.copy();

    // Allocate a place for the start event; we'll have to update it once we know
    // whether it's a tight or loose list
    const start_event = try cursor.append(allocator, .{
        .kind = .start_list,
        .source = .{ .slice = cursor.slice(cursor.source_index, cursor.source_index) },
        .extra = Event.Extra{ .start_list = .{ .style = undefined } },
    });

    const first_list_item = (try parseListItem(allocator, &cursor, prefix)) orelse return null;

    var marker_index: usize = 0;
    const list_marker = Marker.parse(cursor.events.items(.source)[first_list_item.index].slice, &marker_index).?;

    var list_style = list_marker.style;
    var next_item_would_make_loose = false;
    var tight = true;

    if (parseExpectToken(&cursor, .newline)) |_| {
        next_item_would_make_loose = true;
    }

    while (true) {
        var loop_cursor = cursor.copy();
        const was_section_break = parseNewlinePrefix(&loop_cursor, prefix) orelse break;
        if (was_section_break) {
            tight = false;
        }

        const list_item = try parseListItem(allocator, &loop_cursor, prefix) orelse break;

        marker_index = 0;
        const item_marker = Marker.parse(loop_cursor.events.items(.source)[list_item.index].slice, &marker_index).?;
        const style = item_marker.style;

        if (style != list_style and list_style.isRoman() and style.isAlpha()) {
            if (style != list_style.romanToAlpha()) break;
            list_style = list_style.romanToAlpha();
        } else if (style != list_style and list_style.isAlpha() and style.isRoman()) {
            if (style.romanToAlpha() != list_style) break;
            // continue on
        } else if (style != list_style) {
            break;
        }

        if (next_item_would_make_loose) {
            tight = false;
        }

        cursor.commit(loop_cursor);

        if (parseExpectToken(&loop_cursor, .newline)) |_| {
            next_item_would_make_loose = true;
        }
    }

    cursor.events.items(.extra)[start_event.index] = Event.Extra{
        .start_list = .{
            .style = list_style,
        },
    };
    _ = try cursor.append(allocator, .{
        .kind = .close_list,
        .source = .{ .slice = cursor.slice(cursor.source_index, cursor.source_index) },
    });
    parent.commit(cursor);
    return;
}

fn parseListItem(allocator: std.mem.Allocator, parent: *Cursor, prefix: ?*const Prefix) Error!?EventIndex {
    var cursor = parent.copy();

    var marker_index: usize = cursor.source_index.index;
    const marker = Marker.parse(cursor.source, &marker_index) orelse return null;
    cursor.source_index.index = @intCast(u32, marker_index);

    _ = parseExpectToken(&cursor, .space) orelse return null;

    const event_index = try cursor.append(allocator, .{
        .kind = .start_list_item,
        .source = .{ .slice = cursor.source[marker.start..marker.end] },
    });

    if (!try parseBlocks(allocator, &cursor, &.{ .prev = prefix, .token = .space })) {
        return null;
    }

    _ = try cursor.append(allocator, .{ .kind = .close_list_item, .source = .{ .slice = cursor.source[0..0] } });
    parent.commit(cursor);
    return event_index;
}

pub fn parseText(allocator: std.mem.Allocator, parent: *Cursor) !?void {
    var blank = true;

    const start_index = parent.source_index;
    var end_index = start_index;

    var cursor = parent.copy();
    var last_was_newline = false;
    while (parseToken(&cursor)) |token| {
        switch (token.kind) {
            .heading,
            .marker,
            .quote,
            => break,

            .space => {},

            .newline => {
                if (last_was_newline) break;
                last_was_newline = true;
                end_index = token.end;
                parent.commit(cursor);
            },

            .text => {
                blank = false;
                last_was_newline = false;
                end_index = token.end;
                parent.commit(cursor);
            },
        }
    }

    if (blank) return null;

    _ = try parent.append(allocator, .{
        .kind = .text,
        .source = .{ .slice = parent.slice(start_index, end_index) },
    });

    return;
}

fn parseExpectToken(parent: *Cursor, expected_token_kind: Token.Kind) ?Token {
    var cursor = parent.copy();
    const token = parseToken(&cursor) orelse return null;
    if (token.kind == expected_token_kind) {
        parent.commit(cursor);
        return token;
    }
    return null;
}

pub const Token = struct {
    kind: Kind,
    start: Cursor.SourceIndex,
    end: Cursor.SourceIndex,

    pub const Kind = enum {
        newline,
        text,
        heading,
        marker,
        space,
        quote,
    };
};

pub fn parseToken(parent: *Cursor) ?Token {
    if (parent.source_index.index >= parent.source.len) return null;

    var marker_index: usize = parent.source_index.index;
    if (Marker.parse(parent.source, &marker_index)) |marker| blk: {
        const start = parent.source_index;
        // Only allow alpha numeric characters with a single character
        if (marker.style.isAlpha() and marker.end - start.index > 2) {
            break :blk;
        }
        return Token{
            .kind = .marker,
            .start = .{ .index = @intCast(u32, marker.start) },
            .end = .{ .index = @intCast(u32, marker.end) },
        };
    }

    const State = enum {
        default,
        text,
        heading,
        spaces,
    };

    var res = Token{
        .kind = .text,
        .start = parent.source_index,
        .end = parent.source_index,
    };

    var index: usize = parent.source_index.index;
    var state = State.default;
    while (parselib.next(u8, parent.source, &index)) |c| {
        switch (state) {
            .default => switch (c) {
                '#' => {
                    res.kind = .heading;
                    res.end.index = @intCast(u32, index);
                    state = .heading;
                },
                ' ' => {
                    res.kind = .space;
                    res.end.index = @intCast(u32, index);
                    break;
                },
                '\n' => {
                    res.kind = .newline;
                    res.end.index = @intCast(u32, index);
                    break;
                },
                '>' => {
                    res.kind = .quote;
                    res.end.index = @intCast(u32, index);
                    break;
                },
                else => {
                    res.kind = .text;
                    res.end.index = @intCast(u32, index);
                    state = .text;
                },
            },
            .heading => switch (c) {
                '#' => res.end.index = @intCast(u32, index),
                else => break,
            },
            .text => switch (c) {
                '\n' => break,
                else => res.end.index = @intCast(u32, index),
            },
            .spaces => switch (c) {
                ' ' => {
                    res.end.index = @intCast(u32, index);
                },
                else => break,
            },
        }
    }

    parent.source_index = res.end;

    return res;
}
