const std = @import("std");
const djot = @import("./djot.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    const source = try stdin.readToEndAlloc(gpa.allocator(), 500 * 1024 * 1024);
    defer gpa.allocator().free(source);

    try djot.toHtml(gpa.allocator(), source, stdout.writer());
}

comptime {
    _ = @import("djot.zig");
    _ = @import("event_tests.zig");
    _ = @import("html_tests.zig");
    _ = @import("./Marker.zig");
}
