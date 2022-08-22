const std = @import("std");
const djot = @import("./djot.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var output_fmt = Fmt.html;

    {
        const args = try std.process.argsAlloc(gpa.allocator());
        defer std.process.argsFree(gpa.allocator(), args);
        for (args[1..]) |arg| {
            if (std.mem.startsWith(u8, arg, "-f")) {
                output_fmt = std.meta.stringToEnum(Fmt, arg[2..]) orelse {
                    std.debug.print("Unknown format {s}\n", .{arg[2..]});
                    return error.UnknownFormat;
                };
            }
        }
    }

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    const source = try stdin.readToEndAlloc(gpa.allocator(), 500 * 1024 * 1024);
    defer gpa.allocator().free(source);

    switch (output_fmt) {
        .html => try djot.toHtml(gpa.allocator(), source, stdout.writer()),
        .events => {
            var doc = try djot.parse(gpa.allocator(), source);
            defer doc.deinit(gpa.allocator());
            const out = stdout.writer();
            for (doc.events.items(.tag)) |_, event_index| {
                try out.print("{}\n", .{doc.fmtEvent(event_index)});
            }
        },
        .tokens => {
            const out = stdout.writer();

            var index: usize = 0;
            var pos: usize = 0;
            while (true) : (index += 1) {
                const token = djot.Token.parse(source, pos);
                try out.print("token[{}] = {s} \"{}\"\n", .{ index, std.meta.tagName(token.kind), std.zig.fmtEscapes(source[token.start..token.end]) });
                if (token.kind == .eof) {
                    break;
                }
                pos = token.end;
            }
        },
    }
}

pub const Fmt = enum {
    html,
    events,
    tokens,
};

comptime {
    _ = @import("djot.zig");
    //_ = @import("event_tests.zig");
    _ = @import("html_tests.zig");
    _ = @import("./Marker.zig");
}
