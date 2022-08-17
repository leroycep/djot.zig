const std = @import("std");
const parselib = @import("./parse.zig");

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

pub fn parse(source: []const u8, parent_index: *usize) ?Marker {
    return parseEnclosedMarker(source, parent_index) orelse
        parseDefinitionMarker(source, parent_index) orelse
        parseBulletMarker(source, parent_index) orelse
        parseOrderedMarker(source, parent_index);
}

fn parseEnclosedMarker(source: []const u8, parent_index: *usize) ?Marker {
    const start = parent_index.*;
    var index = start;

    _ = parselib.expect(u8, source, &index, '(') orelse return null;
    const text = parseOrderedMarkerText(source, &index) orelse return null;
    _ = parselib.expect(u8, source, &index, ')') orelse return null;

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

    _ = parselib.expect(u8, source, &index, ':') orelse return null;

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

    const style = switch (source[index]) {
        '*' => Style.asterisk,
        '-' => Style.hyphen,
        '+' => Style.plus,
        else => return null,
    };
    index += 1;

    if (incrementIfCheckBox(source, &index)) |_| {
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

    return Marker{
        .start = start,
        .style = style,
        .end = index,
    };
}

fn incrementIfCheckBox(source: []const u8, index: *usize) ?void {
    var i = index.*;
    _ = parselib.expect(u8, source, &i, ' ') orelse return null;
    _ = parselib.expect(u8, source, &i, '[') orelse return null;
    _ = parselib.expectInList(u8, source, &i, " xX") orelse return null;
    _ = parselib.expect(u8, source, &i, ']') orelse return null;
    //_ = parselib.expectInList(u8, source, &i, " \n") orelse return null;
    index.* = i;
}

fn parseOrderedMarker(source: []const u8, parent_index: *usize) ?Marker {
    const start = parent_index.*;
    var index = parent_index.*;

    const text = parseOrderedMarkerText(source, &index) orelse return null;
    const is_period = switch (parselib.next(u8, source, &index) orelse return null) {
        '.' => true,
        ')' => false,
        else => return null,
    };

    //_ = parselib.expectInList(u8, source, &index, " \n") orelse return null;

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
        .decimal => while (parselib.expectInRange(u8, source, &res.end, '0', '9')) |_| {},
        .lower_alpha => while (parselib.expectInRange(u8, source, &res.end, 'a', 'z')) |_| {},
        .upper_alpha => while (parselib.expectInRange(u8, source, &res.end, 'A', 'Z')) |_| {},
        .lower_roman => {
            while (parselib.expectInList(u8, source, &res.end, "ivxlcdm")) |_| {}
            if (parselib.expectInRange(u8, source, &res.end, 'a', 'z')) |_| {
                res.style = .lower_alpha;
                while (parselib.expectInRange(u8, source, &res.end, 'a', 'z')) |_| {}
            }
        },
        .upper_roman => {
            while (parselib.expectInList(u8, source, &res.end, "IVXLCDM")) |_| {}
            if (parselib.expectInRange(u8, source, &res.end, 'A', 'Z')) |_| {
                res.style = .upper_alpha;
                while (parselib.expectInRange(u8, source, &res.end, 'A', 'Z')) |_| {}
            }
        },
    }

    parent_index.* = res.end;
    return res;
}

test "parse style" {
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

test "parse text" {
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
