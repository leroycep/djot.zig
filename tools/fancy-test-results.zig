const std = @import("std");
const bolt = @import("bolt");
const html = @import("html");

pub fn main() !void {
    // 1. get arguments for running test command
    // 2. run command and get stderr
    // 3. split stderr by test and final test results
    //   - each test starts with regex: `^\d+/\d+` (example: `235/235 test.html.verbatim 6... OK`)
    //   - tests results: `77 passed; 0 skipped; 158 failed.`
    // 4. Generate an html file and put it in "zig-out/test-results.html"

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const res = try std.ChildProcess.exec(.{
        .allocator = gpa.allocator(),
        .argv = args[1..],
        .max_output_bytes = 50 * 1024 * 1024,
    });
    defer {
        gpa.allocator().free(res.stdout);
        gpa.allocator().free(res.stderr);
    }

    const test_cases = try parseTestCases(gpa.allocator(), res.stderr);
    defer {
        gpa.allocator().free(test_cases.other);
        gpa.allocator().free(test_cases.passed);
    }

    var html_contents = std.ArrayList(u8).init(gpa.allocator());
    defer html_contents.deinit();

    const out = html_contents.writer();

    try out.print("<h2>Pass/Fail Total</h2>\n", .{});
    try out.print("<table>\n", .{});
    try out.print("<tr><td>{s}</td><td>{}</td></tr>\n", .{ "passed", test_cases.total.passed });
    try out.print("<tr><td>{s}</td><td>{}</td></tr>\n", .{ "skipped", test_cases.total.skipped });
    try out.print("<tr><td>{s}</td><td>{}</td></tr>\n", .{ "failed", test_cases.total.failed });
    try out.print("</table>\n", .{});

    try out.print("<h2>Failing Test Cases</h2>\n", .{});
    for (test_cases.other) |test_case| {
        try out.print("<h3 id=\"", .{});
        try writeNameAsId(test_case.name, out);
        try out.print("\"><a href=\"#", .{});
        try writeNameAsId(test_case.name, out);
        try out.print("\">{}. {s}</a></h3>\n", .{ test_case.number, html.fmtEscapes(test_case.name) });
        switch (test_case.result) {
            .ok => try out.print("OK\n", .{}),
            .err => |text| try out.print("<pre><code>{}</code></pre>\n", .{html.fmtEscapes(text)}),
        }
    }

    try out.print("<h2>Passing Test Cases</h2>\n", .{});
    for (test_cases.passed) |test_case| {
        try out.print("<h3>{}. {s}</h3>\n", .{ test_case.number, html.fmtEscapes(test_case.name) });
        switch (test_case.result) {
            .ok => try out.print("OK\n", .{}),
            .err => |text| try out.print("<pre><code>{}</code></pre>\n", .{html.fmtEscapes(text)}),
        }
    }

    try std.fs.cwd().writeFile("zig-out/test-results.html", html_contents.items);
}

pub fn writeNameAsId(name: []const u8, writer: anytype) !void {
    for (name) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => try writer.writeByte(c),

            '.',
            ' ',
            => try writer.writeByte('-'),

            else => {},
        }
    }
}

const TestCases = struct {
    total: PassFailTotal,
    other: []const TestCase,
    passed: []const TestCase,
};

fn parseTestCases(allocator: std.mem.Allocator, source: []const u8) !TestCases {
    var other = std.ArrayList(TestCase).init(allocator);
    defer other.deinit();

    var passed = std.ArrayList(TestCase).init(allocator);
    defer passed.deinit();

    var cursor = Read{ .source = source, .index = 0 };

    while (true) {
        if (parsePassFailTotals(&cursor)) |total| {
            return TestCases{
                .total = total,
                .other = other.toOwnedSlice(),
                .passed = passed.toOwnedSlice(),
            };
        }
        if (parseTestCase(&cursor)) |test_case| {
            switch (test_case.result) {
                .ok => try passed.append(test_case),
                .err => try other.append(test_case),
            }
            continue;
        }
        std.debug.print("\nHello: {s}\n", .{cursor.source[cursor.index..]});
        return error.Unknown;
    }
}

const Read = bolt.Read(u8, usize);

const TestCase = struct {
    number: u64,
    name: []const u8,
    result: Result,

    const Result = union(enum) {
        ok,
        err: []const u8,
    };
};

fn parseTestCase(parent: *Read) ?TestCase {
    var cursor = parent.*;

    var header = parseTestCaseHeader(&cursor) orelse return null;
    var result_start = cursor.index;

    if (cursor.expectString("OK\n")) |_| {
        parent.* = cursor;
        return TestCase{
            .number = header.number,
            .name = header.name,
            .result = .ok,
        };
    }

    while (cursor.next()) |_| {
        if (cursor.expect('\n')) |_| {
            var lookahead = cursor;
            if (parseTestCaseHeader(&lookahead)) |_| {
                break;
            }
            if (parsePassFailTotals(&lookahead)) |_| {
                break;
            }
        }
    }
    const result_end = cursor.index;

    parent.* = cursor;
    return TestCase{
        .number = header.number,
        .name = header.name,
        .result = .{ .err = cursor.source[result_start..result_end] },
    };
}

const TestCaseHeader = struct {
    number: u64,
    name: []const u8,
};

fn parseTestCaseHeader(parent: *Read) ?TestCaseHeader {
    var cursor = parent.*;

    const number = parseNumber(&cursor) orelse return null;
    _ = cursor.expect('/') orelse return null;
    _ = parseNumber(&cursor) orelse return null;
    _ = cursor.expect(' ') orelse return null;

    const name_start = cursor.index;
    var name_end = cursor.index;
    while (cursor.index < cursor.source.len) : (cursor.index += 1) {
        if (cursor.expectString("... ")) |_| {
            break;
        }
        name_end = cursor.index + 1;
    }

    parent.* = cursor;
    return TestCaseHeader{
        .number = number,
        .name = cursor.source[name_start..name_end],
    };
}

const PassFailTotal = struct {
    passed: u64,
    skipped: u64,
    failed: u64,
};

fn parsePassFailTotals(parent: *Read) ?PassFailTotal {
    var cursor = parent.*;

    const passed = parseNumber(&cursor) orelse return null;
    _ = cursor.expectString(" passed; ") orelse return null;

    const skipped = parseNumber(&cursor) orelse return null;
    _ = cursor.expectString(" skipped; ") orelse return null;

    const failed = parseNumber(&cursor) orelse return null;
    _ = cursor.expectString(" failed.") orelse return null;

    parent.* = cursor;
    return PassFailTotal{
        .passed = passed,
        .skipped = skipped,
        .failed = failed,
    };
}

fn parseNumber(parent: *Read) ?u64 {
    var cursor = parent.*;

    const start = cursor.expectInRange('0', '9') orelse return null;
    while (cursor.expectInRange('0', '9')) |_| {}

    const text = parent.source[start..cursor.index];
    const number = std.fmt.parseInt(u64, text, 10) catch return null;

    parent.* = cursor;
    return number;
}

test {
    var cursor = Read{
        .source = "77 passed; 0 skipped; 158 failed.",
        .index = 0,
    };
    try std.testing.expectEqual(@as(?PassFailTotal, PassFailTotal{
        .passed = 77,
        .skipped = 0,
        .failed = 158,
    }), parsePassFailTotals(&cursor));
}

test {
    var cursor = Read{
        .source = 
        \\235/235 test.html.verbatim 6... OK
        \\77 passed; 0 skipped; 158 failed.
        ,
        .index = 0,
    };

    const case = parseTestCase(&cursor) orelse return error.TestExpectedNotNull;
    try std.testing.expectEqual(@as(u64, 235), case.number);
    try std.testing.expectEqualStrings("test.html.verbatim 6", case.name);
    try std.testing.expectEqual(TestCase.Result.ok, case.result);

    try std.testing.expectEqual(@as(?TestCase, null), parseTestCase(&cursor));

    try std.testing.expectEqual(@as(?PassFailTotal, PassFailTotal{
        .passed = 77,
        .skipped = 0,
        .failed = 158,
    }), parsePassFailTotals(&cursor));
}
