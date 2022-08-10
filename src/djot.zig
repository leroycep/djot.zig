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
            .start_link => |url| try html.writer().print("<a href=\"{}\">", .{std.zig.fmtEscapes(url)}),
            .close_link => try html.appendSlice("</a>"),
            .start_image_link => try html.writer().print("<img alt=\"", .{}),
            .close_image_link => |url| try html.writer().print("\" src=\"{}\">", .{std.zig.fmtEscapes(url)}),
            .autolink => |url| try html.writer().print("<a href=\"{}\">{s}</a>", .{ std.zig.fmtEscapes(url), url }),
            .autolink_email => |email| try html.writer().print("<a href=\"mailto:{}\">{s}</a>", .{ std.zig.fmtEscapes(email), email }),
        }
    }

    return html.toOwnedSlice();
}

pub const Event = union(enum) {
    newline,
    text: []const u8,
    verbatim_inline: []const u8,

    /// Data is URL
    autolink: []const u8,

    /// Data is email address
    autolink_email: []const u8,

    /// Data is URL
    start_link: []const u8,
    close_link,

    /// Data is URL
    start_image_link: []const u8,
    close_image_link: []const u8,

    start_paragraph,
    close_paragraph,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ![]Event {
    var token_starts = std.ArrayList(u32).init(allocator);
    var token_kinds = std.ArrayList(Token.Kind).init(allocator);
    defer {
        token_kinds.deinit();
        token_starts.deinit();
    }

    {
        var pos: usize = 0;
        while (true) {
            const tok = nextToken(source, pos);
            try token_starts.append(@intCast(u32, tok.start));
            try token_kinds.append(tok.kind);
            if (tok.kind == .eof) {
                break;
            }
            pos = tok.end;
        }
    }

    var cursor = Cursor{
        .source = source,
        .token_starts = token_starts.items,
        .token_kinds = token_kinds.items,
        .token_index = 0,
    };

    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();
    while (true) {
        if (try parseParagraph(allocator, cursor)) |paragraph| {
            defer allocator.free(paragraph.events);
            try events.append(.start_paragraph);
            try events.appendSlice(paragraph.events);
            try events.append(.close_paragraph);
            cursor.token_index = paragraph.end_index;
            continue;
        }
        switch (cursor.token_kinds[cursor.token_index]) {
            .double_newline => cursor.token_index += 1,
            .eof => break,
            else => return error.TODO,
        }
    }

    return events.toOwnedSlice();
}

const Parse = struct {
    events: []Event,
    end_index: Cursor.TokenIndex,
};

fn parseParagraph(allocator: std.mem.Allocator, start_cursor: Cursor) !?Parse {
    var cursor = start_cursor;
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    switch (cursor.token_kinds[cursor.token_index]) {
        .eof, .double_newline => return null,
        else => {},
    }

    var in_attr = false;

    while (true) {
        switch (cursor.token_kinds[cursor.token_index]) {
            .text,
            .spaces,
            => try events.append(.{ .text = cursor.tokenText(cursor.token_index) }),

            .single_newline => switch (cursor.token_kinds[cursor.token_index + 1]) {
                .single_newline => unreachable,

                .eof,
                .double_newline,
                => {},

                else => try events.append(.{ .text = cursor.tokenText(cursor.token_index) }),
            },

            .autolink => {
                if (try parseAutoLink(cursor)) |autolink| {
                    try events.append(autolink.event);
                    cursor.token_index = autolink.end_index;
                    continue;
                } else {
                    return error.AutoLinkWasntAutoLink;
                }
            },

            .square_brace_close => {},
            .parenthesis_open => {},
            .parenthesis_close => {},
            .exclaimation => {
                if (try parseImageLink(allocator, cursor)) |link| {
                    defer allocator.free(link.desc);
                    try events.append(.{ .start_image_link = link.url });
                    try events.appendSlice(link.desc);
                    try events.append(.{ .close_image_link = link.url });
                    cursor.token_index = link.end_index;
                    continue;
                } else {
                    try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
                }
            },
            .square_brace_open => {
                if (try parseLink(allocator, cursor)) |link| {
                    defer allocator.free(link.desc);
                    try events.append(.{ .start_link = link.url });
                    try events.appendSlice(link.desc);
                    try events.append(.close_link);
                    cursor.token_index = link.end_index;
                    continue;
                } else {
                    try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
                }
            },

            .curly_brace_open => in_attr = true,
            .curly_brace_close => in_attr = false,
            .percent => if (in_attr) {
                _ = cursor.until(.percent) orelse return error.UnclosedComment;
            },
            .ticks => {
                if (parseVerbatim(cursor)) |verbatim| {
                    try events.append(.{ .verbatim_inline = verbatim.text });
                    cursor.token_index = verbatim.end_index;
                    continue;
                } else {
                    try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
                }
            },
            .double_newline, .eof => break,
        }
        cursor.token_index += 1;
    }

    return Parse{
        .events = events.toOwnedSlice(),
        .end_index = cursor.token_index,
    };
}

fn parseImageLink(allocator: std.mem.Allocator, start_cursor: Cursor) anyerror!?ParseLink {
    var cursor = start_cursor;

    // Parse alt text
    _ = cursor.eat(.exclaimation) orelse return null;
    const link = (try parseLink(allocator, cursor)) orelse return null;

    return ParseLink{
        .url = link.url,
        .desc = link.desc,
        .end_index = link.end_index,
    };
}

const ParseLink = struct {
    url: []const u8,
    desc: []Event,
    end_index: Cursor.TokenIndex,
};

fn parseLink(allocator: std.mem.Allocator, start_cursor: Cursor) anyerror!?ParseLink {
    var cursor = start_cursor;

    // Parse hyperlink text
    const desc = (try parseLinkText(allocator, cursor)) orelse return null;
    cursor.token_index = desc.end_index;

    var events = std.ArrayList(Event).fromOwnedSlice(allocator, desc.events);
    defer events.deinit();

    // Parse hyperlink URL
    _ = cursor.eat(.parenthesis_open) orelse return null;
    const url_token_range = cursor.until(.parenthesis_close) orelse return null;

    const url_start = cursor.token_starts[url_token_range[0]];
    const url_end = cursor.tokenAt(url_token_range[1] - 1).end;

    return ParseLink{
        .url = cursor.source[url_start..url_end],
        .desc = events.toOwnedSlice(),
        .end_index = cursor.token_index,
    };
}

fn parseLinkText(allocator: std.mem.Allocator, start_cursor: Cursor) anyerror!?Parse {
    var cursor = start_cursor;
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    _ = cursor.eat(.square_brace_open) orelse return null;

    switch (cursor.token_kinds[cursor.token_index]) {
        .eof, .double_newline => return null,
        else => {},
    }

    var in_attr = false;

    while (true) {
        switch (cursor.token_kinds[cursor.token_index]) {
            .double_newline,
            .eof,
            => break,

            .square_brace_close => {
                cursor.token_index += 1;
                break;
            },

            .text,
            .spaces,
            => try events.append(.{ .text = cursor.tokenText(cursor.token_index) }),

            .single_newline => switch (cursor.token_kinds[cursor.token_index + 1]) {
                .single_newline => unreachable,

                .eof,
                .double_newline,
                => {},

                else => try events.append(.{ .text = cursor.tokenText(cursor.token_index) }),
            },

            .autolink => {
                if (try parseAutoLink(cursor)) |autolink| {
                    try events.append(autolink.event);
                    cursor.token_index = autolink.end_index;
                    continue;
                } else {
                    return error.AutoLinkWasntAutoLink;
                }
            },

            .parenthesis_open => {},
            .parenthesis_close => {},
            .exclaimation => {
                if (try parseImageLink(allocator, cursor)) |link| {
                    defer allocator.free(link.desc);
                    try events.append(.{ .start_image_link = link.url });
                    try events.appendSlice(link.desc);
                    try events.append(.{ .close_image_link = link.url });
                    cursor.token_index = link.end_index;
                    continue;
                } else {
                    try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
                }
            },
            .square_brace_open => {
                if (try parseLink(allocator, cursor)) |link| {
                    defer allocator.free(link.desc);
                    try events.append(.{ .start_link = link.url });
                    try events.appendSlice(link.desc);
                    try events.append(.close_link);
                    cursor.token_index = link.end_index;
                    continue;
                } else {
                    try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
                }
            },

            .curly_brace_open => in_attr = true,
            .curly_brace_close => in_attr = false,
            .percent => if (in_attr) {
                _ = cursor.until(.percent) orelse return error.UnclosedComment;
            },
            .ticks => {
                if (parseVerbatim(cursor)) |verbatim| {
                    try events.append(.{ .verbatim_inline = verbatim.text });
                    cursor.token_index = verbatim.end_index;
                    continue;
                } else {
                    try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
                }
            },
        }
        cursor.token_index += 1;
    }

    return Parse{
        .events = events.toOwnedSlice(),
        .end_index = cursor.token_index,
    };
}

const ParseAutoLink = struct {
    event: Event,
    end_index: u32,
};

fn parseAutoLink(start_cursor: Cursor) !?ParseAutoLink {
    var cursor = start_cursor;

    const tok_i = cursor.eat(.autolink) orelse return null;

    const autolink_text = cursor.tokenText(tok_i);
    const link_text = autolink_text[1 .. autolink_text.len - 1];

    if (std.mem.containsAtLeast(u8, link_text, 1, "@")) {
        return ParseAutoLink{
            .event = .{ .autolink_email = link_text },
            .end_index = cursor.token_index,
        };
    }

    return ParseAutoLink{
        .event = .{ .autolink = link_text },
        .end_index = cursor.token_index,
    };
}

const Verbatim = struct {
    text: []const u8,
    end_index: Cursor.TokenIndex,
};

fn parseVerbatim(start_cursor: Cursor) ?Verbatim {
    var cursor = start_cursor;

    const opener_tok_i = cursor.eat(.ticks) orelse return null;
    const opener_text = cursor.tokenText(opener_tok_i);

    const content_start = cursor.token_index;

    // Find end of verbatim and get list of tokens that are easier to manipulate than raw `nextToken` calls
    var content_end = content_start;
    while (content_end < cursor.token_kinds.len) : (content_end += 1) {
        if (cursor.token_kinds[content_end] == .eof) {
            cursor.token_index = content_end;
            break;
        }
        if (std.mem.eql(u8, cursor.tokenText(content_end), opener_text)) {
            cursor.token_index = content_end + 1;
            break;
        }
    } else unreachable;

    // Check if content begins or ends with a tick
    const content_has_ticks = blk: {
        if (cursor.token_kinds[content_start] == .ticks) break :blk true;
        if (cursor.token_kinds[content_start] == .spaces and cursor.token_kinds[content_start + 1] == .ticks) break :blk true;

        if (cursor.token_kinds[content_end - 1] == .ticks) break :blk true;
        if (cursor.token_kinds[content_end - 1] == .spaces and cursor.token_kinds[content_end - 2] == .ticks) break :blk true;

        break :blk false;
    };

    const span_starts_with_spaces = content_end - content_start > 0 and cursor.token_kinds[content_start] == .spaces;
    const span_ends_with_spaces = content_end - content_start > 1 and cursor.token_kinds[content_end - 1] == .spaces;

    const verbatim_start = if (content_has_ticks and span_starts_with_spaces) cursor.token_starts[content_start] + 1 else cursor.token_starts[content_start];
    const verbatim_end = if (content_has_ticks and span_ends_with_spaces) cursor.tokenAt(content_end - 1).end - 1 else cursor.tokenAt(content_end - 1).end;

    return Verbatim{
        .text = std.mem.trimRight(u8, cursor.source[verbatim_start..verbatim_end], "\n"),
        .end_index = cursor.token_index,
    };
}

pub const Cursor = struct {
    source: []const u8,
    token_kinds: []const Token.Kind,
    token_starts: []const u32,
    token_index: u32,

    const TokenIndex = u32;

    /// Only returns the token if the expected_kind matches
    pub fn eat(this: *@This(), expected_kind: Token.Kind) ?TokenIndex {
        if (this.token_index >= this.token_kinds.len) return null;
        if (this.token_kinds[this.token_index] == expected_kind) {
            defer this.token_index += 1;
            return this.token_index;
        }
        return null;
    }

    /// Returns a range containing all tokens between the current index and expected token kind.
    ///
    /// - Includes the Token with the expected kind
    /// - If expected kind is not found, returns null.
    pub fn until(this: *@This(), expected_kind: Token.Kind) ?[2]TokenIndex {
        const start = this.token_index;
        while (this.token_index < this.token_kinds.len - 1 and this.token_kinds[this.token_index] != expected_kind) : (this.token_index += 1) {}
        if (this.token_kinds[this.token_index] != expected_kind) {
            return null;
        }
        return [2]TokenIndex{ start, this.token_index };
    }

    pub fn next(this: *@This()) TokenIndex {
        if (this.token_index >= this.token_kinds.len) {
            const last = @intCast(u32, this.token_kinds.len - 1);
            std.debug.assert(this.token_kinds[last] == .eof);
            return last;
        }
        defer this.token_index += 1;
        return this.token_index;
    }

    pub fn tokenAt(this: @This(), index: TokenIndex) Token {
        if (index >= this.token_kinds.len) {
            const last = this.token_kinds.len - 1;
            std.debug.assert(this.token_kinds[last] == .eof);
            return nextToken(this.source, this.token_starts[last]);
        }
        return nextToken(this.source, this.token_starts[index]);
    }

    pub fn tokenText(this: @This(), index: TokenIndex) []const u8 {
        if (index >= this.token_kinds.len) {
            return this.source[this.source.len..];
        }
        const tok = nextToken(this.source, this.token_starts[index]);
        return this.source[tok.start..tok.end];
    }

    pub fn end(this: @This()) usize {
        if (this.token_index >= this.token_kinds.len) {
            return this.source.len;
        }
        const tok = nextToken(this.source, this.token_starts[this.token_index]);
        return tok.end;
    }
};

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
        autolink,

        exclaimation,
        square_brace_open,
        square_brace_close,
        parenthesis_open,
        parenthesis_close,

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
        autolink,
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
                '}',
                '%',
                '!',
                '[',
                ']',
                '(',
                ')',
                => {
                    res.kind = switch (source[i]) {
                        '}' => .curly_brace_close,
                        '%' => .percent,
                        '!' => .exclaimation,
                        '[' => .square_brace_open,
                        ']' => .square_brace_close,
                        '(' => .parenthesis_open,
                        ')' => .parenthesis_close,
                        else => unreachable,
                    };
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
                '<' => {
                    res.kind = .autolink;
                    i += 1;
                    res.end = i;
                    state = .autolink;
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
                '!',
                '[',
                ']',
                '(',
                ')',
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
            .autolink => switch (source[i]) {
                ' ',
                '\n',
                '{',
                '}',
                '`',
                => break,
                '>' => {
                    i += 1;
                    res.end = i;
                    break;
                },
                else => {
                    i += 1;
                },
            },
        }
    }
    return res;
}
