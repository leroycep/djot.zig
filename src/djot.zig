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

    var in_attr = false;
    var in_comment = false;

    var pos: usize = 0;
    while (true) {
        const tok = nextToken(source, pos);
        if (in_comment) {
            if (tok.kind == .percent) {
                in_comment = false;
            }
            pos = tok.end;
            continue;
        }
        switch (tok.kind) {
            .single_newline => {},
            .text => {
                try events.append(.{ .text = source[tok.start..tok.end] });
            },
            .curly_brace_open => in_attr = true,
            .curly_brace_close => in_attr = false,
            .percent => if (in_attr) {
                in_comment = true;
            },
            .double_newline => {
                try events.append(.close_paragraph);
                try events.append(.start_paragraph);
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
        double_newline,
        single_newline,
        curly_brace_open,
        curly_brace_close,
        percent,
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
        newline,
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
                    res.kind = .curly_brace_open;
                    i += 1;
                    res.end = i;
                    state = .curly_brace_open;
                },
                '}' => {
                    res.kind = .curly_brace_close;
                    i += 1;
                    res.end = i;
                    break;
                },
                '%' => {
                    res.kind = .percent;
                    i += 1;
                    res.end = i;
                    break;
                },
                '\n' => {
                    res.kind = .single_newline;
                    i += 1;
                    res.end = i;
                    state = .newline;
                },
                else => state = .text,
            },
            .curly_brace_open => switch (source[i]) {
                '%' => {
                    i += 1;
                    state = .comment;
                },
                else => break,
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
                '{', '\n', '}', '%' => break,
                else => {
                    res.kind = .text;
                    i += 1;
                    res.end = i;
                },
            },
            .newline => switch (source[i]) {
                '\n' => {
                    res.kind = .double_newline;
                    i += 1;
                    res.end = i;
                    break;
                },
                else => break,
            },
        }
    }
    return res;
}
