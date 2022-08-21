const std = @import("std");
const unicode = @import("./unicode.zig");

pub fn fmtEscapes(text: []const u8) EscapeFormatter {
    return EscapeFormatter{
        .text = text,
    };
}

pub fn writeEscaped(text: []const u8, writer: anytype) !void {
    var i: usize = 0;
    while (i < text.len) {
        const codepoint_length = try std.unicode.utf8ByteSequenceLength(text[i]);
        // TODO: check this earlier?
        if (i + codepoint_length > text.len) return error.InvalidUTF8;
        switch (try std.unicode.utf8Decode(text[i..][0..codepoint_length])) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            unicode.ELLIPSES => try writer.writeAll("&hellip;"),
            unicode.EN_DASH => try writer.writeAll("&ndash;"),
            unicode.EM_DASH => try writer.writeAll("&mdash;"),
            unicode.LEFT_DOUBLE_QUOTE => try writer.writeAll("&ldquo;"),
            unicode.RIGHT_DOUBLE_QUOTE => try writer.writeAll("&rdquo;"),
            unicode.LEFT_SINGLE_QUOTE => try writer.writeAll("&lsquo;"),
            unicode.RIGHT_SINGLE_QUOTE => try writer.writeAll("&rsquo;"),
            else => try writer.writeAll(text[i..][0..codepoint_length]),
        }
        i += codepoint_length;
    }
}

const EscapeFormatter = struct {
    text: []const u8,

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        writeEscaped(this.text, writer) catch {};
    }
};
