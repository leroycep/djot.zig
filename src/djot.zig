const std = @import("std");
const blocks = @import("./Block.zig");
const Marker = @import("./Marker.zig");

const LEFT_DOUBLE_QUOTE = '“';
const RIGHT_DOUBLE_QUOTE = '”';
const LEFT_SINGLE_QUOTE = '‘';
const RIGHT_SINGLE_QUOTE = '’';

// TODO: Use concrete error set
pub fn toHtml(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var doc = try parse(allocator, source);
    defer doc.deinit(allocator);

    var html = std.ArrayList(u8).init(allocator);
    defer html.deinit();
    for (doc.events.items(.kind)) |event_kind, event_index| {
        switch (event_kind) {
            .text => {
                const t = doc.events.items(.source)[event_index].slice;
                var i: usize = 0;
                while (i < t.len) {
                    const codepoint_length = try std.unicode.utf8ByteSequenceLength(t[i]);
                    // TODO: check this earlier?
                    if (i + codepoint_length > t.len) return error.InvalidUTF8;
                    switch (try std.unicode.utf8Decode(t[i..][0..codepoint_length])) {
                        '…' => try html.appendSlice("&hellip;"),
                        '–' => try html.appendSlice("&ndash;"),
                        '—' => try html.appendSlice("&mdash;"),
                        LEFT_DOUBLE_QUOTE => try html.appendSlice("&ldquo;"),
                        RIGHT_DOUBLE_QUOTE => try html.appendSlice("&rdquo;"),
                        LEFT_SINGLE_QUOTE => try html.appendSlice("&lsquo;"),
                        RIGHT_SINGLE_QUOTE => try html.appendSlice("&rsquo;"),
                        else => try html.appendSlice(t[i..][0..codepoint_length]),
                    }
                    i += codepoint_length;
                }
            },
            .text_break => try html.appendSlice("<p>\n"),

            .start_heading => try html.appendSlice("<h1>"),
            .close_heading => try html.appendSlice("</h1>"),

            .start_list => try html.appendSlice("<ul>"),
            .close_list => try html.appendSlice("</ul>"),

            .start_list_item => try html.appendSlice("<li>"),
            .close_list_item => try html.appendSlice("</li>"),

            .start_quote => try html.appendSlice("<quote>"),
            .close_quote => try html.appendSlice("</quote>"),
        }
    }

    return html.toOwnedSlice();
}

pub const Document = struct {
    events: std.MultiArrayList(Event).Slice,

    pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        this.events.deinit(allocator);
    }
};

pub const Event = struct {
    kind: Kind,
    source: Source,
    extra: Extra = Extra{ .none = {} },

    pub const Kind = enum {
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

    // TODO: Make this just a wrapper over a u32
    pub const Source = union {
        slice: []const u8,
    };

    pub const Extra = union {
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

pub fn parse(allocator: std.mem.Allocator, source: []const u8) Error!Document {
    var events = std.MultiArrayList(Event){};
    defer events.deinit(allocator);

    var cursor = Cursor{
        .source = source,
        .events = &events,
        .source_index = .{ .index = 0 },
        .events_index = .{ .index = 0 },
    };

    _ = try blocks.parseBlocks(allocator, &cursor, null);

    events.len = cursor.events_index.index;

    return Document{
        .events = events.toOwnedSlice(),
    };
}

pub const Cursor = @import("./parse.zig").Cursor(u8, Event);

pub const Error = std.mem.Allocator.Error || error{
    // TODO: Remove this
    WouldLoop,
};

comptime {
    _ = @import("./Block.zig");
}
