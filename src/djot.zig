const std = @import("std");

pub fn toHtml(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const events = try parse(allocator, source);
    defer allocator.free(events);

    var html = std.ArrayList(u8).init(allocator);
    defer html.deinit();
    for (events) |event| {
        switch (event) {
            .text => |t| try html.appendSlice(t),
            .start_paragraph => try html.appendSlice("<p>"),
            .close_paragraph => try html.appendSlice("</p>\n"),
        }
    }

    return html.toOwnedSlice();
}

pub const Event = union(enum) {
    text: []const u8,

    start_paragraph,
    close_paragraph,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ![]Event {
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    try events.append(.start_paragraph);
    var pos: usize = 0;
    while (true) {
        const tok = nextToken(source, pos);
        switch (tok.kind) {
            .text => {
                try events.append(.{ .text = std.mem.trim(u8, source[tok.start..tok.end], "\n") });
            },
            .eof => break,
        }
        pos = tok.end;
    }
    try events.append(.close_paragraph);

    return events.toOwnedSlice();
}

pub const Token = struct {
    start: usize,
    end: usize,
    kind: Kind,

    pub const Kind = enum {
        text,
        eof,
    };
};

pub fn nextToken(source: []const u8, pos: usize) Token {
    const State = enum {
        default,
        text,
        curly_brace_open,
        comment,
        comment_percent,
    };

    var res = Token{
        .start = pos,
        .end = undefined,
        .kind = .eof,
    };
    var state = State.default;
    var i = pos;
    while (i < source.len) {
        switch (state) {
            .default => switch (source[i]) {
                '{' => {
                    res.kind = .text;
                    i += 1;
                    res.end = i;
                    state = .curly_brace_open;
                },
                else => {
                    res.kind = .text;
                    i += 1;
                    res.end = i;
                },
            },
            .curly_brace_open => switch (source[i]) {
                '%' => {
                    i += 1;
                    state = .comment;
                },
                else => {
                    res.kind = .text;
                    i += 1;
                    res.end = i;
                },
            },
            .comment => {
                if (source[i] == '%') state = .comment_percent;
                i += 1;
            },
            .comment_percent => {
                if (source[i] == '}') {
                    i += 1;
                    res.start = i;
                    res.kind = .eof;
                    state = .default;
                } else {
                    state = .comment;
                }
            },
            .text => switch (source[i]) {
                '{' => break,
                else => {
                    res.kind = .text;
                    i += 1;
                    res.end = i;
                },
            },
        }
    }
    return res;
}
