const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");

const Document = std.MultiArrayList(Event);

const Event = struct {
    kind: Kind,
    source: SourceIndex,

    const Kind = enum {
        text,
        start_heading,
        close_heading,

        start_quote,
        close_quote,

        /// Data is the text of the first marker
        start_tight_list,
        close_tight_list,

        /// Data is the text of the first marker
        start_loose_list,
        close_loose_list,

        start_list_item,
        close_list_item,
    };

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (this.kind) {
            .text,
            .start_heading,
            .start_list_item,
            => try writer.print("{s} \"{}\"", .{ std.meta.tagName(this.kind), std.zig.fmtEscapes(this.source.slice) }),

            // Events that are only tags just print the tag name
            .start_tight_list,
            .start_loose_list,
            .close_heading,
            .start_quote,
            .close_quote,
            .close_tight_list,
            .close_loose_list,
            .close_list_item,
            => try writer.print("{s}", .{std.meta.tagName(this.kind)}),
        }
    }
};

// TODO: Make this just a wrapper over a u32
const SourceIndex = struct {
    slice: []const u8,
};

pub fn parse(allocator: std.mem.Allocator, source: [*:0]const u8) !Document.Slice {
    var document = std.MultiArrayList(Event){};
    defer document.deinit(allocator);

    var cursor = Cursor{
        .source = source,
        .out_buffer = &document,
        .index = 0,
        .out_len = 0,
    };

    // for debugging
    var prev_index_opt: ?u32 = null;

    var loop_cursor = cursor.copy();
    while (parseToken(&loop_cursor)) |token| : (loop_cursor = cursor.copy()) {
        // TODO: Panic once everything is supposed to be implemented
        //std.debug.panic("This is a bug in djot.zig: all types of lines should be handled", .{});
        if (builtin.mode == .Debug) {
            if (prev_index_opt) |prev_index| {
                if (cursor.index == prev_index) {
                    return error.WouldLoop;
                }
            }
        }
        if (builtin.mode == .Debug) {
            prev_index_opt = cursor.index;
        }

        switch (token.kind) {
            .newline, .section_break, .spaces => cursor.commit(loop_cursor),

            .heading => _ = try parseHeading(allocator, &cursor),
            .marker => _ = try parseList(allocator, &cursor),
            .text => _ = try parseText(allocator, &cursor),
            .quote => _ = try parseQuote(allocator, &cursor),
        }
    }

    document.len = cursor.out_len;

    return document.toOwnedSlice();
}

pub fn parseHeading(allocator: std.mem.Allocator, parent: *Cursor) !?void {
    var cursor = parent.copy();
    const token = parseExpectToken(&cursor, .heading) orelse return null;

    try cursor.append(allocator, .{ .kind = .start_heading, .source = .{ .slice = cursor.source[token.start..token.end] } });
    _ = parseExpectToken(&cursor, .spaces);
    _ = try parseText(allocator, &cursor);
    _ = parseExpectToken(&cursor, .section_break);
    try cursor.append(allocator, .{ .kind = .close_heading, .source = .{ .slice = cursor.source[0..0] } });

    parent.commit(cursor);
}

pub fn parseQuote(allocator: std.mem.Allocator, parent: *Cursor) !?void {
    var cursor = parent.copy();
    const quote_token = parseExpectToken(&cursor, .quote) orelse return null;

    // Reset
    cursor = parent.copy();
    try cursor.append(allocator, .{ .kind = .start_quote, .source = .{ .slice = cursor.source[quote_token.start..quote_token.end] } });
    while (true) {
        _ = parseExpectToken(&cursor, .quote) orelse break;
        _ = parseExpectToken(&cursor, .spaces);
        _ = try parseText(allocator, &cursor);
        _ = parseExpectToken(&cursor, .newline);
        if (parseExpectToken(&cursor, .section_break)) |_| {
            break;
        }
    }
    try cursor.append(allocator, .{ .kind = .close_quote, .source = .{ .slice = cursor.source[cursor.index..cursor.index] } });

    parent.commit(cursor);
}

pub fn parseList(allocator: std.mem.Allocator, parent: *Cursor) !?void {
    var cursor = parent.copy();

    // Allocate a place for the start event; we'll have to update it once we know
    // whether it's a tight or loose list
    const start_event_idx = cursor.out_len;
    try cursor.append(allocator, undefined);

    const first_list_item = (try parseListItem(allocator, &cursor)) orelse return null;

    const list_marker = Marker.parse(cursor.source, first_list_item.marker).?;

    var list_style = list_marker.style;
    var next_item_would_make_loose = false;
    var tight = first_list_item.tight;

    _ = parseExpectToken(&cursor, .newline);
    if (parseExpectToken(&cursor, .section_break)) |_| {
        next_item_would_make_loose = true;
    }

    var loop_cursor = cursor.copy();
    while (try parseListItem(allocator, &loop_cursor)) |list_item| {
        const style = Marker.parse(cursor.source, list_item.marker).?.style;

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
        if (!list_item.tight) {
            tight = false;
        }

        cursor.commit(loop_cursor);

        _ = parseExpectToken(&loop_cursor, .newline);
        if (parseExpectToken(&loop_cursor, .section_break)) |_| {
            next_item_would_make_loose = true;
        }
    }

    cursor.out_buffer.set(start_event_idx, .{
        .kind = if (tight) .start_tight_list else .start_loose_list,
        .source = .{ .slice = cursor.source[first_list_item.marker..first_list_item.marker] },
    });
    if (tight) {
        try cursor.append(allocator, .{ .kind = .close_tight_list, .source = .{ .slice = cursor.source[cursor.index..cursor.index] } });
    } else {
        try cursor.append(allocator, .{ .kind = .close_loose_list, .source = .{ .slice = cursor.source[cursor.index..cursor.index] } });
    }
    parent.commit(cursor);
    return;
}

pub const ListItem = struct {
    marker: u32,
    tight: bool,
};

fn parseListItem(allocator: std.mem.Allocator, parent_cursor: *Cursor) !?ListItem {
    var cursor = parent_cursor.copy();

    const marker = parseExpectToken(&cursor, .marker) orelse return null;

    try cursor.append(allocator, .{ .kind = .start_list_item, .source = .{ .slice = cursor.source[marker.start..marker.end] } });

    // Remove any leading spaces
    _ = parseExpectToken(&cursor, .spaces);

    // Parse at least one bit of text
    (try parseText(allocator, &cursor)) orelse return null;
    var tight = true;
    while (true) {
        var loop_cursor = cursor;
        // If there is a newline or a section break, skip it
        _ = parseExpectToken(&loop_cursor, .newline);
        if (parseExpectToken(&loop_cursor, .newline) orelse parseExpectToken(&loop_cursor, .section_break)) |_| {
            tight = false;
        }
        _ = parseExpectToken(&loop_cursor, .spaces) orelse break;
        if (try parseText(allocator, &loop_cursor)) |_| {
            cursor.commit(loop_cursor);
            continue;
        }
        return error.Unimplemented;
    }

    try cursor.append(allocator, .{ .kind = .close_list_item, .source = .{ .slice = cursor.source[0..0] } });
    parent_cursor.commit(cursor);
    return ListItem{
        .marker = marker.start,
        .tight = tight,
    };
}

pub fn parseText(allocator: std.mem.Allocator, parent: *Cursor) !?void {
    const first_text = parseExpectToken(parent, .text) orelse return null;

    const start_index = first_text.start;
    var end_index = first_text.end;

    var cursor = parent.copy();
    while (parseToken(&cursor)) |token| {
        switch (token.kind) {
            .section_break,
            .spaces,
            .heading,
            .marker,
            .quote,
            => break,

            .newline => {},

            .text => {
                end_index = token.end;
                parent.commit(cursor);
            },
        }
    }

    try parent.append(allocator, .{ .kind = .text, .source = .{ .slice = parent.source[start_index..end_index] } });

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
    start: u32,
    end: u32,

    pub const Kind = enum {
        newline,
        section_break,
        text,
        heading,
        marker,
        spaces,
        quote,
    };
};

pub fn parseToken(parent: *Cursor) ?Token {
    if (parent.source[parent.index] == 0) return null;
    if (Marker.parse(parent.source, parent.index)) |marker| {
        const start = parent.index;
        parent.index = marker.end;
        return Token{
            .start = start,
            .kind = .marker,
            .end = marker.end,
        };
    }

    const State = enum {
        default,
        newline,
        section_break,
        text,
        heading,
        spaces,
    };

    var res = Token{
        .kind = .text,
        .start = parent.index,
        .end = parent.index,
    };

    var index = parent.index;
    var state = State.default;
    while (parent.source[index] != 0) : (index += 1) {
        switch (state) {
            .default => switch (parent.source[index]) {
                '\n' => {
                    res.kind = .newline;
                    res.end = index + 1;
                    state = .newline;
                },
                ' ' => {
                    res.kind = .spaces;
                    res.end = index + 1;
                    state = .spaces;
                },
                '#' => {
                    res.kind = .heading;
                    res.end = index + 1;
                    state = .heading;
                },
                '>' => {
                    res.kind = .quote;
                    res.end = index + 1;
                    break;
                },
                else => {
                    res.kind = .text;
                    state = .text;
                },
            },
            .newline => switch (parent.source[index]) {
                '\n' => {
                    res.kind = .section_break;
                    res.end = index + 1;
                    state = .section_break;
                },
                else => break,
            },
            .section_break => switch (parent.source[index]) {
                '\n' => res.end = index + 1,
                else => break,
            },
            .heading => switch (parent.source[index]) {
                '#' => res.end = index + 1,
                else => break,
            },
            .text => switch (parent.source[index]) {
                '\n' => break,
                else => res.end = index + 1,
            },
            .spaces => switch (parent.source[index]) {
                ' ' => {
                    res.end = index + 1;
                },
                else => break,
            },
        }
    }

    parent.index = res.end;

    return res;
}

const Cursor = struct {
    source: [*:0]const u8,
    out_buffer: *Document,
    index: u32,
    out_len: u32,

    pub fn copy(this: @This()) @This() {
        return @This(){
            .source = this.source,
            .out_buffer = this.out_buffer,
            .index = this.index,
            .out_len = this.out_len,
        };
    }

    pub fn append(this: *@This(), allocator: std.mem.Allocator, event: Event) !void {
        try this.out_buffer.resize(allocator, this.out_len + 1);
        this.out_buffer.set(this.out_len, event);
        this.out_len += 1;
    }

    // Updates another Parser
    pub fn commit(this: *@This(), other: @This()) void {
        this.index = other.index;
        this.out_len = other.out_len;
    }
};

test "heading" {
    try testParse(
        \\## A level _two_ heading
        \\
    , &.{
        .{ .start_heading = "##" },
        .{ .text = "A level _two_ heading" },
        .close_heading,
    });
}

test "heading that takes up three lines" {
    try testParse(
        \\## A heading that
        \\takes up
        \\three lines
        \\
        \\A paragraph, finally.
    , &.{
        .{ .start_heading = "##" },
        .{ .text = 
        \\A heading that
        \\takes up
        \\three lines
        },
        .close_heading,
        .{ .text = 
        \\A paragraph, finally.
        },
    });
}

test "quote with a list in it" {
    try testParse(
        \\> This is a block quote.
        \\>
        \\> 1. with a
        \\> 2. list in it
    , &.{
        .start_quote,
        .{ .text = 
        \\This is a block quote.
        },

        .start_tight_list,
        .{ .start_list_item = "1. " },
        .{ .text = 
        \\with a
        },
        .close_list_item,
        .{ .start_list_item = "2. " },
        .{ .text = 
        \\list in it
        },
        .close_list_item,
        .close_tight_list,

        .close_quote,
    });
}

test "quote 2" {
    try testParse(
        \\> This is a block
        \\quote.
    , &.{
        .start_quote,
        .{ .text = 
        \\This is a block
        \\quote.
        },
        .close_quote,
    });
}

test "list item containing a block quote" {
    if (true) return error.SkipZigTest;
    try testParse(
        \\1.  This is a
        \\ list item.
        \\
        \\ > containing a block quote
    , &.{
        .{ .start_loose_list = "1. " },

        .start_list_item,
        .{ .text = 
        \\This is a
        },
        .{ .text = 
        \\list item.
        },

        .start_quote,
        .{ .text = 
        \\containing a block quote
        },
        .close_quote,
        .close_list_item,

        .close_loose_list,
    });
}

test "list item with second paragraph" {
    try testParse(
        \\1.  This is a
        \\list item.
        \\
        \\  Second paragraph under the
        \\list item.
    , &.{
        .start_loose_list,

        .{ .start_list_item = "1. " },
        .{ .text = 
        \\This is a
        \\list item.
        },
        .{ .text = 
        \\Second paragraph under the
        \\list item.
        },
        .close_list_item,

        .close_loose_list,
    });
}

test "4 lists" {
    try testParse(
        \\i) one
        \\i. one (style change)
        \\+ bullet
        \\* bullet (style change)
    , &.{
        .start_tight_list,
        .{ .start_list_item = "i) " },
        .{ .text = "one" },
        .close_list_item,
        .close_tight_list,

        .start_tight_list,
        .{ .start_list_item = "i. " },
        .{ .text = "one (style change)" },
        .close_list_item,
        .close_tight_list,

        .start_tight_list,
        .{ .start_list_item = "+ " },
        .{ .text = "bullet" },
        .close_list_item,
        .close_tight_list,

        .start_tight_list,
        .{ .start_list_item = "* " },
        .{ .text = "bullet (style change)" },
        .close_list_item,
        .close_tight_list,
    });
}

test "list: alpha/roman ambiguous" {
    try testParse(
        \\i. item
        \\j. next item
    , &.{
        .start_tight_list,

        .{ .start_list_item = "i. " },
        .{ .text = "item" },
        .close_list_item,

        .{ .start_list_item = "j. " },
        .{ .text = "next item" },
        .close_list_item,

        .close_tight_list,
    });
}

test "list: start number" {
    try testParse(
        \\5) five
        \\8) six
    , &.{
        .start_tight_list,

        .{ .start_list_item = "5) " },
        .{ .text = "five" },
        .close_list_item,

        .{ .start_list_item = "8) " },
        .{ .text = "six" },
        .close_list_item,

        .close_tight_list,
    });
}

test "loose list" {
    try testParse(
        \\- one
        \\
        \\- two
    , &.{
        .start_loose_list,

        .{ .start_list_item = "- " },
        .{ .text = "one" },
        .close_list_item,

        .{ .start_list_item = "- " },
        .{ .text = "two" },
        .close_list_item,

        .close_loose_list,
    });
}

const TestEvent = union(enum) {
    text: []const u8,
    start_heading: []const u8,
    close_heading,

    start_quote,
    close_quote,

    /// Data is the text of the first marker
    start_tight_list,
    close_tight_list,

    /// Data is the text of the first marker
    start_loose_list,
    close_loose_list,

    start_list_item: []const u8,
    close_list_item,

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (this) {
            .text,
            .start_list_item,
            .start_heading,
            => |text| try writer.print("{s} \"{}\"", .{ std.meta.tagName(this), std.zig.fmtEscapes(text) }),

            // Events that are only tags just print the tag name
            .close_heading,
            .start_quote,
            .close_quote,
            .start_tight_list,
            .close_tight_list,
            .start_loose_list,
            .close_loose_list,
            .close_list_item,
            => try writer.print("{s}", .{std.meta.tagName(this)}),
        }
    }
};

fn testParse(source: [*:0]const u8, expected: []const TestEvent) !void {
    var parsed = try parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);

    var expected_text = std.ArrayList(u8).init(std.testing.allocator);
    defer expected_text.deinit();
    for (expected) |expected_block| {
        try expected_text.writer().print("{}\n", .{expected_block});
    }

    var parsed_text = std.ArrayList(u8).init(std.testing.allocator);
    defer parsed_text.deinit();
    var i: usize = 0;
    while (i < parsed.len) : (i += 1) {
        try parsed_text.writer().print("{}\n", .{Event{
            .kind = parsed.items(.kind)[i],
            .source = parsed.items(.source)[i],
        }});
    }

    try std.testing.expectEqualStrings(expected_text.items, parsed_text.items);
}

fn beep(src: std.builtin.SourceLocation, input: anytype) @TypeOf(input) {
    std.debug.print("{s}:{} {}\n", .{ src.fn_name, src.line, input });
    return input;
}
