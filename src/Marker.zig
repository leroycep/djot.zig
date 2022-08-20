const std = @import("std");
const bolt = @import("./bolt.zig");
const djot = @import("./djot.zig");
const Token = @import("./Token.zig");

style: Style,
start: usize,
end: usize,

const Marker = @This();

pub const Style = enum {
    definition,

    hyphen,
    plus,
    asterisk,
    hyphen_task,
    plus_task,
    asterisk_task,

    decimal_period,
    decimal_paren,
    decimal_paren_enclosed,

    // a..b
    lower_alpha_period,
    lower_alpha_paren,
    lower_alpha_paren_enclosed,
    upper_alpha_period,
    upper_alpha_paren,
    upper_alpha_paren_enclosed,

    lower_roman_period,
    lower_roman_paren,
    lower_roman_paren_enclosed,
    upper_roman_period,
    upper_roman_paren,
    upper_roman_paren_enclosed,

    pub fn isRoman(this: @This()) bool {
        return switch (this) {
            .lower_roman_period,
            .lower_roman_paren,
            .lower_roman_paren_enclosed,
            .upper_roman_period,
            .upper_roman_paren,
            .upper_roman_paren_enclosed,
            => true,

            else => false,
        };
    }

    pub fn isAlpha(this: @This()) bool {
        return switch (this) {
            .lower_alpha_period,
            .lower_alpha_paren,
            .lower_alpha_paren_enclosed,
            .upper_alpha_period,
            .upper_alpha_paren,
            .upper_alpha_paren_enclosed,
            => true,

            else => false,
        };
    }

    pub fn romanToAlpha(this: @This()) @This() {
        return switch (this) {
            .lower_roman_period => .lower_alpha_period,
            .lower_roman_paren => .lower_alpha_paren,
            .lower_roman_paren_enclosed => .lower_alpha_paren_enclosed,
            .upper_roman_period => .upper_alpha_period,
            .upper_roman_paren => .upper_alpha_paren,
            .upper_roman_paren_enclosed => .upper_alpha_paren_enclosed,

            else => std.debug.panic("romanToAlpha only for roman styles", .{}),
        };
    }
};

pub fn getStyle(source: []const u8, token: Token) ?Marker.Style {
    var idx: usize = token.start;
    const marker = parse(source, &idx) orelse return null;
    return marker.style;
}

pub fn parse(source: []const u8, parent_index: *usize) ?Marker {
    return parseEnclosedMarker(source, parent_index) orelse
        parseDefinitionMarker(source, parent_index) orelse
        parseBulletMarker(source, parent_index) orelse
        parseOrderedMarker(source, parent_index);
}

pub fn parseTok(parent_tokens: *djot.TokCursor) ?Marker {
    var tokens = parent_tokens.*;

    var res = Marker{
        .start = tokens.startOf(tokens.index),
        .end = undefined,
        .style = undefined,
    };

    switch (tokens.kindOf(tokens.index)) {
        .colon => {
            tokens.index += 1;
            res.style = .definition;
        },

        .asterisk => {
            tokens.index += 1;
            res.style = .asterisk;
        },

        .hyphen => {
            tokens.index += 1;
            res.style = .hyphen;
        },

        .plus => {
            tokens.index += 1;
            res.style = .plus;
        },

        .digits => {
            tokens.index += 1;
            switch (tokens.kindOf(tokens.index)) {
                .period => res.style = .decimal_period,
                .right_paren => res.style = .decimal_paren,
                else => return null,
            }
            tokens.index += 1;
        },

        .lower_alpha => {
            tokens.index += 1;
            switch (tokens.kindOf(tokens.index)) {
                .period => res.style = .lower_alpha_period,
                .right_paren => res.style = .lower_alpha_paren,
                else => return null,
            }
            tokens.index += 1;
        },

        .upper_alpha => {
            tokens.index += 1;
            switch (tokens.kindOf(tokens.index)) {
                .period => res.style = .upper_alpha_period,
                .right_paren => res.style = .upper_alpha_paren,
                else => return null,
            }
            tokens.index += 1;
        },

        .lower_roman => {
            tokens.index += 1;
            switch (tokens.kindOf(tokens.index)) {
                .period => res.style = .lower_roman_period,
                .right_paren => res.style = .lower_roman_paren,
                else => return null,
            }
            tokens.index += 1;
        },

        .upper_roman => {
            tokens.index += 1;
            switch (tokens.kindOf(tokens.index)) {
                .period => res.style = .upper_roman_period,
                .right_paren => res.style = .upper_roman_paren,
                else => return null,
            }
            tokens.index += 1;
        },

        else => return null,
    }

    const space = tokens.expectInList(&.{ .space, .line_break }) orelse return null;
    res.end = tokens.endOf(space);

    parent_tokens.* = tokens;

    return res;
}

fn parseEnclosedMarker(source: []const u8, parent_index: *usize) ?Marker {
    const start = parent_index.*;
    var index = start;

    _ = bolt.raw.expect(u8, usize, source, &index, '(') orelse return null;
    const text = parseOrderedMarkerText(source, &index) orelse return null;
    _ = bolt.raw.expect(u8, usize, source, &index, ')') orelse return null;

    parent_index.* = index;
    return Marker{
        .start = start,
        .end = index,
        .style = switch (text.style) {
            .decimal => .decimal_paren_enclosed,
            .lower_roman => .lower_roman_paren_enclosed,
            .upper_roman => .upper_roman_paren_enclosed,
            .lower_alpha => .lower_alpha_paren_enclosed,
            .upper_alpha => .upper_alpha_paren_enclosed,
        },
    };
}

fn parseDefinitionMarker(source: []const u8, parent_index: *usize) ?Marker {
    const start = parent_index.*;
    var index = start;

    _ = bolt.raw.expect(u8, usize, source, &index, ':') orelse return null;

    parent_index.* = index;
    return Marker{
        .start = start,
        .end = index,
        .style = .definition,
    };
}

fn parseBulletMarker(source: []const u8, parent_index: *usize) ?Marker {
    const start = parent_index.*;
    var index = start;

    const style = switch (bolt.raw.next(u8, usize, source, &index) orelse return null) {
        '*' => Style.asterisk,
        '-' => Style.hyphen,
        '+' => Style.plus,
        else => return null,
    };

    if (incrementIfCheckBox(source, &index)) |_| {
        parent_index.* = index;
        return Marker{
            .start = start,
            .end = index,
            .style = switch (style) {
                .asterisk => .asterisk_task,
                .hyphen => .hyphen_task,
                .plus => .plus_task,
                else => return null,
            },
        };
    }

    parent_index.* = index;
    return Marker{
        .start = start,
        .style = style,
        .end = index,
    };
}

fn incrementIfCheckBox(source: []const u8, index: *usize) ?void {
    var i = index.*;
    _ = bolt.raw.expect(u8, usize, source, &i, ' ') orelse return null;
    _ = bolt.raw.expect(u8, usize, source, &i, '[') orelse return null;
    _ = bolt.raw.expectInList(u8, usize, source, &i, " xX") orelse return null;
    _ = bolt.raw.expect(u8, usize, source, &i, ']') orelse return null;
    //_ = bolt.raw.expectInList(u8, usize, source, &i, " \n") orelse return null;
    index.* = i;
}

fn parseOrderedMarker(source: []const u8, parent_index: *usize) ?Marker {
    const start = parent_index.*;
    var index = parent_index.*;

    const text = parseOrderedMarkerText(source, &index) orelse return null;
    const is_period = switch (bolt.raw.next(u8, usize, source, &index) orelse return null) {
        '.' => true,
        ')' => false,
        else => return null,
    };

    //_ = bolt.raw.expectInList(u8, usize, source, &index, " \n") orelse return null;

    parent_index.* = index;
    return Marker{
        .start = start,
        .end = index,
        .style = if (is_period) switch (text.style) {
            .decimal => .decimal_period,
            .lower_roman => .lower_roman_period,
            .upper_roman => .upper_roman_period,
            .lower_alpha => .lower_alpha_period,
            .upper_alpha => .upper_alpha_period,
        } else switch (text.style) {
            .decimal => .decimal_paren,
            .lower_roman => .lower_roman_paren,
            .upper_roman => .upper_roman_paren,
            .lower_alpha => .lower_alpha_paren,
            .upper_alpha => .upper_alpha_paren,
        },
    };
}

const OrderedStyle = enum {
    decimal,
    lower_roman,
    upper_roman,
    lower_alpha,
    upper_alpha,
};

const MarkerText = struct {
    style: OrderedStyle,
    start: usize,
    end: usize,
};

fn parseOrderedMarkerText(source: []const u8, parent_index: *usize) ?MarkerText {
    if (parent_index.* >= source.len) return null;

    var res = MarkerText{
        .start = parent_index.*,
        .end = parent_index.*,
        .style = switch (source[parent_index.*]) {
            '0'...'9' => .decimal,
            'I', 'V', 'X', 'L', 'C', 'D', 'M' => .upper_roman,
            'i', 'v', 'x', 'l', 'c', 'd', 'm' => .lower_roman,
            'A'...'B', 'E'...'H', 'J'...'K', 'N'...'U', 'W', 'Y', 'Z' => .upper_alpha,
            'a'...'b', 'e'...'h', 'j'...'k', 'n'...'u', 'w', 'y', 'z' => .lower_alpha,
            else => return null,
        },
    };

    switch (res.style) {
        .decimal => while (bolt.raw.expectInRange(u8, usize, source, &res.end, '0', '9')) |_| {},
        .lower_alpha => while (bolt.raw.expectInRange(u8, usize, source, &res.end, 'a', 'z')) |_| {},
        .upper_alpha => while (bolt.raw.expectInRange(u8, usize, source, &res.end, 'A', 'Z')) |_| {},
        .lower_roman => {
            while (bolt.raw.expectInList(u8, usize, source, &res.end, "ivxlcdm")) |_| {}
            if (bolt.raw.expectInRange(u8, usize, source, &res.end, 'a', 'z')) |_| {
                res.style = .lower_alpha;
                while (bolt.raw.expectInRange(u8, usize, source, &res.end, 'a', 'z')) |_| {}
            }
        },
        .upper_roman => {
            while (bolt.raw.expectInList(u8, usize, source, &res.end, "IVXLCDM")) |_| {}
            if (bolt.raw.expectInRange(u8, usize, source, &res.end, 'A', 'Z')) |_| {
                res.style = .upper_alpha;
                while (bolt.raw.expectInRange(u8, usize, source, &res.end, 'A', 'Z')) |_| {}
            }
        },
    }

    parent_index.* = res.end;
    return res;
}

test "marker parse style" {
    try expectParseStyle(": definition", .definition);
    try expectParseStyle("- hyphen", .hyphen);
    try expectParseStyle("+ plus", .plus);
    try expectParseStyle("* asterisk", .asterisk);
    try expectParseStyle("- [ ] hyphen_task", .hyphen_task);
    try expectParseStyle("+ [ ] plus_task", .plus_task);
    try expectParseStyle("* [ ] asterisk_task", .asterisk_task);
    try expectParseStyle("1. decimal_period", .decimal_period);
    try expectParseStyle("2) decimal_paren", .decimal_paren);
    try expectParseStyle("(3) decimal_paren_enclosed", .decimal_paren_enclosed);
    try expectParseStyle("a. lower_alpha_period", .lower_alpha_period);
    try expectParseStyle("b) lower_alpha_paren", .lower_alpha_paren);
    try expectParseStyle("(e) lower_alpha_paren_enclosed", .lower_alpha_paren_enclosed);
    try expectParseStyle("F. upper_alpha_period", .upper_alpha_period);
    try expectParseStyle("G) upper_alpha_paren", .upper_alpha_paren);
    try expectParseStyle("(H) upper_alpha_paren_enclosed", .upper_alpha_paren_enclosed);
    try expectParseStyle("i. lower_roman_period", .lower_roman_period);
    try expectParseStyle("ii) lower_roman_paren", .lower_roman_paren);
    try expectParseStyle("(iii) lower_roman_paren_enclosed", .lower_roman_paren_enclosed);
    try expectParseStyle("IV. upper_roman_period", .upper_roman_period);
    try expectParseStyle("V) upper_roman_paren", .upper_roman_paren);
    try expectParseStyle("(VI) upper_roman_paren_enclosed", .upper_roman_paren_enclosed);
}

fn expectParseStyle(source: []const u8, expected: Style) !void {
    var index: usize = 0;
    const marker = parse(source, &index) orelse return error.ParsedNull;
    try std.testing.expectEqual(expected, marker.style);
}

test "marker parse text" {
    try expectParseText(": definition", ":");
    try expectParseText("- hyphen", "-");
    try expectParseText("+ plus", "+");
    try expectParseText("* asterisk", "*");
    try expectParseText("- [ ] hyphen_task", "- [ ]");
    try expectParseText("+ [ ] plus_task", "+ [ ]");
    try expectParseText("* [ ] asterisk_task", "* [ ]");
    try expectParseText("1. decimal_period", "1.");
    try expectParseText("2) decimal_paren", "2)");
    try expectParseText("(3) decimal_paren_enclosed", "(3)");
    try expectParseText("a. lower_alpha_period", "a.");
    try expectParseText("b) lower_alpha_paren", "b)");
    try expectParseText("(c) lower_alpha_paren_enclosed", "(c)");
    try expectParseText("D. upper_alpha_period", "D.");
    try expectParseText("E) upper_alpha_paren", "E)");
    try expectParseText("(F) upper_alpha_paren_enclosed", "(F)");
    try expectParseText("i. lower_roman_period", "i.");
    try expectParseText("ii) lower_roman_paren", "ii)");
    try expectParseText("(iii) lower_roman_paren_enclosed", "(iii)");
    try expectParseText("IV. upper_roman_period", "IV.");
    try expectParseText("V) upper_roman_paren", "V)");
    try expectParseText("(VI) upper_roman_paren_enclosed", "(VI)");
}

fn expectParseText(source: []const u8, expected: []const u8) !void {
    var index: usize = 0;
    const marker = parse(source, &index) orelse return error.ParsedNull;
    try std.testing.expectEqualStrings(expected, source[marker.start..marker.end]);
    try std.testing.expectEqual(expected.len, index);
}
