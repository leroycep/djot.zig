const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");
const djot = @import("./djot.zig");

test "events heading" {
    try testParse(
        \\## A level _two_ heading
        \\
    , &.{
        .{ .start_heading = 2 },
        .{ .text = 
        \\A level _two_ heading
        },
        .{ .close_heading = 2 },
    });
}

test "events heading that takes up three lines" {
    try testParse(
        \\## A heading that
        \\takes up
        \\three lines
        \\
        \\A paragraph, finally.
    , &.{
        .{ .start_heading = 2 },
        .{ .text = 
        \\A heading that
        \\takes up
        \\three lines
        },
        .{ .close_heading = 2 },

        .start_paragraph,
        .{ .text = 
        \\A paragraph, finally.
        },
        .close_paragraph,
    });
}

test "events quote with a list in it" {
    try testParse(
        \\> This is a block quote.
        \\>
        \\> 1. with a
        \\> 2. list in it
    , &.{
        .start_quote,
        .start_paragraph,
        .{ .text = "This is a block quote." },
        .close_paragraph,

        .{ .start_list = .{ .style = .decimal_period } },
        .{ .start_list_item = "1." },
        .{ .text = "with a" },
        .{ .close_list_item = "1." },
        .{ .start_list_item = "2." },
        .{ .text = "list in it" },
        .{ .close_list_item = "2." },
        .{ .close_list = .{ .style = .decimal_period } },

        .close_quote,
    });
}

test "events quote 2" {
    try testParse(
        \\> This is a block
        \\quote.
    , &.{
        .start_quote,
        .start_paragraph,
        .{ .text = 
        \\This is a block
        \\quote.
        },
        .close_paragraph,
        .close_quote,
    });
}

test "events list item containing a block quote" {
    try testParse(
        \\1.  This is a
        \\ list item.
        \\
        \\ > containing a block quote
    , &.{
        .{ .start_list = .{ .style = .decimal_period } },

        .{ .start_list_item = "1." },
        .start_paragraph,
        .{ .text = 
        \\This is a
        \\ list item.
        },
        .close_paragraph,

        .start_quote,
        .start_paragraph,
        .{ .text = 
        \\containing a block quote
        },
        .close_paragraph,
        .close_quote,
        .{ .close_list_item = "1." },

        .{ .close_list = .{ .style = .decimal_period } },
    });
}

test "events list item with second paragraph" {
    try testParse(
        \\1.  This is a
        \\list item.
        \\
        \\  Second paragraph under the
        \\list item.
    , &.{
        .{ .start_list = .{ .style = .decimal_period } },

        .{ .start_list_item = "1." },
        .start_paragraph,
        .{ .text = 
        \\This is a
        \\list item.
        },
        .close_paragraph,
        .start_paragraph,
        .{ .text = 
        \\Second paragraph under the
        \\list item.
        },
        .close_paragraph,
        .{ .close_list_item = "1." },

        .{ .close_list = .{ .style = .decimal_period } },
    });
}

test "events 4 lists" {
    try testParse(
        \\i) one
        \\i. one (style change)
        \\+ bullet
        \\* bullet (style change)
    , &.{
        .{ .start_list = .{ .style = .lower_roman_paren } },
        .{ .start_list_item = "i)" },
        .{ .text = "one" },
        .{ .close_list_item = "i)" },
        .{ .close_list = .{ .style = .lower_roman_paren } },

        .{ .start_list = .{ .style = .lower_roman_period } },
        .{ .start_list_item = "i." },
        .{ .text = "one (style change)" },
        .{ .close_list_item = "i." },
        .{ .close_list = .{ .style = .lower_roman_period } },

        .{ .start_list = .{ .style = .plus } },
        .{ .start_list_item = "+" },
        .{ .text = "bullet" },
        .{ .close_list_item = "+" },
        .{ .close_list = .{ .style = .plus } },

        .{ .start_list = .{ .style = .asterisk } },
        .{ .start_list_item = "*" },
        .{ .text = "bullet (style change)" },
        .{ .close_list_item = "*" },
        .{ .close_list = .{ .style = .asterisk } },
    });
}

test "events list: alpha/roman ambiguous" {
    try testParse(
        \\i. item
        \\j. next item
    , &.{
        .{ .start_list = .{ .style = .lower_alpha_period } },

        .{ .start_list_item = "i." },
        .{ .text = "item" },
        .{ .close_list_item = "i." },

        .{ .start_list_item = "j." },
        .{ .text = "next item" },
        .{ .close_list_item = "j." },

        .{ .close_list = .{ .style = .lower_alpha_period } },
    });
}

test "events list: start number" {
    try testParse(
        \\5) five
        \\8) six
    , &.{
        .{ .start_list = .{ .style = .decimal_paren } },

        .{ .start_list_item = "5)" },
        .{ .text = "five" },
        .{ .close_list_item = "5)" },

        .{ .start_list_item = "8)" },
        .{ .text = 
        \\six
        },
        .{ .close_list_item = "8)" },

        .{ .close_list = .{ .style = .decimal_paren } },
    });
}

test "events loose list" {
    try testParse(
        \\- one
        \\
        \\- two
    , &.{
        .{ .start_list = .{ .style = .hyphen } },

        .{ .start_list_item = "-" },
        .start_paragraph,
        .{ .text = "one" },
        .close_paragraph,
        .{ .close_list_item = "-" },

        .{ .start_list_item = "-" },
        .start_paragraph,
        .{ .text = "two" },
        .close_paragraph,
        .{ .close_list_item = "-" },

        .{ .close_list = .{ .style = .hyphen } },
    });
}

const TestEvent = union(djot.Event.Kind) {
    text: []const u8,
    escaped: []const u8,

    start_paragraph,
    close_paragraph,

    start_heading: u32,
    close_heading: u32,

    start_quote,
    close_quote,

    start_list: djot.Event.List,
    close_list: djot.Event.List,

    start_list_item: []const u8,
    close_list_item: []const u8,

    start_verbatim,
    close_verbatim,

    start_strong,
    close_strong,

    start_emphasis,
    close_emphasis,

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
            .escaped,
            .start_list_item,
            .close_list_item,
            => |text| try writer.print(" \"{}\"", .{std.zig.fmtEscapes(text)}),

            .start_heading,
            .close_heading,
            => |level| try writer.print(" {}", .{level}),

            .start_list,
            .close_list,
            => |list| try writer.print(" {s}", .{std.meta.tagName(list.style)}),

            // Events that are only tags just print the tag name
            .start_quote,
            .close_quote,
            .start_paragraph,
            .close_paragraph,
            .start_verbatim,
            .close_verbatim,
            .start_strong,
            .close_strong,
            .start_emphasis,
            .close_emphasis,
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
    var i: u32 = 0;
    while (i < parsed.events.len) : (i += 1) {
        try parsed_text.writer().print("{}\n", .{parsed.event(i).fmtWithSource(source)});
    }

    try std.testing.expectEqualStrings(expected_text.items, parsed_text.items);
}
