const std = @import("std");

// TODO: Use concrete error set
pub fn toHtml(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const events = try parse(allocator, source);
    defer parseFree(allocator, events);

    var html = std.ArrayList(u8).init(allocator);
    defer html.deinit();
    for (events) |event| {
        switch (event) {
            .text => |t| {
                var i: usize = 0;
                while (i < t.len) {
                    const codepoint_length = try std.unicode.utf8ByteSequenceLength(t[i]);
                    // TODO: check this earlier?
                    if (i + codepoint_length > t.len) return error.InvalidUTF8;
                    switch (try std.unicode.utf8Decode(t[i..][0..codepoint_length])) {
                        '…' => try html.appendSlice("&hellip;"),
                        else => try html.appendSlice(t[i..][0..codepoint_length]),
                    }
                    i += codepoint_length;
                }
            },
            .newline => try html.appendSlice("\n"),
            // TODO: Remove this? Seems redundant
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
            .start_emphasis => try html.appendSlice("<em>"),
            .close_emphasis => try html.appendSlice("</em>"),
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
    start_emphasis,
    close_emphasis,

    pub fn eql(a: @This(), b: @This()) bool {
        if (std.meta.activeTag(a) != b) {
            return false;
        }
        return switch (a) {
            .text => std.mem.eql(u8, a.text, b.text),
            .verbatim_inline => std.mem.eql(u8, a.verbatim_inline, b.verbatim_inline),
            .start_link => std.mem.eql(u8, a.start_link, b.start_link),
            .image => std.mem.eql(u8, a.image.src, b.image.src) and std.mem.eql(u8, a.image.alt, b.image.alt),
            .autolink => std.mem.eql(u8, a.autolink, b.autolink),
            .autolink_email => std.mem.eql(u8, a.autolink_email, b.autolink_email),

            .character => a.character == b.character,

            // Events that are only tags just return true
            .newline,
            .start_paragraph,
            .close_paragraph,
            .start_strong,
            .close_strong,
            .start_emphasis,
            .close_emphasis,
            .close_link,
            => true,
        };
    }

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (this) {
            .text,
            .verbatim_inline,
            .start_link,
            .autolink,
            .autolink_email,
            => |text| try writer.print("{s} \"{}\"", .{ std.meta.tagName(this), std.zig.fmtEscapes(text) }),

            .image => |img| try writer.print("{s} alt=\"{}\" src=\"{}\"", .{ std.meta.tagName(this), std.zig.fmtEscapes(img.alt), std.zig.fmtEscapes(img.src) }),

            .character => |c| {
                var buf: [4]u8 = undefined;
                const bytes_written = std.unicode.utf8Encode(c, &buf) catch unreachable;
                try writer.print("{s} '{'}'", .{ std.meta.tagName(this), std.zig.fmtEscapes(buf[0..bytes_written]) });
            },

            // Events that are only tags just return true
            .newline,
            .start_paragraph,
            .close_paragraph,
            .start_strong,
            .close_strong,
            .start_emphasis,
            .close_emphasis,
            .close_link,
            => try writer.print("{s}", .{std.meta.tagName(this)}),
        }
    }
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
        if (try parseTextSpan(allocator, cursor, null, null)) |paragraph| {
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

const PrevOpener = struct {
    prev: ?*const PrevOpener,
    opener: Cursor.TokenIndex,
};

fn parseTextSpan(allocator: std.mem.Allocator, start_cursor: Cursor, opener: ?Cursor.TokenIndex, prev_opener: ?*const PrevOpener) anyerror!?Parse {
    var cursor = start_cursor;

    if (cursor.eat(.eof) orelse cursor.eat(.double_newline)) |_| {
        return null;
    }

    var events = std.ArrayList(Event).init(allocator);
    defer parseFree(allocator, events.toOwnedSlice());

    const this_prev_opener = if (opener) |o| &PrevOpener{
        .prev = prev_opener,
        .opener = o,
    } else null;

    var in_attr = false;

    text_span: while (true) {
        switch (cursor.token_kinds[cursor.token_index]) {
            .eof => if (opener == null) {
                break;
            } else {
                return null;
            },
            .double_newline => break,

            .text,
            .spaces,
            .parenthesis_open,
            => {},

            .ellipses => {
                try events.append(.{ .text = "…" });
                cursor.increment();
                continue;
            },

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

            .exclaimation => if (try parseImageLink(allocator, cursor, this_prev_opener)) |link| {
                try events.append(.{ .image = .{
                    .src = link.url,
                    .alt = link.alt_text,
                } });
                cursor.token_index = link.end_index;
                continue;
            },

            .square_brace_open => if (try parseLink(allocator, cursor, this_prev_opener)) |link| {
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
                if (opener != null and tokenClosesSpan(cursor, opener.?, cursor.token_index)) {
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
            .underscores_open,
            .underscores_close,
            .asterisks,
            .asterisks_open,
            .asterisks_close,
            => {
                const index = cursor.token_index;

                if (opener != null and tokenCouldCloseSpan(cursor, index)) {
                    if (tokenClosesSpan(cursor, opener.?, index)) {
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
                    const span_events = tokenToSpanEvents(cursor, index).?;
                    if (try parseTextSpan(allocator, cursor, index, this_prev_opener)) |text_span| {
                        defer allocator.free(text_span.events);

                        const token = cursor.tokenAt(index);
                        const num = switch (token.kind) {
                            .asterisks, .underscores => token.end - token.start,
                            .asterisks_open, .underscores_open => token.end - token.start - 1,
                            else => unreachable,
                        };

                        try events.appendNTimes(span_events[0], num);
                        try events.appendSlice(text_span.events);
                        try events.appendNTimes(span_events[1], num);

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

fn tokenClosesSpan(cursor: Cursor, start: Cursor.TokenIndex, close: Cursor.TokenIndex) bool {
    const start_kind = cursor.token_kinds[start];
    const close_kind = cursor.token_kinds[close];
    return switch (start_kind) {
        .square_brace_open => close_kind == .square_brace_close,
        .parenthesis_open => close_kind == .parenthesis_close,

        // TODO: Use length instead of text comparison
        .underscores => switch (close_kind) {
            .underscores_close => std.mem.eql(u8, cursor.tokenText(start), cursor.tokenText(close)[0..1]),
            .underscores => std.mem.eql(u8, cursor.tokenText(start), cursor.tokenText(close)),
            else => false,
        },

        // TODO: Use length instead of text comparison
        .asterisks => switch (close_kind) {
            .asterisks_close => std.mem.eql(u8, cursor.tokenText(start), cursor.tokenText(close)[0..1]),
            .asterisks => std.mem.eql(u8, cursor.tokenText(start), cursor.tokenText(close)),
            else => false,
        },

        .underscores_open => switch (close_kind) {
            .underscores_close => std.mem.eql(u8, cursor.tokenText(start)[1..], cursor.tokenText(close)[0..1]),
            .underscores => std.mem.eql(u8, cursor.tokenText(start)[1..], cursor.tokenText(close)),
            else => false,
        },

        .asterisks_open => switch (close_kind) {
            .asterisks_close => std.mem.eql(u8, cursor.tokenText(start)[1..], cursor.tokenText(close)[0..1]),
            .asterisks => std.mem.eql(u8, cursor.tokenText(start)[1..], cursor.tokenText(close)),
            else => false,
        },

        else => false,
    };
}

fn tokenCouldStartSpan(cursor: Cursor, index: Cursor.TokenIndex) bool {
    switch (cursor.token_kinds[index]) {
        .square_brace_open,
        .parenthesis_open,
        .asterisks_open,
        .underscores_open,
        => return true,

        .underscores,
        .asterisks,
        => {
            const no_spaces_after = !(cursor.token_kinds[index +| 1] == .spaces or
                cursor.token_kinds[index +| 1] == .single_newline or
                cursor.token_kinds[index +| 1] == .double_newline);
            return no_spaces_after;
        },

        else => return false,
    }
}

fn tokenCouldCloseSpan(cursor: Cursor, index: Cursor.TokenIndex) bool {
    switch (cursor.token_kinds[index]) {
        .square_brace_close,
        .parenthesis_close,
        .asterisks_close,
        .underscores_close,
        => return true,

        .underscores,
        .asterisks,
        => {
            const before = cursor.token_kinds[index -| 1];
            const no_spaces_before = !(before == .spaces or
                before == .single_newline or
                before == .double_newline or
                before == .eof);
            return no_spaces_before;
        },
        else => return false,
    }
}

fn tokenToSpanEvents(cursor: Cursor, index: Cursor.TokenIndex) ?[2]Event {
    switch (cursor.token_kinds[index]) {
        .underscores, .underscores_open => return [_]Event{ .start_emphasis, .close_emphasis },
        .asterisks, .asterisks_open => return [_]Event{ .start_strong, .close_strong },
        else => return null,
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
        /// Asterisks preceded by a bracket (`{*`)
        asterisks_open,
        /// Asterisks followed by a bracket (`*}`)
        asterisks_close,

        underscores,
        /// Underscores preceded by a bracket (`{_`)
        underscores_open,
        /// Underscores followed by a bracket (`_}`)
        underscores_close,

        ellipses,

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
        underscores_open,
        asterisks,
        asterisks_open,
        period1,
        period2,
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
                ' ',
                '\t',
                => {
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
                '.' => {
                    res.kind = .text;
                    i += 1;
                    res.end = i;
                    state = .period1;
                },
                else => state = .text,
            },
            .curly_brace_open => switch (source[i]) {
                '%' => {
                    i += 1;
                    state = .comment;
                },
                '*' => {
                    i += 1;
                    res.kind = .asterisks_open;
                    res.end = i;
                    state = .asterisks_open;
                },
                '_' => {
                    i += 1;
                    res.kind = .underscores_open;
                    res.end = i;
                    state = .underscores_open;
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
                '_',
                ' ',
                '.',
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
                ' ',
                '\t',
                => {
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
                '}' => {
                    i += 1;
                    res.kind = .underscores_close;
                    res.end = i;
                    break;
                },
                else => break,
            },
            .underscores_open => switch (source[i]) {
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
                '}' => {
                    i += 1;
                    res.kind = .asterisks_close;
                    res.end = i;
                    break;
                },
                else => break,
            },
            .asterisks_open => switch (source[i]) {
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
            .period1 => switch (source[i]) {
                '.' => {
                    i += 1;
                    state = .period2;
                },
                else => break,
            },
            .period2 => switch (source[i]) {
                '.' => {
                    i += 1;
                    res.kind = .ellipses;
                    res.end = i;
                    break;
                },
                else => break,
            },
        }
    }
    return res;
}

test "emphasis" {
    try testParse(
        \\_[bar_](url)
    , &.{
        .start_paragraph,
        .start_emphasis,
        .{ .text = "[" },
        .{ .text = "bar" },
        .close_emphasis,
        .{ .text = "]" },
        .{ .text = "(" },
        .{ .text = "url" },
        .{ .text = ")" },
        .close_paragraph,
    });
}

test "tabs are spaces" {
    try testParse("_\ta_", &.{
        .start_paragraph,
        .{ .text = "_" },
        .{ .text = "\t" },
        .{ .text = "a" },
        .{ .text = "_" },
        .close_paragraph,
    });
}

fn testParse(source: []const u8, expected: []const Event) !void {
    const events = try parse(std.testing.allocator, source);
    defer parseFree(std.testing.allocator, events);

    if (expected.len != events.len) {
        std.debug.print("Event slices are not the same length: {} != {}\n", .{ expected.len, events.len });
        dumpParseTestCase(events, expected);
        return error.TestExpectedEqual;
    }
    for (events) |event, i| {
        if (!event.eql(expected[i])) {
            std.debug.print("Expected parsed events to be the same, first difference at index {}\n", .{i});
            dumpParseTestCase(events, expected);
            return error.TestExpectedEqual;
        }
    }
}

fn dumpParseTestCase(events: []const Event, expected: []const Event) void {
    std.debug.print("\nExpected\n", .{});
    std.debug.print("=======\n", .{});
    for (expected) |e, i| {
        std.debug.print("events[{}] = {}\n", .{ i, e });
    }
    std.debug.print("=======\n", .{});
    std.debug.print("\nParsed\n", .{});
    std.debug.print("=======\n", .{});
    for (events) |e, i| {
        std.debug.print("events[{}] = {}\n", .{ i, e });
    }
    std.debug.print("=======\n", .{});
}

fn beep(src: std.builtin.SourceLocation, input: anytype) @TypeOf(input) {
    std.debug.print("{s}:{} {}\n", .{ src.fn_name, src.line, input });
    return input;
}
