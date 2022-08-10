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
            .verbatim_inline => |verbatim| {
                try html.appendSlice("<code>");
                try html.appendSlice(verbatim);
                try html.appendSlice("</code>");
            },
        }
    }

    return html.toOwnedSlice();
}

pub const Event = union(enum) {
    newline,
    text: []const u8,
    verbatim_inline: []const u8,

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

const Parse = struct {
    events: []Event,
    end_pos: usize,
};

fn parseParagraph(allocator: std.mem.Allocator, source: []const u8, start_pos: usize) !?Parse {
    var pos = start_pos;
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    switch (nextToken(source, start_pos).kind) {
        .eof, .double_newline => return null,
        else => {},
    }

    var in_attr = false;
    var in_comment = false;

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
            .text,
            .spaces,
            => try events.append(.{ .text = source[tok.start..tok.end] }),
            .curly_brace_open => in_attr = true,
            .curly_brace_close => in_attr = false,
            .percent => if (in_attr) {
                in_comment = true;
            },
            .ticks => {
                if (try parseVerbatim(allocator, source, pos)) |verbatim| {
                    try events.append(.{ .verbatim_inline = verbatim.text });
                    pos = verbatim.end_pos;
                    continue;
                } else {
                    try events.append(.{ .text = source[tok.start..tok.end] });
                }
            },
            .double_newline, .eof => break,
        }
        pos = tok.end;
    }

    return Parse{
        .events = events.toOwnedSlice(),
        .end_pos = pos,
    };
}

const Verbatim = struct {
    text: []const u8,
    end_pos: usize,
};

fn parseVerbatim(allocator: std.mem.Allocator, source: []const u8, start_pos: usize) !?Verbatim {
    var pos = start_pos;
    const opener = switch (nextToken(source, start_pos).kind) {
        .ticks => nextToken(source, start_pos),
        else => return null,
    };

    pos = opener.end;

    // Find end of verbatim and get list of tokens that are easier to manipulate than raw `nextToken` calls
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();
    while (true) {
        const tok = nextToken(source, pos);

        if (tok.kind == .eof) {
            break;
        }
        if (std.mem.eql(u8, source[tok.start..tok.end], source[opener.start..opener.end])) {
            pos = tok.end;
            break;
        }

        try tokens.append(tok);
        pos = tok.end;
    }

    // Check if content begins or ends with a tick
    const content_has_ticks = blk: {
        if (tokens.items.len > 0 and tokens.items[0].kind == .ticks) break :blk true;
        if (tokens.items.len > 1 and tokens.items[0].kind == .spaces and tokens.items[1].kind == .ticks) break :blk true;

        const end = tokens.items.len -| 1;
        if (tokens.items.len > 0 and tokens.items[end].kind == .ticks) break :blk true;
        if (tokens.items.len > 1 and tokens.items[end].kind == .spaces and tokens.items[end - 1].kind == .ticks) break :blk true;

        break :blk false;
    };

    const span_starts_with_spaces = tokens.items.len > 0 and tokens.items[0].kind == .spaces;
    const span_ends_with_spaces = tokens.items.len > 1 and tokens.items[tokens.items.len - 1].kind == .spaces;

    const verbatim_start = if (content_has_ticks and span_starts_with_spaces) tokens.items[0].start + 1 else tokens.items[0].start;
    const verbatim_end = if (content_has_ticks and span_ends_with_spaces) tokens.items[tokens.items.len - 1].end - 1 else tokens.items[tokens.items.len - 1].end;

    return Verbatim{
        .text = std.mem.trimRight(u8, source[verbatim_start..verbatim_end], "\n"),
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
        spaces,
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
        spaces,
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
                ' ' => {
                    res.kind = .spaces;
                    i += 1;
                    res.end = i;
                    state = .spaces;
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
            .spaces => switch (source[i]) {
                ' ' => {
                    i += 1;
                    res.end = i;
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
