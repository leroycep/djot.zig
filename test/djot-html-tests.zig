const std = @import("std");
const djot = @import("djot");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    const cwd = std.fs.cwd();
    const test_files = args[1..];
    const test_sources = try arena.allocator().alloc([]const u8, test_files.len);
    for (test_files) |test_filepath, i| {
        test_sources[i] = try cwd.readFileAlloc(arena.allocator(), test_filepath, 50 * 1024);
    }

    var tests = std.StringArrayHashMap([]Test).init(arena.allocator());
    for (test_sources) |source, i| {
        const old_value = try tests.fetchPut(test_files[i], try extractTests(arena.allocator(), source));
        if (old_value != null) {
            std.debug.print("test file \"{}\" specified multiple times!\n", .{std.zig.fmtEscapes(test_files[0])});
        }
    }

    const PassFail = struct {
        pass: usize,
        fail: usize,
    };

    // Number of tests passed or failed for each file
    var tests_pass_fail = std.StringArrayHashMap(PassFail).init(arena.allocator());

    var test_cases_file_iter = tests.iterator();
    while (test_cases_file_iter.next()) |file_entry| {
        var num = PassFail{
            .pass = 0,
            .fail = 0,
        };
        for (file_entry.value_ptr.*) |test_case, i| {
            var test_allocator = std.heap.GeneralPurposeAllocator(.{}){
                .backing_allocator = gpa.allocator(),
            };
            if (testDjotToHtml(test_allocator.allocator(), test_case)) {
                num.pass += 1;
            } else |err| {
                num.fail += 1;
                std.debug.print("test {} failed: {}\n```\n{s}\n```\n\n", .{ i, err, test_case.djot });
            }
            if (test_allocator.deinit()) {
                std.debug.print("test {} leaked memory\n\n", .{i});
            }
        }
        try tests_pass_fail.putNoClobber(file_entry.key_ptr.*, num);
    }

    var total = PassFail{
        .pass = 0,
        .fail = 0,
    };

    var pass_fail_iter = tests_pass_fail.iterator();
    while (pass_fail_iter.next()) |file_entry| {
        total.pass += file_entry.value_ptr.pass;
        total.fail += file_entry.value_ptr.fail;
        std.debug.print("[{: >2}/{: >2}/{: >2}] {s}\n", .{
            file_entry.value_ptr.pass,
            file_entry.value_ptr.fail,
            file_entry.value_ptr.pass + file_entry.value_ptr.fail,
            file_entry.key_ptr.*,
        });
    }

    std.debug.print(
        \\Ran {} tests.
        \\{} tests passed.
        \\{} tests failed.
    , .{ total.pass + total.fail, total.pass, total.fail });
}

pub fn testDjotToHtml(allocator: std.mem.Allocator, test_case: Test) !void {
    const html = try djot.toHtml(allocator, test_case.djot);
    defer allocator.free(html);
    try std.testing.expectEqualStrings(test_case.html, html);
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
