const std = @import("std");

pub fn main() anyerror!void {
    // Note that info level log messages are by default printed only in Debug
    // and ReleaseSafe build modes.
    std.log.info("All your codebase are belong to us.", .{});
}

comptime {
    _ = @import("djot.zig");
    _ = @import("html_tests.zig");
}
