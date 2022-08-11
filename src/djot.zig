const std = @import("std");

pub fn toHtml(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const events = try parse(allocator, source);
    defer parseFree(allocator, events);

    var html = std.ArrayList(u8).init(allocator);
    defer html.deinit();
    for (events) |event| {
        switch (event) {
            .text => |t| try html.appendSlice(t),
            .newline => try html.appendSlice("\n"),
            .character => |char| {
                const nbytes = try std.unicode.utf8CodepointSequenceLength(char);
                try html.appendNTimes(undefined, nbytes);
                const nbytes_written = try std.unicode.utf8Encode(char, html.items[html.items.len - nbytes ..]);
                std.debug.assert(nbytes_written == nbytes);
            },
            .start_paragraph => try html.appendSlice("<p>"),
            .close_paragraph => try html.appendSlice("</p>\n"),
            .start_strong => try html.appendSlice("<strong>"),
            .close_strong => try html.appendSlice("</strong>"),
            .verbatim_inline => |verbatim| {
                try html.appendSlice("<code>");
                try html.appendSlice(verbatim);
                try html.appendSlice("</code>");
            },
            .start_link => |url| try html.writer().print("<a href=\"{s}\">", .{url}),
            .close_link => try html.appendSlice("</a>"),
            .image => |link| try html.writer().print("<img alt=\"{}\" src=\"{}\">", .{ std.zig.fmtEscapes(link.alt), std.zig.fmtEscapes(link.src) }),
            .autolink => |url| try html.writer().print("<a href=\"{}\">{s}</a>", .{ std.zig.fmtEscapes(url), url }),
            .autolink_email => |email| try html.writer().print("<a href=\"mailto:{}\">{s}</a>", .{ std.zig.fmtEscapes(email), email }),
        }
    }

    return html.toOwnedSlice();
}

pub const Event = union(enum) {
    newline,
    character: u21,
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
    image: struct {
        /// Alt-Text
        alt: []const u8,

        /// URL pointing to image
        src: []const u8,
    },

    start_paragraph,
    close_paragraph,

    start_strong,
    close_strong,
};

/// The returned events must be freed with `parseFree`
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
    defer parseFree(allocator, events.toOwnedSlice());
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
            .double_newline => cursor.increment(),
            .eof => break,
            else => return error.TODO,
        }
    }

    return events.toOwnedSlice();
}

pub fn parseFree(allocator: std.mem.Allocator, events: []const Event) void {
    for (events) |event| {
        switch (event) {
            .image => |img| {
                allocator.free(img.alt);
                allocator.free(img.src);
            },
            .start_link => |url| {
                allocator.free(url);
            },
            else => {},
        }
    }
    allocator.free(events);
}

const Parse = struct {
    events: []Event,
    end_index: Cursor.TokenIndex,
};

fn parseParagraph(allocator: std.mem.Allocator, start_cursor: Cursor) !?Parse {
    var cursor = start_cursor;

    switch (cursor.token_kinds[cursor.token_index]) {
        .eof, .double_newline => return null,
        else => {},
    }

    var events = std.ArrayList(Event).init(allocator);
    defer parseFree(allocator, events.toOwnedSlice());

    var in_attr = false;

    while (true) {
        switch (cursor.token_kinds[cursor.token_index]) {
            .double_newline, .eof => break,

            .text,
            .spaces,
            .square_brace_close,
            .parenthesis_open,
            .parenthesis_close,
            => {},

            .escape => {
                try events.append(.{ .character = cursor.tokenText(cursor.token_index)[1..][0] });
                cursor.increment();
                continue;
            },

            .single_newline => switch (cursor.token_kinds[cursor.token_index + 1]) {
                .single_newline => unreachable,

                .eof,
                .double_newline,
                => {
                    cursor.increment();
                    continue;
                },

                else => {},
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

            .exclaimation => {
                if (try parseImageLink(allocator, cursor, null)) |link| {
                    try events.append(.{ .image = .{
                        .src = link.url,
                        .alt = link.alt_text,
                    } });
                    cursor.token_index = link.end_index;
                    continue;
                }
            },
            .square_brace_open => {
                if (try parseLink(allocator, cursor, null)) |link| {
                    defer allocator.free(link.desc);
                    try events.append(.{ .start_link = link.url });
                    try events.appendSlice(link.desc);
                    try events.append(.close_link);
                    cursor.token_index = link.end_index;
                    continue;
                }
            },

            .curly_brace_open => {
                in_attr = true;
                cursor.increment();
                continue;
            },
            .curly_brace_close => {
                in_attr = false;
                cursor.increment();
                continue;
            },
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
            .underscores,
            .asterisks,
            => {
                if (tokenCouldStartSpan(cursor, cursor.token_index)) {
                    const index = cursor.token_index;
                    cursor.increment();
                    if (try parseTextSpan(allocator, cursor, index, null)) |text_span| {
                        defer allocator.free(text_span.events);
                        try events.append(.start_strong);
                        try events.appendSlice(text_span.events);
                        try events.append(.close_strong);
                        cursor.token_index = text_span.end_index;
                        continue;
                    }
                    cursor.token_index -= 1;
                }
            },
        }
        try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
        cursor.increment();
    }

    return Parse{
        .events = events.toOwnedSlice(),
        .end_index = cursor.token_index,
    };
}

const ParseImageLink = struct {
    alt_text: []const u8,
    url: []const u8,
    end_index: Cursor.TokenIndex,
};

fn parseImageLink(allocator: std.mem.Allocator, start_cursor: Cursor, other_openers: ?*const PrevOpener) anyerror!?ParseImageLink {
    var cursor = start_cursor;

    // Parse alt text
    _ = cursor.eat(.exclaimation) orelse return null;
    const link = (try parseLink(allocator, cursor, other_openers)) orelse return null;
    defer parseFree(allocator, link.desc);

    return ParseImageLink{
        .alt_text = try eventsToAttributeText(allocator, link.desc),
        .url = link.url,
        .end_index = link.end_index,
    };
}

const ParseLink = struct {
    url: []const u8,
    desc: []Event,
    end_index: Cursor.TokenIndex,
};

fn parseLink(allocator: std.mem.Allocator, start_cursor: Cursor, other_openers: ?*const PrevOpener) anyerror!?ParseLink {
    var cursor = start_cursor;

    // Parse hyperlink text
    const desc_open = cursor.eat(.square_brace_open) orelse return null;
    const desc = (try parseTextSpan(allocator, cursor, desc_open, other_openers)) orelse return null;
    cursor.token_index = desc.end_index;

    var events = std.ArrayList(Event).fromOwnedSlice(allocator, desc.events);
    defer parseFree(allocator, events.toOwnedSlice());

    // Parse hyperlink URL
    const url_open = cursor.eat(.parenthesis_open) orelse return null;
    const url = (try parseTextSpan(allocator, cursor, url_open, other_openers)) orelse return null;
    cursor.token_index = url.end_index;
    defer parseFree(allocator, url.events);

    return ParseLink{
        .url = try eventsToAttributeText(allocator, url.events),
        .desc = events.toOwnedSlice(),
        .end_index = cursor.token_index,
    };
}

fn eventsToAttributeText(allocator: std.mem.Allocator, events: []const Event) ![]u8 {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();

    for (events) |event| {
        switch (event) {
            .text => |t| {
                // Remove any newlines
                var lines = std.mem.tokenize(u8, t, "\n");
                while (lines.next()) |line| {
                    try text.appendSlice(line);
                }
            },
            .character => |char| {
                const nbytes = try std.unicode.utf8CodepointSequenceLength(char);
                try text.appendNTimes(undefined, nbytes);
                const nbytes_written = try std.unicode.utf8Encode(char, text.items[text.items.len - nbytes ..]);
                std.debug.assert(nbytes_written == nbytes);
            },
            .verbatim_inline => |verbatim| try text.appendSlice(verbatim),

            .start_strong,
            .close_strong,
            => try text.appendSlice("*"),

            else => {},
        }
    }

    return text.toOwnedSlice();
}

fn parseTextSpan(allocator: std.mem.Allocator, start_cursor: Cursor, opener: Cursor.TokenIndex, prev_opener: ?*const PrevOpener) anyerror!?Parse {
    var cursor = start_cursor;

    var events = std.ArrayList(Event).init(allocator);
    defer parseFree(allocator, events.toOwnedSlice());

    var in_attr = false;

    text_span: while (true) {
        switch (cursor.token_kinds[cursor.token_index]) {
            .eof => return null,
            .double_newline => break,

            .text,
            .spaces,
            .parenthesis_open,
            => {},

            .escape => {
                try events.append(.{ .character = cursor.tokenText(cursor.token_index)[1..][0] });
                cursor.increment();
                continue;
            },

            .single_newline => switch (cursor.token_kinds[cursor.token_index + 1]) {
                .single_newline => unreachable,

                .eof,
                .double_newline,
                => {
                    cursor.increment();
                    continue;
                },

                else => {},
            },

            .autolink => if (try parseAutoLink(cursor)) |autolink| {
                try events.append(autolink.event);
                cursor.token_index = autolink.end_index;
                continue;
            } else {
                return error.AutoLinkWasntAutoLink;
            },

            .exclaimation => if (try parseImageLink(allocator, cursor, &.{ .prev = prev_opener, .opener = opener })) |link| {
                try events.append(.{ .image = .{
                    .src = link.url,
                    .alt = link.alt_text,
                } });
                cursor.token_index = link.end_index;
                continue;
            },

            .square_brace_open => if (try parseLink(allocator, cursor, &.{ .prev = prev_opener, .opener = opener })) |link| {
                defer allocator.free(link.desc);
                try events.append(.{ .start_link = link.url });
                try events.appendSlice(link.desc);
                try events.append(.close_link);
                cursor.token_index = link.end_index;
                continue;
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
                }
            },

            .square_brace_close,
            .parenthesis_close,
            => {
                if (tokenClosesSpan(cursor, opener, cursor.token_index)) {
                    cursor.increment();
                    break :text_span;
                }

                // See if this closer matches any open spans
                var prev_opt = prev_opener;
                while (prev_opt) |prev| : (prev_opt = prev.prev) {
                    if (tokenClosesSpan(cursor, prev.opener, cursor.token_index)) {
                        return null;
                    }
                }
            },

            .underscores,
            .asterisks,
            => {
                const index = cursor.token_index;

                if (tokenCouldCloseSpan(cursor, index)) {
                    if (tokenClosesSpan(cursor, opener, index)) {
                        cursor.increment();
                        break :text_span;
                    }

                    var prev_opt = prev_opener;
                    while (prev_opt) |prev| : (prev_opt = prev.prev) {
                        if (tokenClosesSpan(cursor, prev.opener, index)) {
                            return null;
                        }
                    }
                }

                cursor.increment();

                if (tokenCouldStartSpan(cursor, index)) {
                    if (try parseTextSpan(allocator, cursor, index, &.{ .prev = prev_opener, .opener = opener })) |text_span| {
                        defer allocator.free(text_span.events);
                        try events.append(.start_strong);
                        try events.appendSlice(text_span.events);
                        try events.append(.close_strong);
                        cursor.token_index = text_span.end_index;
                        continue :text_span;
                    }
                }

                // Just make it into regular text otherwise
                try events.append(.{ .text = cursor.tokenText(index) });
                continue :text_span;
            },
        }
        try events.append(.{ .text = cursor.tokenText(cursor.token_index) });
        cursor.increment();
    }

    return Parse{
        .events = events.toOwnedSlice(),
        .end_index = cursor.token_index,
    };
}

const PrevOpener = struct {
    prev: ?*const PrevOpener,
    opener: Cursor.TokenIndex,
};

fn tokenClosesSpan(cursor: Cursor, start: Cursor.TokenIndex, close: Cursor.TokenIndex) bool {
    const start_kind = cursor.token_kinds[start];
    const close_kind = cursor.token_kinds[close];
    return switch (start_kind) {
        .square_brace_open => close_kind == .square_brace_close,
        .parenthesis_open => close_kind == .parenthesis_close,
        .underscores,
        .asterisks,
        => {
            if (start_kind != close_kind) {
                return false;
            }
            if (!std.mem.eql(u8, cursor.tokenText(start), cursor.tokenText(close))) {
                return false;
            }
            return true;
        },
        else => false,
    };
}

fn tokenCouldStartSpan(cursor: Cursor, index: Cursor.TokenIndex) bool {
    switch (cursor.token_kinds[index]) {
        .underscores,
        .asterisks,
        => return cursor.token_kinds[index -| 1] == .curly_brace_open or
            !(cursor.token_kinds[index +| 1] == .spaces or
            cursor.token_kinds[index +| 1] == .single_newline or
            cursor.token_kinds[index +| 1] == .double_newline),
        else => return false,
    }
}

fn tokenCouldCloseSpan(cursor: Cursor, index: Cursor.TokenIndex) bool {
    switch (cursor.token_kinds[index]) {
        .underscores,
        .asterisks,
        => return cursor.token_kinds[index +| 1] == .curly_brace_close or
            !(cursor.token_kinds[index -| 1] == .spaces or
            cursor.token_kinds[index -| 1] == .single_newline or
            cursor.token_kinds[index -| 1] == .double_newline),
        else => return false,
    }
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
            defer this.increment();
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
        while (this.token_kinds[this.token_index] != .eof) : (this.increment()) {
            if (this.token_kinds[this.token_index] == expected_kind) {
                return [2]TokenIndex{ start, this.token_index };
            }
        }
        return null;
    }

    pub fn next(this: *@This()) TokenIndex {
        if (this.token_index >= this.token_kinds.len) {
            const last = @intCast(u32, this.token_kinds.len - 1);
            std.debug.assert(this.token_kinds[last] == .eof);
            return last;
        }
        defer this.increment();
        return this.token_index;
    }

    pub fn increment(this: *@This()) void {
        this.token_index = std.math.min(this.token_index + 1, this.token_kinds.len - 1);
    }

    pub fn tokenAt(this: @This(), index: TokenIndex) Token {
        std.debug.assert(this.token_index < this.token_kinds.len);
        return nextToken(this.source, this.token_starts[index]);
    }

    pub fn tokenText(this: @This(), index: TokenIndex) []const u8 {
        std.debug.assert(this.token_index < this.token_kinds.len);
        const tok = nextToken(this.source, this.token_starts[index]);
        return this.source[tok.start..tok.end];
    }

    pub fn end(this: @This()) usize {
        std.debug.assert(this.token_index < this.token_kinds.len);
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

        escape,

        asterisks,
        underscores,

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
        escape,
        underscores,
        asterisks,
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
                '_' => {
                    res.kind = .underscores;
                    i += 1;
                    res.end = i;
                    state = .underscores;
                },
                '*' => {
                    res.kind = .asterisks;
                    i += 1;
                    res.end = i;
                    state = .asterisks;
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
                '\\' => {
                    res.kind = .escape;
                    i += 1;
                    res.end = i;
                    state = .escape;
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
                '\\',
                '*',
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
            .underscores => switch (source[i]) {
                '_' => {
                    i += 1;
                    res.end = i;
                },
                else => break,
            },
            .asterisks => switch (source[i]) {
                '*' => {
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
            .escape => switch (source[i]) {
                else => {
                    i += 1;
                    res.end = i;
                    break;
                },
            },
        }
    }
    return res;
}
