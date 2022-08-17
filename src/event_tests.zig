const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");
const djot = @import("./djot.zig");

const Cursor = djot.Cursor;
const EventIndex = Cursor.EventIndex;
const Event = djot.Event;
const Error = djot.Error;

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

fn testParse(source: []const u8, expected: []const TestEvent) !void {
    errdefer std.debug.print("\n```djot\n{s}\n```\n\n", .{source});

    var parsed = try djot.parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);

    var expected_text = std.ArrayList(u8).init(std.testing.allocator);
    defer expected_text.deinit();
    for (expected) |expected_block| {
        try expected_text.writer().print("{}\n", .{expected_block});
    }

    var parsed_text = std.ArrayList(u8).init(std.testing.allocator);
    defer parsed_text.deinit();
    var i: usize = 0;
    while (i < parsed.events.len) : (i += 1) {
        try parsed_text.writer().print("{}\n", .{Event{
            .kind = parsed.events.items(.kind)[i],
            .source = parsed.events.items(.source)[i],
            .extra = parsed.events.items(.extra)[i],
        }});
    }

    try std.testing.expectEqualStrings(expected_text.items, parsed_text.items);
}
