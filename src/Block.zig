const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");

const Event = union(enum) {
    text: []const u8,
    heading: []const u8,

    start_quote,
    close_quote,

    /// Data is the text of the first marker
    start_tight_list: []const u8,
    close_tight_list,

    /// Data is the text of the first marker
    start_loose_list: []const u8,
    close_loose_list,

    start_list_item,
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
            .heading,
            .start_tight_list,
            .start_loose_list,
            => |text| try writer.print("{s} \"{}\"", .{ std.meta.tagName(this), std.zig.fmtEscapes(text) }),

            // Events that are only tags just print the tag name
            .start_quote,
            .close_quote,
            .close_tight_list,
            .close_loose_list,
            .start_list_item,
            .close_list_item,
            => try writer.print("{s}", .{std.meta.tagName(this)}),
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, source: [*:0]const u8) ![]Event {
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    // for debugging
    var prev_index_opt: ?u32 = null;

    var index: u32 = 0;
    while (parseToken(source, index)) |token| {
        switch (token.kind) {
            .newline, .section_break, .spaces => index = token.end,

            .heading => if (parseHeading(source, index)) |heading_end| {
                try events.append(.{ .heading = source[index..heading_end] });
                index = heading_end;
            },
            .marker => if (try parseList(allocator, source, index)) |list| {
                defer allocator.free(list.events);
                const marker = Marker.parse(source, list.first_marker).?;
                try events.append(.{ .start_tight_list = source[list.first_marker..marker.end] });
                try events.appendSlice(list.events);
                try events.append(.close_tight_list);
                index = list.end;
            },
            .text => if (parseText(source, index)) |text_end| {
                try events.append(.{ .text = source[index..text_end] });
                index = text_end;
            },
        }

        // TODO: Panic once everything is supposed to be implemented
        //std.debug.panic("This is a bug in djot.zig: all types of lines should be handled", .{});
        defer if (builtin.mode == .Debug) {
            prev_index_opt = index;
        };
        if (builtin.mode == .Debug) {
            if (prev_index_opt) |prev_index| {
                if (index == prev_index) {
                    return error.WouldLoop;
                }
            }
        }
    }

    return events.toOwnedSlice();
}

pub fn parseHeading(source: [*:0]const u8, start_index: u32) ?u32 {
    if (source[start_index] != '#') return null;
    var index = start_index;
    while (source[index] != 0) : (index += 1) {
        if (source[index] == '\n') {
            if (source[index + 1] == 0 or source[index + 1] == '\n') {
                return index;
            }
        }
    }
    return index;
}

pub const List = struct {
    first_marker: u32,
    events: []Event,
    end: u32,
};

pub fn parseList(allocator: std.mem.Allocator, source: [*:0]const u8, start_index: u32) !?List {
    const first_list_item = (try parseListItem(allocator, source, start_index)) orelse return null;

    var events = std.ArrayList(Event).fromOwnedSlice(allocator, first_list_item.events);
    try events.insert(0, .start_list_item);
    try events.append(.close_list_item);
    defer events.deinit();

    var list_style = Marker.parse(source, first_list_item.marker).?.style;

    var index = first_list_item.end;
    if (parseExpectToken(source, index, .newline) orelse parseExpectToken(source, index, .section_break)) |tok| {
        index = tok.end;
    }
    while (try parseListItem(allocator, source, index)) |list_item| : (index = list_item.end) {
        defer allocator.free(list_item.events);
        const style = Marker.parse(source, list_item.marker).?.style;

        if (style != list_style and list_style.isRoman() and style.isAlpha()) {
            if (style != list_style.romanToAlpha()) break;
            list_style = list_style.romanToAlpha();
        } else if (style != list_style) {
            break;
        }

        try events.append(.start_list_item);
        try events.appendSlice(list_item.events);
        try events.append(.close_list_item);
    }

    return List{
        .first_marker = first_list_item.marker,
        .events = events.toOwnedSlice(),
        .end = index,
    };
}

pub const ListItem = struct {
    marker: u32,
    events: []Event,
    end: u32,
};

fn parseListItem(allocator: std.mem.Allocator, source: [*:0]const u8, start_index: u32) !?ListItem {
    const marker = parseExpectToken(source, start_index, .marker) orelse return null;

    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    var index = marker.end;
    if (parseExpectToken(source, index, .spaces)) |tok| {
        index = tok.end;
    }
    const first_text = parseText(source, index) orelse return null;
    try events.append(.{ .text = source[index..first_text] });
    index = first_text;
    var i = index;
    while (true) {
        if (parseExpectToken(source, i, .newline) orelse parseExpectToken(source, i, .section_break)) |tok| {
            i = tok.end;
        }
        const spaces = parseExpectToken(source, i, .spaces) orelse break;
        i = spaces.end;
        index = i;
        if (parseText(source, i)) |text_end| {
            try events.append(.{ .text = source[i..text_end] });
            i = text_end;
            index = i;
            continue;
        }
        return error.Unimplemented;
    }

    return ListItem{
        .marker = start_index,
        .events = events.toOwnedSlice(),
        .end = index,
    };
}

pub fn parseText(source: [*:0]const u8, start_index: u32) ?u32 {
    var index = start_index;
    const first_token = parseExpectToken(source, index, .text) orelse return null;
    index = first_token.end;

    var i = index;
    while (parseToken(source, i)) |token| : (i = token.end) {
        switch (token.kind) {
            .section_break,
            .spaces,
            .heading,
            .marker,
            => break,

            .newline => {},

            .text => index = i,
        }
    }
    return index;
}

fn parseExpectToken(source: [*:0]const u8, start_index: u32, expected_token_kind: Token.Kind) ?Token {
    const token = parseToken(source, start_index) orelse return null;
    if (token.kind == expected_token_kind) {
        return token;
    }
    return null;
}

pub const Token = struct {
    kind: Kind,
    end: u32,

    pub const Kind = enum {
        newline,
        section_break,
        text,
        heading,
        marker,
        spaces,
    };
};

pub fn parseToken(source: [*:0]const u8, start_index: u32) ?Token {
    if (source[start_index] == 0) return null;
    if (Marker.parse(source, start_index)) |marker| {
        return Token{
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
        .end = start_index,
    };

    var index = start_index;
    var state = State.default;
    while (source[index] != 0) : (index += 1) {
        switch (state) {
            .default => switch (source[index]) {
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
                else => {
                    res.kind = .text;
                    state = .text;
                },
            },
            .newline => switch (source[index]) {
                '\n' => {
                    res.kind = .section_break;
                    res.end = index + 1;
                    state = .section_break;
                },
                else => break,
            },
            .section_break => switch (source[index]) {
                '\n' => res.end = index + 1,
                else => break,
            },
            .heading => switch (source[index]) {
                '#' => res.end = index + 1,
                else => break,
            },
            .text => switch (source[index]) {
                '\n' => break,
                else => res.end = index + 1,
            },
            .spaces => switch (source[index]) {
                ' ' => {
                    res.end = index + 1;
                },
                else => break,
            },
        }
    }

    return res;
}

test "heading" {
    try testParse(
        \\## A level _two_ heading
        \\
    , &.{
        .{ .heading = "## A level _two_ heading" },
    });
}

test "heading" {
    try testParse(
        \\## A heading that
        \\takes up
        \\three lines
        \\
        \\A paragraph, finally.
    , &.{
        .{ .heading = 
        \\## A heading that
        \\takes up
        \\three lines
        },
        .{ .text = 
        \\A paragraph, finally.
        },
    });
}

test "quote" {
    if (true) return error.SkipZigTest;
    try testParse(
        \\> This is a block quote.
        \\>
        \\> 1. with a
        \\> 2. list in it
    , &.{
        .start_quote,
        .{ .text = 
        \\This is a blockquote.
        },

        .{ .start_tight_list = "1" },
        .start_list_item,
        .{ .text = 
        \\with a
        },
        .close_list_item,
        .start_list_item,
        .{ .text = 
        \\list in it
        },
        .close_list_item,
        .close_tight_list,

        .close_quote,
    });
}

test "quote" {
    if (true) return error.SkipZigTest;
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

test "list item" {
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

test "list item" {
    if (true) return error.SkipZigTest;
    try testParse(
        \\1.  This is a
        \\list item.
        \\
        \\  Second paragraph under the
        \\list item.
    , &.{
        .{ .start_loose_list = "1" },

        .start_list_item,
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

test "list" {
    try testParse(
        \\i) one
        \\i. one (style change)
        \\+ bullet
        \\* bullet (style change)
    , &.{
        .{ .start_tight_list = "i) " },
        .start_list_item,
        .{ .text = "one" },
        .close_list_item,
        .close_tight_list,

        .{ .start_tight_list = "i. " },
        .start_list_item,
        .{ .text = "one (style change)" },
        .close_list_item,
        .close_tight_list,

        .{ .start_tight_list = "+ " },
        .start_list_item,
        .{ .text = "bullet" },
        .close_list_item,
        .close_tight_list,

        .{ .start_tight_list = "* " },
        .start_list_item,
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
        .{ .start_tight_list = "i. " },

        .start_list_item,
        .{ .text = "item" },
        .close_list_item,

        .start_list_item,
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
        .{ .start_tight_list = "5) " },

        .start_list_item,
        .{ .text = "five" },
        .close_list_item,

        .start_list_item,
        .{ .text = "six" },
        .close_list_item,

        .close_tight_list,
    });
}

test "loose list" {
    if (true) return error.SkipZigTest;
    try testParse(
        \\- one
        \\
        \\- two
    , &.{
        .{ .start_loose_list = "-" },

        .start_list_item,
        .{ .text = "one" },
        .close_list_item,

        .start_list_item,
        .{ .text = "two" },
        .close_list_item,

        .close_loose_list,
    });
}

fn testParse(source: [*:0]const u8, expected: []const Event) !void {
    const parsed = try parse(std.testing.allocator, source);
    defer std.testing.allocator.free(parsed);

    var expected_text = std.ArrayList(u8).init(std.testing.allocator);
    defer expected_text.deinit();
    for (expected) |expected_block| {
        try expected_text.writer().print("{}\n", .{expected_block});
    }

    var parsed_text = std.ArrayList(u8).init(std.testing.allocator);
    defer parsed_text.deinit();
    for (parsed) |parsed_block| {
        try parsed_text.writer().print("{}\n", .{parsed_block});
    }

    try std.testing.expectEqualStrings(expected_text.items, parsed_text.items);
}

fn beep(src: std.builtin.SourceLocation, input: anytype) @TypeOf(input) {
    std.debug.print("{s}:{} {}\n", .{ src.fn_name, src.line, input });
    return input;
}
