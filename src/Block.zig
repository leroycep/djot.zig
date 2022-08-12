const std = @import("std");

kind: Kind,
text: []const u8,

const Block = @This();

const Kind = enum {
    paragraph,
    heading,
    quote,
    list_item,
    list,
    code,
    thematic_break,
    raw,
    div,
    pipe_table,
    reference_link_deinition,
    footnote,
};

pub const Iterator = struct {
    source: []const u8,
    index: usize = 0,

    pub fn next(this: *@This()) ?Block {
        if (this.index >= this.source.len) {
            return null;
        }

        var kind = Kind.paragraph;
        var start = this.index;
        var end: usize = undefined;

        var state = State.default;
        while (this.index < this.source.len) {
            switch (state) {
                .default => switch (this.source[this.index]) {
                    '\n' => {
                        this.index += 1;
                        start = this.index;
                    },
                    '#' => {
                        this.index += 1;
                        kind = .heading;
                        state = .heading;
                    },
                    else => {
                        this.index += 1;
                        kind = .paragraph;
                        state = .paragraph;
                    },
                },
                .paragraph => switch (this.source[this.index]) {
                    '\r',
                    '\n',
                    => {
                        end = this.index;
                        this.index += 1;
                        state = .paragraph_newline;
                    },
                    else => {
                        this.index += 1;
                        end = this.index;
                    },
                },
                .paragraph_newline => switch (this.source[this.index]) {
                    '\n' => break,

                    '\t',
                    ' ',
                    '\r',
                    => this.index += 1,

                    else => {
                        this.index += 1;
                        state = .paragraph;
                    },
                },
                .heading => switch (this.source[this.index]) {
                    '\r',
                    '\n',
                    => {
                        end = this.index;
                        this.index += 1;
                        state = .heading_newline;
                    },
                    else => {
                        this.index += 1;
                        end = this.index;
                    },
                },
                .heading_newline => switch (this.source[this.index]) {
                    '\n' => break,

                    '\t',
                    ' ',
                    '\r',
                    => this.index += 1,

                    else => {
                        this.index += 1;
                        state = .heading;
                    },
                },
            }
        }
        return Block{
            .kind = kind,
            .text = this.source[start..end],
        };
    }

    const State = enum {
        default,
        heading,
        heading_newline,
        paragraph,
        paragraph_newline,
    };
};

test {
    try testParse(
        \\## A level _two_ heading
        \\
    , &.{
        .{ .kind = .heading, .text = "## A level _two_ heading" },
    });

    try testParse(
        \\## A heading that
        \\takes up
        \\three lines
        \\
        \\A paragraph, finally.
    , &.{
        .{ .kind = .heading, .text = 
        \\## A heading that
        \\takes up
        \\three lines
        },
        .{ .kind = .paragraph, .text = "A paragraph, finally." },
    });
}

fn testParse(source: []const u8, expected: []const Block) !void {
    var iter = Iterator{ .source = source };
    for (expected) |expected_block| {
        const block = iter.next() orelse return error.TestExpectedNotNull;
        if (!(expected_block.kind == block.kind)) return error.TestExpectedEqual;
        if (!std.mem.eql(u8, expected_block.text, block.text)) return error.TestExpectedEqual;
    }
}
