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

    escape,
    heading,
    right_angle,
    asterisk,

    marker,

    ticks,
    underscore,
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
        text_newline,

        heading,
        spaces,
        escape,

        marker_end,
        digits,
        lower_roman,
        upper_roman,
        lower_alpha,
        upper_alpha,

        ticks,
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
                ' ' => {
                    res.kind = .space;
                    res.end = index;
                    break;
                },
                '\n' => {
                    res.kind = .line_break;
                    res.end = index;
                    break;
                },
                '>' => {
                    res.kind = .right_angle;
                    res.end = index;
                    break;
                },
                '*' => {
                    res.kind = .asterisk;
                    res.end = index;
                    break;
                },
                '_' => {
                    res.kind = .underscore;
                    res.end = index;
                    break;
                },
                '-',
                '+',
                => {
                    res.kind = .text;
                    res.end = index;
                    state = .marker_end;
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
                '0'...'9' => {
                    res.kind = .text;
                    res.end = index;
                    state = .digits;
                },
                'I', 'V', 'X', 'L', 'C', 'D', 'M' => {
                    res.kind = .text;
                    res.end = index;
                    state = .upper_roman;
                },
                'i', 'v', 'x', 'l', 'c', 'd', 'm' => {
                    res.kind = .text;
                    res.end = index;
                    state = .lower_roman;
                },
                'A'...'B', 'E'...'H', 'J'...'K', 'N'...'U', 'W', 'Y', 'Z' => {
                    res.kind = .text;
                    res.end = index;
                    state = .upper_alpha;
                },
                'a'...'b', 'e'...'h', 'j'...'k', 'n'...'u', 'w', 'y', 'z' => {
                    res.kind = .text;
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
                '`', '*', '_', '\\' => break,

                '\n' => state = .text_newline,
                else => res.end = index,
            },
            .text_newline => switch (c) {
                '\n', '0'...'9', '-', '+', '*', '>', '`', '_', '\\' => break,

                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .spaces => switch (c) {
                ' ' => {
                    res.end = index;
                },
                else => break,
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
            .marker_end => switch (c) {
                ' ',
                '\n',
                => {
                    res.kind = .marker;
                    res.end = index;
                    break;
                },
                else => break,
            },
            .digits => switch (c) {
                '0'...'9' => res.end = index,

                '.',
                ')',
                => {
                    res.end = index;
                    state = .marker_end;
                },

                '_',
                '\n',
                => break,

                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .lower_roman => switch (c) {
                'i', 'v', 'x', 'l', 'c', 'd', 'm' => res.end = index,
                'a'...'b', 'e'...'h', 'j'...'k', 'n'...'u', 'w', 'y', 'z' => {
                    res.end = index;
                    state = .lower_alpha;
                },

                '.',
                ')',
                => {
                    res.end = index;
                    state = .marker_end;
                },

                '`',
                '*',
                '_',
                '\\',
                '\n',
                => break,

                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .upper_roman => switch (c) {
                'I', 'V', 'X', 'L', 'C', 'D', 'M' => res.end = index,
                'A'...'B', 'E'...'H', 'J'...'K', 'N'...'U', 'W', 'Y', 'Z' => {
                    res.end = index;
                    state = .lower_alpha;
                },

                '.',
                ')',
                => {
                    res.end = index;
                    state = .marker_end;
                },

                '`',
                '*',
                '_',
                '\\',
                '\n',
                => break,

                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .lower_alpha => switch (c) {
                'a'...'z' => res.end = index,

                '.',
                ')',
                => {
                    res.end = index;
                    state = .marker_end;
                },

                '`',
                '*',
                '_',
                '\\',
                '\n',
                => break,

                else => {
                    res.end = index;
                    state = .text;
                },
            },
            .upper_alpha => switch (c) {
                'A'...'Z' => res.end = index,

                '.',
                ')',
                => {
                    res.end = index;
                    state = .marker_end;
                },

                '`',
                '*',
                '_',
                '\\',
                '\n',
                => break,

                else => {
                    res.end = index;
                    state = .text;
                },
            },
        }
    }

    return res;
}
