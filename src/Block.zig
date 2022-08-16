const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");

const Document = std.MultiArrayList(Event);

const Event = struct {
    kind: Kind,
    source: SourceIndex,
    extra: Extra = Extra{ .none = {} },

    const Kind = enum {
        text,
        text_break,

        start_heading,
        close_heading,

        start_quote,
        close_quote,

        start_list,
        close_list,

        start_list_item,
        close_list_item,
    };

    const Extra = union {
        none: void,
        start_list: List,

        const List = struct {
            style: Marker.Style,
        };
    };

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{std.meta.tagName(this.kind)});
        switch (this.kind) {
            .text,
            .start_heading,
            .start_list_item,
            => try writer.print(" \"{}\"", .{std.zig.fmtEscapes(this.source.slice)}),

            .start_list => try writer.print(" {s}", .{
                std.meta.tagName(this.extra.start_list.style),
            }),

            // Events that are only tags just print the tag name
            .text_break,
            .close_heading,
            .start_quote,
            .close_quote,
            .close_list,
            .close_list_item,
            => {},
        }
    }
};

// TODO: Make this just a wrapper over a u32
const SourceIndex = struct {
    slice: []const u8,
};

const Error = std.mem.Allocator.Error || error{
    // TODO: Remove this
    WouldLoop,
};

const EventIndex = struct {
    index: u32,
};

pub fn parse(allocator: std.mem.Allocator, source: [*:0]const u8) Error!Document.Slice {
    var document = std.MultiArrayList(Event){};
    defer document.deinit(allocator);

    var cursor = Cursor{
        .source = source,
        .out_buffer = &document,
        .index = 0,
        .out_len = 0,
    };

    _ = try parseBlocks(allocator, &cursor, null);

    document.len = cursor.out_len;

    return document.toOwnedSlice();
}

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
        std.debug.print("{s}|", .{std.meta.tagName(this.token)});
    }
};

pub fn parseBlocks(allocator: std.mem.Allocator, parent: *Cursor, prefix: ?*const Prefix) Error!bool {
    var cursor = parent.copy();

    var prev_index = cursor.index;
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

        if (cursor.index == prev_index) {
            const source = std.mem.span(cursor.source);
            std.debug.print("source = \"{}\"\n", .{std.zig.fmtEscapes(source[cursor.index..])});
            std.debug.print("events = {any}\n", .{cursor.out_buffer.items(.kind)});
            return error.WouldLoop;
        }
        prev_index = cursor.index;
    }

    const was_content = cursor.out_len > parent.out_len;

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

    _ = try cursor.append(allocator, .{ .kind = .start_heading, .source = .{ .slice = cursor.source[token.start..token.end] } });
    _ = try parseText(allocator, &cursor);
    _ = try cursor.append(allocator, .{ .kind = .close_heading, .source = .{ .slice = cursor.source[0..0] } });
    _ = parseExpectToken(&cursor, .newline);

    parent.commit(cursor);
}

pub fn parseQuote(allocator: std.mem.Allocator, parent: *Cursor, prefix: ?*const Prefix) Error!?void {
    var cursor = parent.copy();
    const quote_token = parseExpectToken(&cursor, .quote) orelse return null;
    _ = parseExpectToken(&cursor, .space) orelse return null;

    _ = try cursor.append(allocator, .{ .kind = .start_quote, .source = .{ .slice = cursor.source[quote_token.start..quote_token.end] } });
    _ = try parseBlocks(allocator, &cursor, &.{ .prev = &.{ .prev = prefix, .token = .quote }, .token = .space });
    _ = try cursor.append(allocator, .{ .kind = .close_quote, .source = .{ .slice = cursor.source[cursor.index..cursor.index] } });

    parent.commit(cursor);
}

pub fn parseList(allocator: std.mem.Allocator, parent: *Cursor, prefix: ?*const Prefix) Error!?void {
    var cursor = parent.copy();

    // Allocate a place for the start event; we'll have to update it once we know
    // whether it's a tight or loose list
    const start_event = try cursor.append(allocator, .{
        .kind = .start_list,
        .source = .{ .slice = cursor.source[cursor.index..cursor.index] },
        .extra = Event.Extra{ .start_list = .{ .style = undefined } },
    });

    const first_list_item = (try parseListItem(allocator, &cursor, prefix)) orelse return null;

    const list_marker = Marker.parse(cursor.source, @intCast(u32, @ptrToInt(cursor.out_buffer.items(.source)[first_list_item.index].slice.ptr) - @ptrToInt(cursor.source))).?;

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

        const item_marker = Marker.parse(loop_cursor.source, @intCast(u32, @ptrToInt(loop_cursor.out_buffer.items(.source)[list_item.index].slice.ptr) - @ptrToInt(loop_cursor.source))).?;
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

    cursor.out_buffer.items(.extra)[start_event.index] = Event.Extra{
        .start_list = .{
            .style = list_style,
        },
    };
    _ = try cursor.append(allocator, .{ .kind = .close_list, .source = .{ .slice = cursor.source[cursor.index..cursor.index] } });
    parent.commit(cursor);
    return;
}

fn parseListItem(allocator: std.mem.Allocator, parent_cursor: *Cursor, prefix: ?*const Prefix) Error!?EventIndex {
    var cursor = parent_cursor.copy();

    const marker = parseExpectToken(&cursor, .marker) orelse return null;
    _ = parseExpectToken(&cursor, .space) orelse return null;

    const event_index = try cursor.append(allocator, .{ .kind = .start_list_item, .source = .{ .slice = cursor.source[marker.start..marker.end] } });

    if (!try parseBlocks(allocator, &cursor, &.{ .prev = prefix, .token = .space })) {
        return null;
    }

    _ = try cursor.append(allocator, .{ .kind = .close_list_item, .source = .{ .slice = cursor.source[0..0] } });
    parent_cursor.commit(cursor);
    return event_index;
}

pub fn parseText(allocator: std.mem.Allocator, parent: *Cursor) !?void {
    var blank = true;

    const start_index = parent.index;
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

    _ = try parent.append(allocator, .{ .kind = .text, .source = .{ .slice = parent.source[start_index..end_index] } });

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
        text,
        heading,
        marker,
        space,
        quote,
    };
};

pub fn parseToken(parent: *Cursor) ?Token {
    if (parent.source[parent.index] == 0) return null;
    if (Marker.parse(parent.source, parent.index)) |marker| blk: {
        const start = parent.index;
        // Only allow alpha numeric characters with a single character
        if (marker.style.isAlpha() and marker.end - start > 2) {
            break :blk;
        }
        parent.index = marker.end;
        return Token{
            .start = start,
            .kind = .marker,
            .end = marker.end,
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
        .start = parent.index,
        .end = parent.index,
    };

    var index = parent.index;
    var state = State.default;
    while (parent.source[index] != 0) : (index += 1) {
        switch (state) {
            .default => switch (parent.source[index]) {
                '#' => {
                    res.kind = .heading;
                    res.end = index + 1;
                    state = .heading;
                },
                ' ' => {
                    res.kind = .space;
                    res.end = index + 1;
                    break;
                },
                '\n' => {
                    res.kind = .newline;
                    res.end = index + 1;
                    break;
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

    pub fn append(this: *@This(), allocator: std.mem.Allocator, event: Event) !EventIndex {
        const index = EventIndex{ .index = this.out_len };
        try this.out_buffer.resize(allocator, this.out_len + 1);
        this.out_len += 1;
        this.out_buffer.set(index.index, event);
        return index;
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
        .{ .text = 
        \\A level _two_ heading
        \\
        },
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
        \\
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
        \\
        },

        .{ .start_list = .{ .style = .decimal_period } },
        .{ .start_list_item = "1." },
        .{ .text = 
        \\with a
        \\
        },
        .close_list_item,
        .{ .start_list_item = "2." },
        .{ .text = 
        \\list in it
        },
        .close_list_item,
        .close_list,

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
    try testParse(
        \\1.  This is a
        \\ list item.
        \\
        \\ > containing a block quote
    , &.{
        .{ .start_list = .{ .style = .decimal_period } },

        .{ .start_list_item = "1." },
        .{ .text = 
        \\ This is a
        \\ list item.
        \\
        },

        .start_quote,
        .{ .text = 
        \\containing a block quote
        },
        .close_quote,
        .close_list_item,

        .close_list,
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
        .{ .start_list = .{ .style = .decimal_period } },

        .{ .start_list_item = "1." },
        .{ .text = 
        \\ This is a
        \\list item.
        \\
        },
        .text_break,
        .{ .text = 
        \\ Second paragraph under the
        \\list item.
        },
        .close_list_item,

        .close_list,
    });
}

test "4 lists" {
    try testParse(
        \\i) one
        \\i. one (style change)
        \\+ bullet
        \\* bullet (style change)
    , &.{
        .{ .start_list = .{ .style = .lower_roman_paren } },
        .{ .start_list_item = "i)" },
        .{ .text = 
        \\one
        \\
        },
        .close_list_item,
        .close_list,

        .{ .start_list = .{ .style = .lower_roman_period } },
        .{ .start_list_item = "i." },
        .{ .text = 
        \\one (style change)
        \\
        },
        .close_list_item,
        .close_list,

        .{ .start_list = .{ .style = .plus } },
        .{ .start_list_item = "+" },
        .{ .text = 
        \\bullet
        \\
        },
        .close_list_item,
        .close_list,

        .{ .start_list = .{ .style = .asterisk } },
        .{ .start_list_item = "*" },
        .{ .text = 
        \\bullet (style change)
        },
        .close_list_item,
        .close_list,
    });
}

test "list: alpha/roman ambiguous" {
    try testParse(
        \\i. item
        \\j. next item
    , &.{
        .{ .start_list = .{ .style = .lower_alpha_period } },

        .{ .start_list_item = "i." },
        .{ .text = 
        \\item
        \\
        },
        .close_list_item,

        .{ .start_list_item = "j." },
        .{ .text = "next item" },
        .close_list_item,

        .close_list,
    });
}

test "list: start number" {
    try testParse(
        \\5) five
        \\8) six
    , &.{
        .{ .start_list = .{ .style = .decimal_paren } },

        .{ .start_list_item = "5)" },
        .{ .text = 
        \\five
        \\
        },
        .close_list_item,

        .{ .start_list_item = "8)" },
        .{ .text = 
        \\six
        },
        .close_list_item,

        .close_list,
    });
}

test "loose list" {
    try testParse(
        \\- one
        \\
        \\- two
    , &.{
        .{ .start_list = .{ .style = .hyphen } },

        .{ .start_list_item = "-" },
        .{ .text = 
        \\one
        \\
        },
        .close_list_item,

        .{ .start_list_item = "-" },
        .{ .text = "two" },
        .close_list_item,

        .close_list,
    });
}

const TestEvent = union(Event.Kind) {
    text: []const u8,

    text_break,

    start_heading: []const u8,
    close_heading,

    start_quote,
    close_quote,

    start_list: struct { style: Marker.Style },
    close_list,

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
        try writer.print("{s}", .{std.meta.tagName(this)});
        switch (this) {
            .text,
            .start_list_item,
            .start_heading,
            => |text| try writer.print(" \"{}\"", .{std.zig.fmtEscapes(text)}),

            .start_list => |list| {
                try writer.print(" {s}", .{
                    std.meta.tagName(list.style),
                });
            },

            // Events that are only tags just print the tag name
            .text_break,
            .close_heading,
            .start_quote,
            .close_quote,
            .close_list,
            .close_list_item,
            => {},
        }
    }
};

fn testParse(source: [*:0]const u8, expected: []const TestEvent) !void {
    errdefer std.debug.print("\n```djot\n{s}\n```\n\n", .{source});

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
            .extra = parsed.items(.extra)[i],
        }});
    }

    try std.testing.expectEqualStrings(expected_text.items, parsed_text.items);
}

fn beep(src: std.builtin.SourceLocation, input: anytype) @TypeOf(input) {
    std.debug.print("{s}:{} {}\n", .{ src.fn_name, src.line, input });
    return input;
}
