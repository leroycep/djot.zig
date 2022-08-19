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
        if (try parseHeading(&events, &tokens)) |_| {
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

pub fn parseHeading(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor) djot.Error!?void {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    const heading_token_index = tokens.expect(.heading) orelse return null;
    _ = tokens.expect(.space);

    const heading_token = tokens.token(heading_token_index);
    const level = @intCast(u32, heading_token.end - heading_token.start);

    _ = try events.append(.{ .start_heading = level });

    const text = tokens.expect(.text) orelse return null;
    _ = try events.append(.{ .text = tokens.tokens.items(.start)[text] });

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

    (try parseTextSpan(&events, &tokens, prefix, null)) orelse return null;

    _ = tokens.expect(.line_break);

    _ = try events.append(.close_paragraph);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseTextSpan(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, opener: ?PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    //if (try parseTextSpanStrong(&events, &tokens, prefix, if (opener) |o| &o else null)) |_| {
    //    parent_tokens.* = tokens;
    //    parent_events.* = events;
    //    return;
    //}

    if (try parseTextSpanVerbatim(&events, &tokens, prefix, if (opener) |o| &o else null)) |_| {
        parent_tokens.* = tokens;
        parent_events.* = events;
        return;
    }

    const first_text = parseTextPlain(&tokens) orelse return null;
    _ = try events.append(.{ .text = first_text.source_index });

    var lookahead = tokens;
    while (lookahead.next()) |token| : (tokens = lookahead) {
        switch (token.kind) {
            .eof => if (opener) |o| {
                if (o.tok.kind == .ticks) break;
                return null;
            } else {
                break;
            },

            .line_break => {
                if (lookahead.expectInList(&.{ .line_break, .eof })) |_| {
                    break;
                }
                if (prefix) |p| {
                    if (!p.parsePrefix(&lookahead)) {
                        break;
                    }
                }
                _ = try events.append(.{ .text = token.start });
            },

            .text,
            .space,
            .right_angle,
            .heading,
            .nonbreaking_space,
            => {
                // Treat as text
                _ = try events.append(.{ .text = token.start });
            },

            .escape => {
                // TODO: Append as an escape event
            },
            .hard_line_break => {
                // TODO: Append hard_line_break event
            },

            .asterisk => {
                // TODO: parse strong span
                if (opener) |o| {
                    if (o.tok.kind == .asterisk) {
                        // Exit loop, return value
                        tokens.index = lookahead.index - 1;
                        break;
                    }
                }

                // TODO: parse strong span
                // start a new verbatim span
                var strong_events = events;
                if (try parseTextSpanStrong(&strong_events, &tokens, prefix, if (opener) |o| &o else null)) |_| {
                    events = strong_events;
                    lookahead = tokens;
                    continue;
                }

                _ = try events.append(.{ .text = token.start });
            },

            .ticks => {
                if (opener) |o| blk: {
                    if (o.tok.kind != .ticks) break :blk;
                    const opener_ticks = Token.parse(tokens.source, o.tok.start);
                    const these_ticks = lookahead.token(lookahead.index - 1);
                    if (opener_ticks.end - opener_ticks.start == these_ticks.end - these_ticks.start) {
                        // Exit loop, return value
                        tokens.index = lookahead.index - 1;
                        break;
                    }
                }

                // TODO: parse verbatim span
                {
                    // start a new verbatim span
                    var verbatim_events = events;
                    if (try parseTextSpanVerbatim(&verbatim_events, &tokens, prefix, if (opener) |o| &o else null)) |_| {
                        events = verbatim_events;
                        lookahead = tokens;
                    }
                }
            },

            .marker => break,
        }

        if (prefix) |p| {
            if (!p.parsePrefix(&lookahead)) break;
        }
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseTextSpanStrong(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, prev_opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const asterisk_open = tokens.expect(.asterisk) orelse return null;
    _ = try events.append(.start_strong);

    _ = (try parseTextSpan(&events, &tokens, prefix, .{ .prev = prev_opener, .tok = tokens.tokOf(asterisk_open) })) orelse return null;

    _ = tokens.expect(.asterisk) orelse return null;
    _ = try events.append(.close_strong);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseTextSpanVerbatim(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, prev_opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const ticks_open = tokens.expect(.ticks) orelse return null;
    _ = try events.append(.start_verbatim);

    _ = (try parseTextSpanPlain(&events, &tokens, prefix, .{ .prev = prev_opener, .tok = tokens.tokOf(ticks_open) })) orelse return null;

    if (tokens.expect(.ticks)) |ticks_close| {
        // TODO: ensure it matches
        _ = ticks_close;
    }
    _ = try events.append(.close_verbatim);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseTextSpanPlain(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, opener: ?PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    var lookahead = tokens;
    while (lookahead.next()) |token| : (tokens = lookahead) {
        switch (token.kind) {
            .eof => if (opener) |o| {
                if (o.tok.kind == .ticks) break;
                return null;
            } else {
                break;
            },

            .line_break => {
                if (lookahead.expectInList(&.{ .line_break, .eof })) |_| {
                    break;
                }
                if (prefix) |p| {
                    if (!p.parsePrefix(&lookahead)) {
                        break;
                    }
                }
                _ = try events.append(.{ .text = token.start });
            },

            .text,
            .space,
            .right_angle,
            .heading,
            .nonbreaking_space,
            => {
                // Treat as text
                _ = try events.append(.{ .text = token.start });
            },

            .escape => {
                // TODO: Append as an escape event
            },
            .hard_line_break => {
                // TODO: Append hard_line_break event
            },

            .asterisk => {
                // TODO: parse strong span
            },

            .ticks => {
                // Only exit if it ends a previous open
                if (opener) |o| blk: {
                    if (o.tok.kind != .ticks) break :blk;
                    const opener_ticks = Token.parse(tokens.source, o.tok.start);
                    const these_ticks = lookahead.token(lookahead.index - 1);
                    if (opener_ticks.end - opener_ticks.start == these_ticks.end - these_ticks.start) {
                        // Exit loop, return value
                        tokens.index = lookahead.index - 1;
                        break;
                    }
                }
                _ = try events.append(.{ .text = token.start });
            },

            .marker => break,
        }

        if (prefix) |p| {
            if (!p.parsePrefix(&lookahead)) break;
        }
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

const PlainText = struct {
    source_index: u32,
};

fn parseTextPlain(parent_tokens: *djot.TokCursor) ?PlainText {
    var tokens = parent_tokens.*;

    const token = tokens.next() orelse return null;
    switch (token.kind) {
        .eof,
        .line_break,
        .hard_line_break,
        => return null,

        .text,
        .space,
        .right_angle,
        .heading,
        .nonbreaking_space,
        .marker,
        .escape,
        .asterisk,
        .ticks,
        => {
            // Treat as text
            parent_tokens.* = tokens;
            return PlainText{ .source_index = token.start };
        },
    }
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
};
