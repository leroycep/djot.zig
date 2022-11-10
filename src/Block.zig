const std = @import("std");
const builtin = @import("builtin");
const Marker = @import("./Marker.zig");
const djot = @import("./djot.zig");
const Token = @import("./Token.zig");
const unicode = @import("./unicode.zig");

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

        const next_block = (try parseBlock(&events, &tokens, prefix)) orelse break;
        if (!next_block.tight) {
            tight = false;
        }
        if (was_break and !next_block.list) {
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
    list: bool,
};

pub fn parseBlock(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?Block {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    var tight = true;
    var list = false;

    blk: {
        switch (tokens.kindOf(tokens.index)) {
            .hyphen,
            .asterisk,
            => if (try parseThematicBreak(&events, &tokens)) |_| {
                break :blk;
            } else if (try parseList(&events, &tokens, prefix)) |_| {
                list = true;
                break :blk;
            },

            .plus,
            .digits,
            .lower_alpha,
            .upper_alpha,
            .lower_roman,
            .upper_roman,
            => if (try parseList(&events, &tokens, prefix)) |_| {
                list = true;
                break :blk;
            },

            .heading => if (try parseHeading(&events, &tokens, prefix)) |_| {
                break :blk;
            },

            .ticks,
            .tildes,
            => if (try parseCodeBlock(&events, &tokens, prefix)) |_| {
                break :blk;
            },

            .right_angle => if (try parseQuote(&events, &tokens, prefix)) |_| {
                break :blk;
            },

            .pipe => if (try parsePipeTable(&events, &tokens, prefix)) |_| {
                break :blk;
            },

            .space => if (try parseIndentBlock(&events, &tokens, prefix)) |_| {
                break :blk;
            },

            else => {},
        }

        if (try parseThematicBreak(&events, &tokens)) |_| {
            break :blk;
        }

        if (try parseHeading(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseCodeBlock(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseQuote(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseList(&events, &tokens, prefix)) |_| {
            list = true;
            break :blk;
        }

        if (try parsePipeTable(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseAttribute(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        if (try parseParagraph(&events, &tokens, prefix)) |_| {
            break :blk;
        }

        return null;
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
    return Block{ .tight = tight, .list = list };
}

pub fn parseIndentBlock(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    _ = tokens.expect(.space) orelse return null;

    _ = (try parseBlocks(&events, &tokens, &.{ .prev = prefix, .token = .space })) orelse return null;

    parent_events.* = events;
    parent_tokens.* = tokens;
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

pub fn parsePipeTable(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    _ = try events.append(.start_table);

    _ = (try parsePipeTableRow(&events, &tokens, prefix)) orelse return null;

    while (true) {
        (try parsePipeTableRow(&events, &tokens, prefix)) orelse break;
    }

    _ = try events.append(.close_table);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

pub fn parsePipeTableRow(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    _ = try events.append(.start_table_row);

    const open_pipe = tokens.expect(.pipe) orelse return null;
    _ = try events.append(.start_table_cell);

    while (tokens.expect(.space)) |_| {}

    while (true) {
        _ = try parseTextSpans(&events, &tokens, prefix, &.{ .tok = tokens.tokOf(open_pipe) });

        while (tokens.expect(.space)) |_| {}

        _ = tokens.expect(.pipe) orelse return null;

        _ = try events.append(.close_table_cell);

        while (tokens.expect(.space)) |_| {}
        if (tokens.expectInList(&.{ .line_break, .eof })) |_| {
            break;
        }

        _ = try events.append(.start_table_cell);
    }

    _ = try events.append(.close_table_row);

    parent_tokens.* = tokens;
    parent_events.* = events;
}

pub fn parseCodeBlock(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    var tokens = parent_tokens.*;
    var events = parent_events.*;

    const fence = tokens.expectInList(&.{ .ticks, .tildes }) orelse return null;
    const fence_token = tokens.token(fence);
    const num_start_ticks = fence_token.end - fence_token.start;
    if (num_start_ticks < 3) {
        return null;
    }

    while (tokens.expect(.space)) |_| {}
    const language_or_null = tokens.expectInList(&.{
        .digits,
        .lower_alpha,
        .upper_alpha,
        .lower_roman,
        .upper_roman,
        .text,
    });
    while (tokens.expect(.space)) |_| {}
    _ = tokens.expect(.line_break) orelse return null;

    if (language_or_null) |language| {
        // TODO: See if we can make the tokenizer checking for spaces
        const text = tokens.token(language);
        if (std.mem.indexOfAny(u8, tokens.source[text.start..text.end], " ") != null) return null;

        // TODO: attach language info; check if it is a raw block
        _ = try events.append(.{ .start_code_language = tokens.startOf(language) });
    } else {
        _ = try events.append(.start_code_block);
    }

    var was_newline = true;
    while (tokens.current()) |tok| : (tokens.index += 1) {
        switch (tok.kind) {
            .eof => break,
            .ticks,
            .tildes,
            => if (was_newline) {
                // Check if the number of ticks is >= the starting fence
                const token = tokens.token(fence);
                const num_these_ticks = token.end - token.start;
                if (token.kind == fence_token.kind and num_these_ticks >= num_start_ticks) {
                    tokens.index += 1;
                    break;
                }

                // Otherwise append it as text
                _ = try events.append(.{ .text = tok.start });
                was_newline = false;
            },

            .line_break => {
                was_newline = true;
                _ = try events.append(.{ .text = tok.start });
                // TODO: handle prefixes
                _ = prefix;
            },

            else => {
                _ = try events.append(.{ .text = tok.start });
                was_newline = false;
            },
        }
    }

    if (language_or_null) |language| {
        // TODO: attach language info; check if it is a raw block
        _ = try events.append(.{ .close_code_language = tokens.startOf(language) });
    } else {
        _ = try events.append(.close_code_block);
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
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
            if (event_tag == .start_paragraph) {
                continue;
            }
            if (event_tag == .close_paragraph) {
                events.events.set(next_index, .{ .tag = .character, .data = .{ .character = '\n' } });
                next_index += 1;
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

pub fn parseAttribute(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix) djot.Error!?void {
    _ = prefix;

    var events = parent_events.*;
    var tokens = parent_tokens.*;

    if (tokens.kindOf(tokens.index) == .left_curl) {
        _ = (try parseInlineAttribute(&events, &tokens)) orelse return null;
    } else {
        return null;
    }

    parent_events.* = events;
    parent_tokens.* = tokens;
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

        while (lookahead.expect(.space)) |_| {}
        if (lookahead.expect(.line_break)) |line_break| {
            if (prefix) |p| {
                if (!p.parsePrefix(&lookahead)) break;
            }
            _ = try lookahead_events.append(.{ .text = lookahead.startOf(line_break) });

            // Remove spaces at start of line
            while (lookahead.expect(.space)) |_| {}
        } else {
            lookahead = tokens;
        }

        while (lookahead.expect(.space)) |space| {
            _ = try lookahead_events.append(.{ .text = tokens.startOf(space) });
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

        .period => {
            if (tokens.expectString(&.{ .period, .period, .period })) |_| {
                _ = try events.append(.{ .character = unicode.ELLIPSES });
            } else {
                _ = try events.append(.{ .text = token.start });
                tokens.index += 1;
            }
        },

        .hyphen => {
            var num_hyphens: u32 = 0;
            while (tokens.expect(.hyphen)) |_| : (num_hyphens += 1) {}

            if (num_hyphens == 1) {
                _ = try events.append(.{ .text = token.start });
            } else if (num_hyphens % 3 == 0) {
                var i: u32 = 0;
                while (i < num_hyphens / 3) : (i += 1) {
                    _ = try events.append(.{ .character = unicode.EM_DASH });
                }
            } else if (num_hyphens % 2 == 0) {
                var i: u32 = 0;
                while (i < num_hyphens / 2) : (i += 1) {
                    _ = try events.append(.{ .character = unicode.EN_DASH });
                }
            } else {
                // TODO: Figure what the actual algorithm for this is
                switch (num_hyphens) {
                    5 => {
                        _ = try events.append(.{ .character = unicode.EM_DASH });
                        _ = try events.append(.{ .character = unicode.EN_DASH });
                    },
                    7 => {
                        _ = try events.append(.{ .character = unicode.EM_DASH });
                        _ = try events.append(.{ .character = unicode.EN_DASH });
                        _ = try events.append(.{ .character = unicode.EN_DASH });
                    },
                    13 => {
                        _ = try events.append(.{ .character = unicode.EM_DASH });
                        _ = try events.append(.{ .character = unicode.EM_DASH });
                        _ = try events.append(.{ .character = unicode.EM_DASH });
                        _ = try events.append(.{ .character = unicode.EN_DASH });
                        _ = try events.append(.{ .character = unicode.EN_DASH });
                    },
                    else => {
                        const num_ems = ((num_hyphens + 1) / 3) / 2;
                        const num_ens = (num_hyphens - num_ems * 3) / 2;
                        const remain = (num_hyphens - num_ems * 3 - num_ens * 2);
                        var i: u32 = 0;
                        while (i < num_ems) : (i += 1) {
                            _ = try events.append(.{ .character = unicode.EM_DASH });
                        }
                        i = 0;
                        while (i < num_ens) : (i += 1) {
                            _ = try events.append(.{ .character = unicode.EN_DASH });
                        }
                        i = 0;
                        while (i < remain) : (i += 1) {
                            _ = try events.append(.{ .text = token.start });
                        }
                    },
                }
            }
        },

        .text,
        .right_angle,
        .heading,
        .nonbreaking_space,
        .space,
        .colon,
        .plus,
        .left_paren,
        .right_paren,
        .digits,
        .lower_alpha,
        .upper_alpha,
        .lower_roman,
        .upper_roman,
        .tildes,
        .percent,
        .right_curl,
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

        .left_curl => {
            (try parseInlineAttribute(&events, &tokens)) orelse {
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
        .pipe,
        .right_square,
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
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

fn parseInlineAttribute(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    _ = tokens.expect(.left_curl) orelse return null;

    const State = enum {
        default,
        comment,
    };
    var state = State.default;

    while (tokens.next()) |token| {
        switch (state) {
            .default => switch (token.kind) {
                .eof => break,
                .right_curl => {
                    parent_tokens.* = tokens;
                    parent_events.* = events;
                    return {};
                },
                .percent => state = .comment,
                else => {},
            },

            .comment => switch (token.kind) {
                .eof => break,
                .percent => state = .default,
                else => {},
            },
        }
    }

    return null;
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

        .right_square => {
            tokens.index += 1;
            if (parseInlineLinkReferenceText(&tokens, .left_square, .right_square)) |link_reference| {
                // TODO
                events.set(start_event, .{ .start_link_undefined = link_reference.start });
                _ = try events.append(.{ .close_link_undefined = link_reference.start });
            } else if (parseInlineLinkReferenceText(&tokens, .left_paren, .right_paren)) |link_reference| {
                events.set(start_event, .{ .start_image_link = link_reference.start });
                _ = try events.append(.{ .close_image_link = link_reference.start });
            } else {
                return null;
            }
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

        .right_square => {
            tokens.index += 1;
            if (parseInlineLinkReferenceText(&tokens, .left_square, .right_square)) |link_reference| {
                events.set(start_event, .{ .start_link_undefined = link_reference.start });
                _ = try events.append(.{ .close_link_undefined = link_reference.start });
            } else if (parseInlineLinkReferenceText(&tokens, .left_paren, .right_paren)) |link_reference| {
                events.set(start_event, .{ .start_link = link_reference.start });
                _ = try events.append(.{ .close_link = link_reference.start });
            } else {
                return null;
            }
        },

        else => return null,
    }

    parent_tokens.* = tokens;
    parent_events.* = events;
}

const LinkReferenceText = struct {
    start: u32,
    end: u32,
};

fn parseInlineLinkReferenceText(parent_tokens: *djot.TokCursor, start_kind: Token.Kind, close_kind: Token.Kind) ?LinkReferenceText {
    var tokens = parent_tokens.*;

    _ = tokens.expect(start_kind) orelse return null;

    const start = tokens.startOf(tokens.index);

    while (tokens.kindOf(tokens.index) != .eof) : (tokens.index += 1) {
        if (tokens.kindOf(tokens.index) == close_kind) {
            break;
        }
    } else {
        return null;
    }

    const end = tokens.endOf(tokens.index);

    _ = tokens.expect(close_kind) orelse return null;

    parent_tokens.* = tokens;
    return LinkReferenceText{ .start = start, .end = end };
}

fn parseInlineFormatting(parent_events: *djot.EventCursor, parent_tokens: *djot.TokCursor, prefix: ?*const Prefix, prev_opener: ?*const PrevOpener) djot.Error!?void {
    var events = parent_events.*;
    var tokens = parent_tokens.*;

    const ASTERISK_OPEN = [_]Token.Kind{ .asterisk, .space_asterisk, .open_asterisk };
    const ASTERISK_CLOSE = [_]Token.Kind{ .asterisk, .close_asterisk };
    const UNDERSCORE_OPEN = [_]Token.Kind{ .underscore, .space_underscore, .open_underscore };
    const UNDERSCORE_CLOSE = [_]Token.Kind{ .underscore, .close_underscore };

    const open = tokens.expectInList(&(ASTERISK_OPEN ++ UNDERSCORE_OPEN)) orelse return null;

    switch (tokens.kindOf(open)) {
        .asterisk,
        .underscore,
        => if (tokens.expect(.space)) |_| {
            return null;
        },
        .space_asterisk,
        .space_underscore,
        => if (tokens.expect(.space)) |_| {
            return null;
        } else {
            _ = try events.append(.{ .character = ' ' });
        },
        else => {},
    }

    const openers = switch (tokens.kindOf(open)) {
        .asterisk,
        .space_asterisk,
        .open_asterisk,
        => &ASTERISK_OPEN,

        .underscore,
        .space_underscore,
        .open_underscore,
        => &UNDERSCORE_OPEN,
        else => unreachable,
    };
    const opener_event: djot.Event = switch (tokens.kindOf(open)) {
        .asterisk,
        .space_asterisk,
        .open_asterisk,
        => .start_strong,

        .underscore,
        .space_underscore,
        .open_underscore,
        => .start_emphasis,

        else => unreachable,
    };

    _ = try events.append(opener_event);

    var num_open_tokens: u32 = 1;
    while (tokens.expectInList(openers)) |_| : (num_open_tokens += 1) {
        _ = try events.append(opener_event);
    }

    _ = (try parseTextSpans(&events, &tokens, prefix, &.{ .prev = prev_opener, .tok = tokens.tokOf(open) })) orelse return null;

    const closers = switch (tokens.kindOf(open)) {
        .asterisk,
        .space_asterisk,
        .open_asterisk,
        => &ASTERISK_CLOSE,

        .underscore,
        .space_underscore,
        .open_underscore,
        => &UNDERSCORE_CLOSE,

        else => unreachable,
    };
    const close_event: djot.Event = switch (tokens.kindOf(open)) {
        .asterisk,
        .space_asterisk,
        .open_asterisk,
        => .close_strong,

        .underscore,
        .space_underscore,
        .open_underscore,
        => .close_emphasis,
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

    var only_seen_spaces = true;
    var was_space_that_should_be_removed = false;

    while (true) {
        switch (tokens.kindOf(tokens.index)) {
            .eof => break,

            .line_break => {
                only_seen_spaces = false;
                was_space_that_should_be_removed = false;

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

                _ = try events.append(.{ .text = tokens.startOf(tokens.index) });
                tokens.index += 1;
            },

            .space => {
                // TODO: Ensure these are the closing ticks
                if (only_seen_spaces and tokens.kindOf(tokens.index + 1) == .ticks) {
                    // skip adding space to output
                } else {
                    _ = try events.append(.{ .text = tokens.startOf(tokens.index) });
                }
                tokens.index += 1;
            },

            .text,
            .right_angle,
            .left_square,
            .right_square,
            .heading,
            .nonbreaking_space,
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

            .period,
            .colon,
            .plus,
            .left_paren,
            .right_paren,

            .digits,
            .lower_alpha,
            .upper_alpha,
            .lower_roman,
            .upper_roman,
            .pipe,

            .tildes,

            .percent,
            .left_curl,
            .right_curl,
            => {
                only_seen_spaces = false;
                was_space_that_should_be_removed = false;

                _ = try events.append(.{ .text = tokens.startOf(tokens.index) });
                tokens.index += 1;
            },

            .ticks => {
                only_seen_spaces = false;

                const opener_ticks = tokens.token(opener);
                const these_ticks = tokens.token(tokens.index);
                if (opener_ticks.end - opener_ticks.start == these_ticks.end - these_ticks.start) {
                    if (was_space_that_should_be_removed) {
                        events.index -= 1;
                    }
                    tokens.index += 1;
                    break;
                }

                _ = try events.append(.{ .text = @intCast(u32, these_ticks.start) });
                tokens.index += 1;

                if (tokens.kindOf(tokens.index) == .space) {
                    // Skip a space at the end
                    was_space_that_should_be_removed = true;
                }
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

            .pipe => if (this.tok.kind == .pipe) {
                return true;
            },

            .right_square => if (this.tok.kind == .left_square) {
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
