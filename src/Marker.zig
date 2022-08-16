const std = @import("std");

style: Style,
end: u32,

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

pub fn parse(source: [*:0]const u8, index: u32) ?Marker {
    return parseEnclosedMarker(source, index) orelse
        parseDefinitionMarker(source, index) orelse
        parseBulletMarker(source, index) orelse
        parseOrderedMarker(source, index);
}

fn parseEnclosedMarker(source: [*:0]const u8, start_index: u32) ?Marker {
    var index = start_index;

    incrementIfCharacter(source, &index, '(') orelse return null;

    const text = parseOrderedMarkerText(source, index) orelse return null;
    index = text.end;

    incrementIfCharacter(source, &index, ')') orelse return null;

    return Marker{
        .style = switch (text.style) {
            .decimal => .decimal_paren_enclosed,
            .lower_roman => .lower_roman_paren_enclosed,
            .upper_roman => .upper_roman_paren_enclosed,
            .lower_alpha => .lower_alpha_paren_enclosed,
            .upper_alpha => .upper_alpha_paren_enclosed,
        },
        .end = index,
    };
}

fn parseDefinitionMarker(source: [*:0]const u8, start_index: u32) ?Marker {
    var index = start_index;
    incrementIfCharacter(source, &index, ':') orelse return null;
    //incrementIfInList(source, &index, " \n") orelse return null;
    return Marker{
        .style = .definition,
        .end = index,
    };
}

fn parseBulletMarker(source: [*:0]const u8, start_index: u32) ?Marker {
    var index = start_index;

    const style = switch (source[index]) {
        '*' => Style.asterisk,
        '-' => Style.hyphen,
        '+' => Style.plus,
        else => return null,
    };
    index += 1;

    if (incrementIfCheckBox(source, &index)) |_| {
        return Marker{
            .style = switch (style) {
                .asterisk => .asterisk_task,
                .hyphen => .hyphen_task,
                .plus => .plus_task,
                else => return null,
            },
            .end = index,
        };
    }

    //incrementIfInList(source, &index, " \n") orelse return null;

    return Marker{
        .style = style,
        .end = index,
    };
}

fn incrementIfCheckBox(source: [*:0]const u8, index: *u32) ?void {
    var i = index.*;
    incrementIfCharacter(source, &i, ' ') orelse return null;
    incrementIfCharacter(source, &i, '[') orelse return null;
    incrementIfInList(source, &i, " xX") orelse return null;
    incrementIfCharacter(source, &i, ']') orelse return null;
    //incrementIfInList(source, &i, " \n") orelse return null;
    index.* = i;
}

fn parseOrderedMarker(source: [*:0]const u8, start_index: u32) ?Marker {
    const text = parseOrderedMarkerText(source, start_index) orelse return null;
    var index = text.end;

    const is_period = switch (source[index]) {
        '.' => true,
        ')' => false,
        else => return null,
    };
    index += 1;

    //incrementIfInList(source, &index, " \n") orelse return null;

    if (is_period) {
        return Marker{
            .style = switch (text.style) {
                .decimal => .decimal_period,
                .lower_roman => .lower_roman_period,
                .upper_roman => .upper_roman_period,
                .lower_alpha => .lower_alpha_period,
                .upper_alpha => .upper_alpha_period,
            },
            .end = index,
        };
    } else {
        return Marker{
            .style = switch (text.style) {
                .decimal => .decimal_paren,
                .lower_roman => .lower_roman_paren,
                .upper_roman => .upper_roman_paren,
                .lower_alpha => .lower_alpha_paren,
                .upper_alpha => .upper_alpha_paren,
            },
            .end = index,
        };
    }
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
    end: u32,
};

fn parseOrderedMarkerText(source: [*:0]const u8, start_index: u32) ?MarkerText {
    var res = MarkerText{
        .end = start_index,
        .style = switch (source[start_index]) {
            '0'...'9' => .decimal,
            'I', 'V', 'X', 'L', 'C', 'D', 'M' => .upper_roman,
            'i', 'v', 'x', 'l', 'c', 'd', 'm' => .lower_roman,
            'A'...'B', 'E'...'H', 'J'...'K', 'N'...'U', 'W', 'Y', 'Z' => .upper_alpha,
            'a'...'b', 'e'...'h', 'j'...'k', 'n'...'u', 'w', 'y', 'z' => .lower_alpha,
            else => return null,
        },
    };
    switch (res.style) {
        .decimal => while (incrementIfInRange(source, &res.end, '0', '9')) |_| {},
        .lower_alpha => while (incrementIfInRange(source, &res.end, 'a', 'z')) |_| {},
        .upper_alpha => while (incrementIfInRange(source, &res.end, 'A', 'Z')) |_| {},
        .lower_roman => {
            while (incrementIfInList(source, &res.end, "ivxlcdm")) |_| {}
            if (incrementIfInRange(source, &res.end, 'a', 'z')) |_| {
                res.style = .lower_alpha;
                while (incrementIfInRange(source, &res.end, 'a', 'z')) |_| {}
            }
        },
        .upper_roman => {
            while (incrementIfInList(source, &res.end, "IVXLCDM")) |_| {}
            if (incrementIfInRange(source, &res.end, 'A', 'Z')) |_| {
                res.style = .upper_alpha;
                while (incrementIfInRange(source, &res.end, 'A', 'Z')) |_| {}
            }
        },
    }
    return res;
}

fn incrementIfCharacter(source: [*:0]const u8, index: *u32, c: u8) ?void {
    if (source[index.*] == c) {
        index.* += 1;
        return;
    }
    return null;
}

fn incrementIfInRange(source: [*:0]const u8, index: *u32, low: u8, high: u8) ?void {
    if (low <= source[index.*] and source[index.*] <= high) {
        index.* += 1;
        return;
    }
    return null;
}

fn incrementIfInList(source: [*:0]const u8, index: *u32, list: []const u8) ?void {
    if (std.mem.indexOfScalar(u8, list, source[index.*])) |_| {
        index.* += 1;
        return;
    }
    return null;
}

fn incrementIfString(source: [*:0]const u8, index: *u32, string: []const u8) ?void {
    var i = index.*;
    for (string) |c| {
        incrementIfCharacter(source, &i, c) orelse return null;
    }
    index.* = i;
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

fn expectParseStyle(source: [*:0]const u8, expected: Style) !void {
    const marker = parse(source, 0) orelse return error.ParsedNull;
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

fn expectParseText(source: [*:0]const u8, expected: []const u8) !void {
    const marker = parse(source, 0) orelse return error.ParsedNull;
    try std.testing.expectEqualStrings(expected, source[0..marker.end]);
}

fn beep(src: std.builtin.SourceLocation, input: anytype) @TypeOf(input) {
    std.debug.print("{s}:{} {}\n", .{ src.fn_name, src.line, input });
    return input;
}
