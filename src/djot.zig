const std = @import("std");

pub fn toHtml(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const events = try parse(allocator, source);
    defer allocator.free(events);

    var html = std.ArrayList(u8).init(allocator);
    defer html.deinit();
    for (events) |event| {
        switch (event) {
            .text => |t| try html.appendSlice(t),
            .newline => try html.appendSlice("\n"),
            .start_paragraph => try html.appendSlice("<p>"),
            .close_paragraph => try html.appendSlice("</p>\n"),
            .start_inline_code => try html.appendSlice("<code>"),
            .close_inline_code => try html.appendSlice("</code>"),
        }
    }

    return html.toOwnedSlice();
}

pub const Event = union(enum) {
    newline,
    text: []const u8,

    start_inline_code: []const u8,
    close_inline_code: []const u8,

    start_paragraph,
    close_paragraph,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ![]Event {
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    var pos: usize = 0;
    while (true) {
        if (try parseParagraph(allocator, source, pos)) |paragraph| {
            defer allocator.free(paragraph.events);
            try events.append(.start_paragraph);
            try events.appendSlice(paragraph.events);
            try events.append(.close_paragraph);
            pos = paragraph.end_pos;
            continue;
        }
        const tok = nextToken(source, pos);
        switch (tok.kind) {
            .double_newline => {},
            .eof => break,
            else => return error.TODO,
        }
        pos = tok.end;
    }

    return events.toOwnedSlice();
}

const Paragraph = struct {
    events: []Event,
    end_pos: usize,
};

fn parseParagraph(allocator: std.mem.Allocator, source: []const u8, start_pos: usize) !?Paragraph {
    var pos = start_pos;
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    switch (nextToken(source, start_pos).kind) {
        .eof, .double_newline => return null,
        else => {},
    }

    var in_attr = false;
    var in_comment = false;
    var style_code: ?[]const u8 = null;

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
            .single_newline => if (style_code != null) {
                try events.append(.newline);
            },
            .text => {
                try events.append(.{ .text = source[tok.start..tok.end] });
            },
            .curly_brace_open => in_attr = true,
            .curly_brace_close => in_attr = false,
            .percent => if (in_attr) {
                in_comment = true;
            },
            .ticks => {
                if (style_code) |opener| {
                    if (std.mem.eql(u8, source[tok.start..tok.end], opener)) {
                        try events.append(.{ .close_inline_code = source[tok.start..tok.end] });
                        style_code = null;
                    } else {
                        try events.append(.{ .text = source[tok.start..tok.end] });
                    }
                } else {
                    style_code = source[tok.start..tok.end];
                    try events.append(.{ .start_inline_code = source[tok.start..tok.end] });
                }
            },
            .double_newline, .eof => break,
        }
        pos = tok.end;
    }
    if (style_code) |opener| {
        while (events.items.len > 0 and events.items[events.items.len - 1] == .newline) {
            _ = events.pop();
        }
        try events.append(.{ .close_inline_code = opener });
    }

    return Paragraph{
        .events = events.toOwnedSlice(),
        .end_pos = pos,
    };
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
        ticks,
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
        ticks,
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
                '`' => {
                    res.kind = .ticks;
                    i += 1;
                    res.end = i;
                    state = .ticks;
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
                '{',
                '\n',
                '}',
                '%',
                '`',
                => break,
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
            .ticks => switch (source[i]) {
                '`' => {
                    i += 1;
                    res.end = i;
                },
                else => break,
            },
        }
    }
    return res;
}
