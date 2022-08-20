const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");
const djot = @import("./djot.zig");
const Token = @import("./Token.zig");

pub const Blocks = struct {
    tight: bool,
};

pub fn parseBlocks(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?Blocks {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const first_block = (try parseBlock(&events, &tokens, prefix)) orelse return null;

    var tight = first_block.tight;
    var prev_index = tokens.index;

    while (tokens.tokens.items(.kind)[tokens.index] != .eof) {
        const was_break = parseNewlinePrefix(&tokens, prefix) orelse break;
        if (was_break) {
            tight = false;
        }

        const next_block = (try parseBlock(&events, &tokens, prefix)) orelse break;
        if (!next_block.tight) {
            tight = false;
        }

        if (tokens.index == prev_index) {
            std.debug.print("\ntoken[{}] = {s} \"{}\"\n", .{ tokens.index, std.meta.tagName(tokens.tokens.items(.kind)[tokens.index]), std.zig.fmtEscapes(tokens.text(tokens.index)) });
            return error.WouldLoop;
        }
        prev_index = tokens.index;
    }

    const was_content = events.index > parent_events.index;

    parent_tokens.* = tokens;
    parent_events.* = events;

    if (!was_content) {
        return null;
    }
    return Blocks{ .tight = tight };
}

pub const Block = struct {
    tight: bool,
};

pub fn parseBlock(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?Block {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    var tight = true;

    blk: {
        if (try parseThematicBreak(&events, &tokens)) |_| {
            break :blk;
        }

        if (try parseHeading(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseQuote(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseList(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseParagraph(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        return null;
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
    return Block{ .tight = tight };
}

// Move past the prefix and any empty lines
pub fn parseNewlinePrefix(parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) ?bool {
    var tokens = parent_tokens.*;
    var was_newline = false;

    // Parse empty lines
    while (true) {
        var lookahead = tokens;

        if (prefix) |p| {
            if (!p.parsePrefixVisible(&lookahead)) break;
        }
        while (lookahead.expect(.space)) |_| {}
        _ = lookahead.expect(.line_break) orelse break;

        was_newline = true;
        tokens = lookahead;
    }

    if (prefix) |p| {
        if (!p.parsePrefix(&tokens)) return null;
    }

    parent_tokens.* = tokens;
    return was_newline;
}

pub fn parseThematicBreak(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor) djot.Error!?void {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    var num_characters: usize = 0;
    while (tokens.expectInList(&.{ .space_asterisk, .asterisk, .hyphen, .space })) |char| : (num_characters += 1) {
        switch (tokens.kindOf(char)) {
            .space_asterisk, .asterisk, .hyphen => num_characters += 1,
            else => {},
        }
    }
    _ = tokens.expect(.line_break) orelse return null;

    if (num_characters < 4) return null;

    _ = try events.append(.thematic_break);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

pub fn parseHeading(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    const heading_token_index = tokens.expect(.heading) orelse return null;
    _ = tokens.expect(.space);

    const heading_token = tokens.token(heading_token_index);
    const level = @intCast(u32, heading_token.end - heading_token.start);

    _ = try events.append(.{ .start_heading = level });

    _ = (try parseTextSpans(&events, &tokens, prefix, null)) orelse return null;

    _ = try events.append(.{ .close_heading = level });

    parent_tokens.* = tokens;
    parent_events.* = events;
}

pub fn parseQuote(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    _ = tokens.expect(.right_angle) orelse return null;
    _ = tokens.expect(.space) orelse return null;

    _ = try events.append(.start_quote);
    _ = try parseBlocks(&events, &tokens, &.{ .prev = &.{ .prev = prefix, .token = .right_angle }, .token = .space });
    _ = try events.append(.close_quote);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

const List = struct {
    start: djot.EventCursor.Index,
    close: djot.EventCursor.Index,
};

fn parseList(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?List {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    // Allocate a place for the start event; we'll have to update it once we know
    // whether it's a tight or loose list
    const start_event = try events.append(.{ .start_list = undefined });

    const first_list_item = (try parseListItem(&events, &tokens, prefix)) orelse return null;

    var list_style = first_list_item.style;
    var tight = first_list_item.tight;

    while (true) {
        var lookahead = tokens;
        var lookahead_events = events;

        const was_newline = parseNewlinePrefix(&lookahead, prefix) orelse break;
        if (was_newline) {
            tight = false;
        }

        const list_item = try parseListItem(&lookahead_events, &lookahead, prefix) orelse break;

        if (list_item.style != list_style and list_style.isRoman() and list_item.style.isAlpha()) {
            if (list_item.style != list_style.romanToAlpha()) break;
            list_style = list_style.romanToAlpha();
        } else if (list_item.style != list_style and list_style.isAlpha() and list_item.style.isRoman()) {
            if (list_item.style.romanToAlpha() != list_style) break;
            // continue on
        } else if (list_item.style != list_style) {
            break;
        }

        tokens = lookahead;
        events = lookahead_events;
    }

    events.set(start_event, .{
        .start_list = .{
            .style = list_style,
        },
    });

    if (tight) {
        // Remove paragraph start and close events
        var next_index = start_event;
        for (events.events.items(.tag)[start_event..events.index]) |event_tag, offset| {
            if (event_tag == .start_paragraph or event_tag == .close_paragraph) {
                continue;
            }
            events.events.set(next_index, events.events.get(start_event + offset));
            next_index += 1;
        }
        events.index = next_index;
        events.events.len = next_index;
    }

    const close_event = try events.append(.{
        .close_list = .{
            .style = list_style,
        },
    });

    parent_tokens.* = tokens;
    parent_events.* = events;
    return List{
        .start = start_event,
        .close = close_event,
    };
}

const ListItem = struct {
    style: Marker.Style,
    tight: bool,
    start: djot.EventCursor.Index,
    close: djot.EventCursor.Index,
};

fn parseListItem(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?ListItem {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    var tight = true;

    const marker = Marker.parseTok(&tokens) orelse return null;

    const start = try events.append(.{ .start_list_item = @intCast(u32, marker.start) });

    const blocks = try parseBlocks(&events, &tokens, &.{ .prev = prefix, .token = .space }) orelse return null;
    if (!blocks.tight) {
        tight = false;
    }

    const close = try events.append(.{ .close_list_item = @intCast(u32, marker.start) });

    parent_tokens.* = tokens;
    parent_events.* = events;
    return ListItem{
        .style = marker.style,
        .tight = tight,
        .start = start,
        .close = close,
    };
}

fn parseParagraph(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    _ = try events.append(.start_paragraph);

    while (tokens.expect(.space)) |_| {}

    (try parseTextSpans(&events, &tokens, prefix, null)) orelse return null;

    _ = tokens.expect(.line_break);

    _ = try events.append(.close_paragraph);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseTextSpans(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    _ = try parseTextSpan(&events, &tokens, prefix, opener) orelse return null;

    while (true) {
        var lookahead = tokens;
        var lookahead_events = events;

        if (lookahead.expect(.line_break)) |line_break| {
            if (prefix) |p| {
                if (!p.parsePrefix(&lookahead)) break;
            }
            _ = try lookahead_events.append(.{ .text = lookahead.startOf(line_break) });
        }

        _ = try parseTextSpan(&lookahead_events, &lookahead, prefix, opener) orelse break;

        tokens = lookahead;
        events = lookahead_events;
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseTextSpan(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const token = tokens.current() orelse return null;
    switch (token.kind) {
        .eof => return null,
        .line_break => return null,

        .escape => {
            _ = tokens.next();
            _ = try events.append(.{ .escaped = token.start });
        },

        .hard_line_break => {
            // TODO: Append hard_line_break event
            _ = tokens.next();
        },

        .text,
        .right_angle,
        .right_square,
        .heading,
        .nonbreaking_space,
        .marker,
        .space,
        => {
            _ = try events.append(.{ .text = token.start });
            tokens.index += 1;
        },

        .exclaimation => {
            try parseInlineImageLink(&events, &tokens, prefix, opener) orelse {
                _ = try events.append(.{ .text = token.start });
                tokens.index += 1;
            };
        },
        .left_square => {
            try parseInlineLink(&events, &tokens, prefix, opener) orelse {
                _ = try events.append(.{ .text = token.start });
                tokens.index += 1;
            };
        },

        .open_asterisk,
        .space_asterisk,
        .open_underscore,
        .space_underscore,
        => (try parseInlineFormatting(&events, &tokens, prefix, opener)) orelse {
            _ = try events.append(.{ .text = token.start });
            tokens.index += 1;
        },

        .close_asterisk,
        .close_underscore,
        .inline_link_url,
        => {
            if (opener) |o| {
                if (o.isEnd(tokens, tokens.index)) {
                    return null;
                }
            }

            _ = try events.append(.{ .text = token.start });
            tokens.index += 1;
        },

        .asterisk, .underscore => {
            if (opener) |o| {
                if (o.isEnd(tokens, tokens.index)) {
                    return null;
                }
            }

            (try parseInlineFormatting(&events, &tokens, prefix, opener)) orelse {
                _ = try events.append(.{ .text = token.start });
                tokens.index += 1;
            };
        },
        .ticks => (try parseTextSpanVerbatim(&events, &tokens, prefix)).?,

        .autolink => {
            _ = try events.append(.{ .autolink = token.start });
            tokens.index += 1;
        },
        .autolink_email => {
            _ = try events.append(.{ .autolink_email = token.start });
            tokens.index += 1;
        },

        .hyphen => {
            // TODO: smart punctuation
            _ = try events.append(.{ .text = token.start });
            tokens.index += 1;
        },
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseInlineImageLink(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, prev_opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    _ = tokens.expect(.exclaimation) orelse return null;
    const open_link_token = tokens.expect(.left_square) orelse return null;

    const start_event = try events.append(.{ .start_image_link = undefined });

    _ = (try parseTextSpans(&events, &tokens, prefix, &.{ .prev = prev_opener, .tok = tokens.tokOf(open_link_token) })) orelse return null;

    switch (tokens.kindOf(tokens.index)) {
        .inline_link_url => {
            events.set(start_event, .{ .start_image_link = tokens.startOf(tokens.index) });
            _ = try events.append(.{ .close_image_link = tokens.startOf(tokens.index) });
            tokens.index += 1;
        },

        else => return null,
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseInlineLink(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, prev_opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const open_link_token = tokens.expect(.left_square) orelse return null;

    const start_event = try events.append(.{ .start_link = undefined });

    _ = (try parseTextSpans(&events, &tokens, prefix, &.{ .prev = prev_opener, .tok = tokens.tokOf(open_link_token) })) orelse return null;

    switch (tokens.kindOf(tokens.index)) {
        .inline_link_url => {
            events.set(start_event, .{ .start_link = tokens.startOf(tokens.index) });
            _ = try events.append(.{ .close_link = tokens.startOf(tokens.index) });
            tokens.index += 1;
        },

        else => return null,
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseInlineFormatting(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, prev_opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const ASTERISK_OPEN = [_]Token.Kind{ .asterisk, .open_asterisk };
    const ASTERISK_CLOSE = [_]Token.Kind{ .asterisk, .close_asterisk };
    const UNDERSCORE_OPEN = [_]Token.Kind{ .underscore, .open_underscore };
    const UNDERSCORE_CLOSE = [_]Token.Kind{ .underscore, .close_underscore };

    const open = tokens.expectInList(&(ASTERISK_OPEN ++ UNDERSCORE_OPEN)) orelse return null;

    switch (tokens.kindOf(open)) {
        .asterisk, .underscore => if (tokens.expect(.space)) |_| {
            return null;
        },
        else => {},
    }

    const openers = switch (tokens.kindOf(open)) {
        .asterisk, .open_asterisk => &ASTERISK_OPEN,
        .underscore, .open_underscore => &UNDERSCORE_OPEN,
        else => unreachable,
    };
    const opener_event: djot.Event = switch (tokens.kindOf(open)) {
        .asterisk, .open_asterisk => .start_strong,
        .underscore, .open_underscore => .start_emphasis,
        else => unreachable,
    };

    _ = try events.append(opener_event);

    var num_open_tokens: u32 = 1;
    while (tokens.expectInList(openers)) |_| : (num_open_tokens += 1) {
        _ = try events.append(opener_event);
    }

    _ = (try parseTextSpans(&events, &tokens, prefix, &.{ .prev = prev_opener, .tok = tokens.tokOf(open) })) orelse return null;

    const closers = switch (tokens.kindOf(open)) {
        .asterisk, .open_asterisk => &ASTERISK_CLOSE,
        .underscore, .open_underscore => &UNDERSCORE_CLOSE,
        else => unreachable,
    };
    const close_event: djot.Event = switch (tokens.kindOf(open)) {
        .asterisk, .open_asterisk => .close_strong,
        .underscore, .open_underscore => .close_emphasis,
        else => unreachable,
    };

    _ = tokens.expectInList(closers) orelse return null;
    _ = try events.append(close_event);

    var num_close_tokens: u32 = 1;
    while (tokens.expectInList(closers)) |_| : (num_close_tokens += 1) {
        if (num_close_tokens >= num_open_tokens) break;
        _ = try events.append(close_event);
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseTextSpanVerbatim(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const opener = tokens.expect(.ticks) orelse return null;
    _ = try events.append(.start_verbatim);

    while (true) {
        switch (tokens.kindOf(tokens.index)) {
            .eof => break,

            .line_break => {
                var lookahead = tokens;
                lookahead.index += 1;

                if (lookahead.expectInList(&.{ .line_break, .eof })) |_| {
                    break;
                }
                if (prefix) |p| {
                    if (!p.parsePrefix(&lookahead)) {
                        break;
                    }
                }

                _ = try events.append(.{ .text = tokens.index });
                tokens.index += 1;
            },

            .text,
            .space,
            .right_angle,
            .left_square,
            .right_square,
            .heading,
            .nonbreaking_space,
            .marker,
            .hard_line_break,
            .escape,

            .asterisk,
            .open_asterisk,
            .close_asterisk,
            .space_asterisk,

            .underscore,
            .open_underscore,
            .close_underscore,
            .space_underscore,

            .autolink,
            .autolink_email,
            .inline_link_url,
            .exclaimation,

            .hyphen,
            => {
                _ = try events.append(.{ .text = tokens.startOf(tokens.index) });
                tokens.index += 1;
            },

            .ticks => {
                const opener_ticks = tokens.token(opener);
                const these_ticks = tokens.token(tokens.index);
                if (opener_ticks.end - opener_ticks.start == these_ticks.end - these_ticks.start) {
                    tokens.index += 1;
                    break;
                }

                _ = try events.append(.{ .text = @intCast(u32, these_ticks.start) });
                tokens.index += 1;
            },
        }
    }

    _ = try events.append(.close_verbatim);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

const Prefix = struct {
    prev: ?*const Prefix = null,
    token: Token.Kind,

    pub fn parsePrefix(this: @This(), parent: *djot.TokCursor) bool {
        var cursor = parent.*;
        if (this.prev) |prev| {
            if (!prev.parsePrefix(&cursor)) {
                return false;
            }
        }
        if (cursor.expect(this.token) == null) {
            return false;
        }
        parent.* = cursor;
        return true;
    }

    pub fn parsePrefixVisible(this: @This(), parent: *djot.TokCursor) bool {
        var cursor = parent.*;
        if (this.prev) |prev| {
            if (!prev.parsePrefixVisible(&cursor)) {
                return false;
            }
        }
        if (cursor.expect(this.token) == null and this.token != .space) {
            return false;
        }
        parent.* = cursor;
        return true;
    }

    pub fn dump(this: @This()) void {
        if (this.prev) |prev| {
            prev.dump();
        }
    }
};

const PrevOpener = struct {
    prev: ?*const PrevOpener = null,
    tok: Token.Tok,

    pub fn isEnd(this: @This(), tokens: djot.TokCursor, index: djot.TokCursor.Index) bool {
        switch (tokens.kindOf(index)) {
            .asterisk,
            .close_asterisk,
            => if (this.tok.kind.isAsterisk()) {
                return true;
            },

            .underscore,
            .close_underscore,
            => if (this.tok.kind.isUnderscore()) {
                return true;
            },

            .inline_link_url => if (this.tok.kind == .left_square) {
                return true;
            },

            else => {},
        }
        if (this.prev) |prev| {
            return prev.isEnd(tokens, index);
        } else {
            return false;
        }
    }
};
