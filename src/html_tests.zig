const std = @import("std");
const djot = @import("./djot.zig");

pub fn testDjotToHtml(djot_source: [:0]const u8, expected_html: []const u8) !void {
    errdefer std.debug.print("\n```djot\n{s}\n```\n\n", .{djot_source});
    const html = try djot.toHtml(std.testing.allocator, djot_source);
    defer std.testing.allocator.free(html);
    try std.testing.expectEqualStrings(expected_html, html);
}

comptime {
_ = @import("test/attributes.zig");
_ = @import("test/tables.zig");
_ = @import("test/math.zig");
_ = @import("test/para.zig");
_ = @import("test/raw.zig");
_ = @import("test/spans.zig");
_ = @import("test/task_lists.zig");
_ = @import("test/fenced_divs.zig");
_ = @import("test/emoji.zig");
_ = @import("test/thematic_breaks.zig");
_ = @import("test/links_and_images.zig");
_ = @import("test/definition-lists.zig");
_ = @import("test/blockquote.zig");
_ = @import("test/super-subscript.zig");
_ = @import("test/code_blocks.zig");
_ = @import("test/escapes.zig");
_ = @import("test/emphasis.zig");
_ = @import("test/footnotes.zig");
_ = @import("test/lists.zig");
_ = @import("test/insert-delete-mark.zig");
_ = @import("test/headings.zig");
_ = @import("test/smart.zig");
_ = @import("test/verbatim.zig");
}

