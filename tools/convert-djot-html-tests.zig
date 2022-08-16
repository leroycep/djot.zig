const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    if (args.len < 2) {
        return error.NoTestCaseDirectorySpecified;
    }

    const cwd = std.fs.cwd();

    var test_dir = try cwd.openIterableDir(args[1], .{});
    defer test_dir.close();

    var out_dir = try cwd.makeOpenPath("src/test", .{});
    defer out_dir.close();

    var test_index_zig_source = std.ArrayList(u8).init(gpa.allocator());
    defer test_index_zig_source.deinit();

    try test_index_zig_source.writer().writeAll(
        \\const std = @import("std");
        \\const djot = @import("./djot.zig");
        \\
        \\pub fn testDjotToHtml(djot_source: [:0]const u8, expected_html: []const u8) !void {
        \\    errdefer std.debug.print("\n```djot\n{s}\n```\n\n", .{djot_source});
        \\    const html = try djot.toHtml(std.testing.allocator, djot_source);
        \\    defer std.testing.allocator.free(html);
        \\    try std.testing.expectEqualStrings(expected_html, html);
        \\}
        \\
        \\comptime {
        \\
    );

    var num_tests_converted: usize = 0;
    var walker = try test_dir.walk(arena.allocator());
    while (try walker.next()) |walk_entry| {
        if (walk_entry.kind != .File) {
            continue;
        }

        const test_filepath = walk_entry.path;
        const test_extension = std.fs.path.extension(test_filepath);
        if (!std.mem.eql(u8, test_extension, ".test")) {
            std.debug.print("\"{}\" has wrong extension, skipping\n", .{std.zig.fmtEscapes(test_filepath)});
            continue;
        }
        const output_filepath = try std.fmt.allocPrint(arena.allocator(), "{s}.zig", .{test_filepath[0 .. test_filepath.len - 5]});

        const test_source = try walk_entry.dir.readFileAlloc(arena.allocator(), walk_entry.basename, 50 * 1024);
        const tests = try extractTests(arena.allocator(), test_source);

        var zig_source = std.ArrayList(u8).init(gpa.allocator());
        defer zig_source.deinit();

        const writer = zig_source.writer();

        try writer.writeAll(
            \\const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;
            \\
            \\
        );

        for (tests) |test_case, i| {
            var djot_lines = std.mem.split(u8, test_case.djot, "\n");
            var html_lines = std.mem.split(u8, test_case.html, "\n");

            try writer.print("test \"html.{} {}\" {{\n", .{ std.zig.fmtEscapes(walk_entry.basename[0 .. walk_entry.basename.len - 5]), i });
            try writer.writeAll("    try testDjotToHtml(\n");
            while (djot_lines.next()) |line| {
                try writer.print("        \\\\{s}\n", .{line});
            }
            try writer.writeAll("    ,\n");
            while (html_lines.next()) |line| {
                try writer.print("        \\\\{s}\n", .{line});
            }
            try writer.writeAll("    );\n");
            try writer.writeAll("}\n\n");

            num_tests_converted += 1;
        }

        try out_dir.writeFile(output_filepath, zig_source.items);

        try test_index_zig_source.writer().print("_ = @import(\"test/{}\");\n", .{std.zig.fmtEscapes(output_filepath)});
    }

    try test_index_zig_source.writer().writeAll(
        \\}
        \\
        \\
    );

    try cwd.writeFile("src/html_tests.zig", test_index_zig_source.items);

    std.debug.print("Converted {} tests.\n", .{num_tests_converted});
}

const Test = struct {
    djot: []const u8,
    html: []const u8,
};

pub fn extractTests(allocator: std.mem.Allocator, test_file_contents: []const u8) ![]Test {
    const State = union(enum) {
        default,
        in_djot_section: u32,
        in_html_section: u32,
    };

    var tests = std.ArrayList(Test).init(allocator);
    defer tests.deinit();

    var state = State{ .default = {} };
    var num_tick_marks: usize = undefined;
    var line_iter = lines(test_file_contents);
    while (line_iter.next()) |line| {
        switch (state) {
            .default => {
                if (line.len() == 0) continue;

                if (isCodeBlock(line.text(test_file_contents))) |num_ticks| {
                    num_tick_marks = num_ticks;
                    state = .{ .in_djot_section = line.end };
                }
            },
            .in_djot_section => |djot_start| if (std.mem.eql(u8, ".\n", line.text(test_file_contents))) {
                const t = try tests.addOne();
                t.djot = test_file_contents[djot_start..line.start];
                state = .{ .in_html_section = line.end };
            },
            .in_html_section => |html_start| {
                if (isCodeBlock(line.text(test_file_contents))) |num_ticks| {
                    if (num_ticks != num_tick_marks) continue;
                    tests.items[tests.items.len - 1].html = test_file_contents[html_start..line.start];
                    state = .default;
                }
            },
        }
    }

    std.debug.assert(state == .default);

    return tests.toOwnedSlice();
}

fn isCodeBlock(text: []const u8) ?usize {
    for (text) |c, i| {
        switch (c) {
            '`' => {},
            '\n' => return if (i >= 3) i else null,
            else => return null,
        }
    }
    return text.len;
}

const Loc = struct {
    start: u32,
    end: u32,

    pub fn text(this: @This(), buffer: []const u8) []const u8 {
        return buffer[this.start..this.end];
    }

    pub fn len(this: @This()) u32 {
        return this.end - this.start;
    }
};

const LineIter = struct {
    buffer: []const u8,
    index: usize,

    fn next(this: *@This()) ?Loc {
        if (this.index >= this.buffer.len) return null;

        const start = this.index;
        while (this.index < this.buffer.len and this.buffer[this.index] != '\n') : (this.index += 1) {}
        this.index += 1;
        return Loc{
            .start = @intCast(u32, start),
            .end = @intCast(u32, this.index),
        };
    }
};

fn lines(source: []const u8) LineIter {
    return LineIter{
        .buffer = source,
        .index = 0,
    };
}
