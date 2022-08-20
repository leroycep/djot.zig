const std = @import("std");
const bolt = @import("./bolt.zig");

kind: Kind,
start: usize,
end: usize,

pub const Kind = enum(u8) {
    eof,
    line_break,
    hard_line_break,
    space,
    nonbreaking_space,
    text,

    digits,
    lower_alpha,
    upper_alpha,
    lower_roman,
    upper_roman,

    escape,
    heading,
    right_angle,
    left_square,
    right_square,
    right_paren,

    ticks,

    asterisk,
    open_asterisk,
    close_asterisk,
    space_asterisk,

    underscore,
    open_underscore,
    close_underscore,
    space_underscore,

    autolink,
    autolink_email,
    inline_link_url,
    exclaimation,

    hyphen,
    period,
    colon,
    plus,

    pub fn isAsterisk(this: @This()) bool {
        switch (this) {
            .asterisk,
            .space_asterisk,
            .open_asterisk,
            .close_asterisk,
            => return true,

            else => return false,
        }
    }

    pub fn isUnderscore(this: @This()) bool {
        switch (this) {
            .underscore,
            .space_underscore,
            .open_underscore,
            .close_underscore,
            => return true,

            else => return false,
        }
    }
};

pub const MultiArrayList = std.MultiArrayList(Tok);
pub const Slice = MultiArrayList.Slice;

/// A cut down version of token, only include the kind and start index
pub const Tok = struct {
    kind: Kind,
    start: u32,
};

pub fn parseAll(allocator: std.mem.Allocator, source: []const u8) !Slice {
    var tokens = std.MultiArrayList(Tok){};
    defer tokens.deinit(allocator);

    var pos: usize = 0;
    while (true) {
        const token = parse(source, pos);
        try tokens.append(allocator, .{
            .kind = token.kind,
            .start = @intCast(u32, token.start),
        });
        if (token.kind == .eof) {
            break;
        }
        pos = token.end;
    }

    return tokens.toOwnedSlice();
}

pub fn parse(source: []const u8, start: usize) @This() {
    const State = enum {
        default,
        text,
        text_period1,
        text_period2,
        text_newline,
        text_space,

        heading,
        escape,

        digits,
        lower_roman,
        upper_roman,
        lower_alpha,
        upper_alpha,

        ticks,
        lcurl,
        asterisk,
        underscore,
        space,

        autolink,
        autolink_email,

        rsquare,
        rsquare_lparen,
        rsquare_lparen_url,
    };

    var res = @This(){
        .kind = .eof,
        .start = start,
        .end = start,
    };

    var state = State.default;
    var index = start;
    while (bolt.raw.next(u8, usize, source, &index)) |c| {
        switch (state) {
            .default => switch (c) {
                '#' => {
                    res.kind = .heading;
                    res.end = index;
                    state = .heading;
                },
                ' ',
                '\t',
                => {
                    res.kind = .space;
                    res.end = index;
                    state = .space;
                },
                '\n' => {
                    res.kind = .line_break;
                    res.end = index;
                    break;
                },
                '<' => {
                    res.kind = .text;
                    res.end = index;
                    state = .autolink;
                },
                '>' => {
                    res.kind = .right_angle;
                    res.end = index;
                    break;
                },
                '*' => {
                    res.kind = .asterisk;
                    res.end = index;
                    state = .asterisk;
                },
                '_' => {
                    res.kind = .underscore;
                    res.end = index;
                    state = .underscore;
                },
                '{' => {
                    res.kind = .text;
                    res.end = index;
                    state = .lcurl;
                },
                '!' => {
                    res.kind = .exclaimation;
                    res.end = index;
                    break;
                },
                '[' => {
                    res.kind = .left_square;
                    res.end = index;
                    state = .rsquare;
                },
                ']' => {
                    res.kind = .right_square;
                    res.end = index;
                    state = .rsquare;
                },
                '-' => {
                    res.kind = .hyphen;
                    res.end = index;
                    break;
                },
                '`' => {
                    res.kind = .ticks;
                    res.end = index;
                    state = .ticks;
                },
                '\\' => {
                    res.kind = .text;
                    res.end = index;
                    state = .escape;
                },
                '.' => {
                    res.kind = .period;
                    res.end = index;
                    break;
                },
                ':' => {
                    res.kind = .colon;
                    res.end = index;
                    break;
                },
                ')' => {
                    res.kind = .right_paren;
                    res.end = index;
                    break;
                },
                '+' => {
                    res.kind = .plus;
                    res.end = index;
                    break;
                },
                '0'...'9' => {
                    res.kind = .digits;
                    res.end = index;
                    state = .digits;
                },
                'I', 'V', 'X', 'L', 'C', 'D', 'M' => {
                    res.kind = .upper_roman;
                    res.end = index;
                    state = .upper_roman;
                },
                'i', 'v', 'x', 'l', 'c', 'd', 'm' => {
                    res.kind = .lower_roman;
                    res.end = index;
                    state = .lower_roman;
                },
                'A'...'B', 'E'...'H', 'J'...'K', 'N'...'U', 'W', 'Y', 'Z' => {
                    res.kind = .upper_alpha;
                    res.end = index;
                    state = .upper_alpha;
                },
                'a'...'b', 'e'...'h', 'j'...'k', 'n'...'u', 'w', 'y', 'z' => {
                    res.kind = .lower_alpha;
                    res.end = index;
                    state = .lower_alpha;
                },
                else => {
                    res.kind = .text;
                    res.end = index;
                    state = .text;
                },
            },
            .heading => switch (c) {
                '#' => res.end = index,
                else => break,
            },
            .text => switch (c) {
                '`',
                '*',
                '_',
                '{',
                '\\',
                '!',
                '[',
                ']',
                => break,

                '.' => state = .text_period1,
                ' ' => state = .text_space,
                '\n' => state = .text_newline,
                else => res.end = index,
            },
            .text_period1 => switch (c) {
                '.' => state = .text_period2,
                '`', '*', '_', '{', '\\', '!', '[', ']' => break,

                ' ' => {
                    res.end = index;
                    state = .text_space;
                },
                '\n' => {
                    res.end = index - 1;
                    state = .text_newline;
                },
                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .text_period2 => switch (c) {
                '.' => break,

                '`', '*', '_', '{', '\\', '!', '[', ']' => break,

                ' ' => state = .text_space,
                '\n' => {
                    res.end = index - 1;
                    state = .text_newline;
                },
                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .text_newline => switch (c) {
                '\n',
                '0'...'9',
                '-',
                '+',
                '*',
                '<',
                '>',
                '`',
                '_',
                '{',
                '\\',
                '!',
                '[',
                ']',
                ')',
                => break,

                ' ' => {
                    res.kind = .text;
                    state = .text_space;
                },
                '.' => break,

                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .text_space => switch (c) {
                '`',
                '*',
                '_',
                '{',
                '\n',
                '\\',
                '<',
                '!',
                '[',
                ']',
                '.',
                ')',
                => break,

                ' ' => {},

                else => {
                    res.kind = .text;
                    res.end = index;
                    state = .text;
                },
            },
            .ticks => switch (c) {
                '`' => res.end = index,
                else => break,
            },
            .escape => switch (c) {
                ' ' => {
                    res.kind = .nonbreaking_space;
                    res.end = index;
                    break;
                },
                '\n' => {
                    res.kind = .hard_line_break;
                    res.end = index;
                    break;
                },
                else => if (std.ascii.isPunct(c)) {
                    res.kind = .escape;
                    res.end = index;
                    break;
                } else {
                    res.end = index;
                    state = .text;
                },
            },
            .digits => switch (c) {
                '0'...'9' => res.end = index,
                ' ' => {
                    res.kind = .text;
                    res.end = index;
                    state = .text_space;
                },
                else => break,
            },
            .lower_roman => switch (c) {
                'i', 'v', 'x', 'l', 'c', 'd', 'm' => res.end = index,
                'a'...'b', 'e'...'h', 'j'...'k', 'n'...'u', 'w', 'y', 'z' => {
                    res.end = index;
                    state = .lower_alpha;
                },
                ' ', 'A'...'Z', '0'...'9' => {
                    res.kind = .text;
                    res.end = index;
                    state = .text_space;
                },
                else => break,
            },
            .upper_roman => switch (c) {
                'I', 'V', 'X', 'L', 'C', 'D', 'M' => res.end = index,
                'A'...'B', 'E'...'H', 'J'...'K', 'N'...'U', 'W', 'Y', 'Z' => {
                    res.end = index;
                    state = .upper_alpha;
                },
                ' ', 'a'...'z', '0'...'9' => {
                    res.kind = .text;
                    res.end = index;
                    state = .text_space;
                },
                else => break,
            },
            .lower_alpha => switch (c) {
                'a'...'z' => res.end = index,
                ' ', 'A'...'Z', '0'...'9' => {
                    res.kind = .text;
                    res.end = index;
                    state = .text_space;
                },
                else => break,
            },
            .upper_alpha => switch (c) {
                'A'...'Z' => res.end = index,
                ' ', 'a'...'z', '0'...'9' => {
                    res.kind = .text;
                    res.end = index;
                    state = .text_space;
                },
                else => break,
            },
            .lcurl => switch (c) {
                '*' => {
                    res.kind = .open_asterisk;
                    res.end = index;
                    break;
                },
                '_' => {
                    res.kind = .open_underscore;
                    res.end = index;
                    break;
                },
                else => break,
            },
            .asterisk => switch (c) {
                '}' => {
                    res.kind = .close_asterisk;
                    res.end = index;
                    break;
                },
                else => break,
            },
            .underscore => switch (c) {
                '}' => {
                    res.kind = .close_underscore;
                    res.end = index;
                    break;
                },
                else => break,
            },
            .space => switch (c) {
                '*' => {
                    res.kind = .space_asterisk;
                    res.end = index;
                    break;
                },
                '_' => {
                    res.kind = .space_underscore;
                    res.end = index;
                    break;
                },
                else => break,
            },
            .autolink => switch (c) {
                '>' => {
                    res.kind = .autolink;
                    res.end = index;
                    break;
                },
                '@' => state = .autolink_email,
                '\n' => break,
                else => res.end = index,
            },
            .autolink_email => switch (c) {
                '>' => {
                    res.kind = .autolink_email;
                    res.end = index;
                    break;
                },
                '\n' => break,
                else => res.end = index,
            },
            .rsquare => switch (c) {
                '(' => state = .rsquare_lparen,
                else => break,
            },
            .rsquare_lparen => switch (c) {
                'A'...'Z', 'a'...'z' => state = .rsquare_lparen_url,
                else => break,
            },
            .rsquare_lparen_url => switch (c) {
                ')' => {
                    res.kind = .inline_link_url;
                    res.end = index;
                    break;
                },
                else => {},
            },
        }
    }

    if (index == source.len) {
        switch (state) {
            .text_period1 => res.end = index,
            else => {},
        }
    }

    return res;
}
