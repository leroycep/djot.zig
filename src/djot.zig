const std = @import("std");
const blocks = @import("./Block.zig");
const Marker = @import("./Marker.zig");
const Token = @import("./Token.zig");
const bolt = @import("./bolt.zig");

const LEFT_DOUBLE_QUOTE = '“';
const RIGHT_DOUBLE_QUOTE = '”';
const LEFT_SINGLE_QUOTE = '‘';
const RIGHT_SINGLE_QUOTE = '’';

pub fn toHtml(allocator: std.mem.Allocator, source: []const u8, html_writer: anytype) !void {
    var doc = try parse(allocator, source);
    defer doc.deinit(allocator);

    var in_alt_text: u32 = 0;

    for (doc.events.items(.tag)) |event_kind, event_index| {
        switch (event_kind) {
            .text,
            .escaped,
            => {
                const t = doc.asText(event_index);
                var i: usize = 0;
                while (i < t.len) {
                    const codepoint_length = try std.unicode.utf8ByteSequenceLength(t[i]);
                    // TODO: check this earlier?
                    if (i + codepoint_length > t.len) return error.InvalidUTF8;
                    switch (try std.unicode.utf8Decode(t[i..][0..codepoint_length])) {
                        '…' => try html_writer.writeAll("&hellip;"),
                        '–' => try html_writer.writeAll("&ndash;"),
                        '—' => try html_writer.writeAll("&mdash;"),
                        LEFT_DOUBLE_QUOTE => try html_writer.writeAll("&ldquo;"),
                        RIGHT_DOUBLE_QUOTE => try html_writer.writeAll("&rdquo;"),
                        LEFT_SINGLE_QUOTE => try html_writer.writeAll("&lsquo;"),
                        RIGHT_SINGLE_QUOTE => try html_writer.writeAll("&rsquo;"),
                        else => try html_writer.writeAll(t[i..][0..codepoint_length]),
                    }
                    i += codepoint_length;
                }
            },

            .autolink => {
                const url = doc.asText(event_index);
                try html_writer.print("<a href=\"{}\">{s}</a>", .{ std.zig.fmtEscapes(url), url });
            },
            .autolink_email => {
                const email = doc.asText(event_index);
                try html_writer.print("<a href=\"mailto:{}\">{s}</a>", .{ std.zig.fmtEscapes(email), email });
            },

            .start_link => if (in_alt_text < 1) {
                // Remove newlines from the url
                const url = doc.asText(event_index);
                var lines = std.mem.split(u8, url, "\n");

                try html_writer.writeAll("<a href=\"");
                while (lines.next()) |line| {
                    try html_writer.writeAll(line);
                }
                try html_writer.writeAll("\">");
            },
            .close_link => if (in_alt_text < 1) {
                try html_writer.writeAll("</a>");
            },

            .start_image_link => {
                try html_writer.writeAll("<img alt=\"");
                in_alt_text += 1;
            },
            .close_image_link => {
                // Remove newlines from the url
                const url = doc.asText(event_index);
                var lines = std.mem.split(u8, url, "\n");

                try html_writer.writeAll("\" src=\"");
                while (lines.next()) |line| {
                    try html_writer.writeAll(line);
                }
                try html_writer.writeAll("\">");
                in_alt_text -= 1;
            },

            .start_paragraph => try html_writer.writeAll("<p>"),
            .close_paragraph => try html_writer.writeAll("</p>\n"),

            .start_heading => try html_writer.print("<h{}>", .{doc.events.items(.data)[event_index].start_heading}),
            .close_heading => try html_writer.print("</h{}>", .{doc.events.items(.data)[event_index].close_heading}),

            .start_list => try html_writer.writeAll("<ul>"),
            .close_list => try html_writer.writeAll("</ul>"),

            .start_list_item => try html_writer.writeAll("<li>"),
            .close_list_item => try html_writer.writeAll("</li>"),

            .start_quote => try html_writer.writeAll("<quote>"),
            .close_quote => try html_writer.writeAll("</quote>"),

            .start_verbatim => try html_writer.writeAll("<code>"),
            .close_verbatim => try html_writer.writeAll("</code>"),

            .start_strong => try html_writer.writeAll("<strong>"),
            .close_strong => try html_writer.writeAll("</strong>"),

            .start_emphasis => try html_writer.writeAll("<em>"),
            .close_emphasis => try html_writer.writeAll("</em>"),
        }
    }
}

pub const Document = struct {
    source: []const u8,
    events: std.MultiArrayList(StructTaggedUnion(Event)).Slice,

    pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        this.events.deinit(allocator);
    }

    pub fn event(this: @This(), index: usize) Event {
        const struct_tag_union = StructTaggedUnion(Event){
            .tag = this.events.items(.tag)[index],
            .data = this.events.items(.data)[index],
        };
        return struct_tag_union.toUnion();
    }

    pub fn asText(this: @This(), index: usize) []const u8 {
        return this.event(index).asText(this.source);
    }
};

pub const Event = union(Kind) {
    text: SourceIndex,
    escaped: SourceIndex,
    autolink: SourceIndex,
    autolink_email: SourceIndex,

    start_paragraph,
    close_paragraph,

    start_heading: u32,
    close_heading: u32,

    start_quote,
    close_quote,

    start_list: List,
    close_list: List,

    start_list_item: SourceIndex,
    close_list_item: SourceIndex,

    // Inline verbatim text
    start_verbatim,
    close_verbatim,

    start_strong,
    close_strong,

    start_emphasis,
    close_emphasis,

    start_link: SourceIndex,
    close_link: SourceIndex,

    start_image_link: SourceIndex,
    close_image_link: SourceIndex,

    pub const List = struct {
        style: Marker.Style,
    };

    const SourceIndex = u32;

    pub const Kind = enum {
        text,
        escaped,
        autolink,
        autolink_email,

        start_paragraph,
        close_paragraph,

        start_heading,
        close_heading,

        start_quote,
        close_quote,

        start_list,
        close_list,

        start_list_item,
        close_list_item,

        start_verbatim,
        close_verbatim,

        start_strong,
        close_strong,

        start_emphasis,
        close_emphasis,

        start_link,
        close_link,

        start_image_link,
        close_image_link,
    };

    /// Only valid for events with a SourceIndex payload
    pub fn asText(this: @This(), source: []const u8) []const u8 {
        switch (this) {
            .text => |source_index| {
                const token = Token.parse(source, source_index);
                return source[token.start..token.end];
            },

            .autolink, .autolink_email => |source_index| {
                const token = Token.parse(source, source_index);
                return source[token.start + 1 .. token.end - 1];
            },

            .escaped => |source_index| {
                const token = Token.parse(source, source_index);
                return source[token.start + 1 .. token.end];
            },

            .start_list_item,
            .close_list_item,
            => |source_index| {
                var source_pos: usize = source_index;
                const marker = Marker.parse(source, &source_pos).?;
                return source[marker.start..marker.end];
            },

            .start_link,
            .close_link,
            .start_image_link,
            .close_image_link,
            => |source_index| {
                const token = Token.parse(source, source_index);
                return source[token.start + 2 .. token.end - 1];
            },

            else => std.debug.panic("Event {s} does not have associated text", .{std.meta.tagName(this)}),
        }
    }

    pub fn fmtWithSource(this: @This(), source: []const u8) FmtWithSource {
        return FmtWithSource{ .event = this, .source = source };
    }

    pub const FmtWithSource = struct {
        event: Event,
        source: []const u8,

        pub fn format(
            this: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s}", .{std.meta.tagName(this.event)});
            switch (this.event) {
                .text,
                .escaped,
                .autolink,
                .autolink_email,
                .start_list_item,
                .close_list_item,
                .start_link,
                .close_link,
                .start_image_link,
                .close_image_link,
                => |_| try writer.print(" \"{}\"", .{std.zig.fmtEscapes(this.event.asText(this.source))}),

                .start_heading,
                .close_heading,
                => |level| try writer.print(" {}", .{level}),

                .start_list,
                .close_list,
                => |list| try writer.print(" {s}", .{std.meta.tagName(list.style)}),

                // Events that are only tags just print the tag name
                .start_paragraph,
                .close_paragraph,
                .start_quote,
                .close_quote,
                .start_verbatim,
                .close_verbatim,
                .start_strong,
                .close_strong,
                .start_emphasis,
                .close_emphasis,
                => {},
            }
        }
    };
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) Error!Document {
    var tokens = try Token.parseAll(allocator, source);
    defer tokens.deinit(allocator);

    var events = std.MultiArrayList(StructTaggedUnion(Event)){};
    defer events.deinit(allocator);

    var event_cursor = EventCursor{
        .allocator = allocator,
        .events = &events,
        .index = 0,
    };
    var tok_cursor = TokCursor{
        .source = source,
        .tokens = &tokens,
        .index = 0,
    };

    _ = try blocks.parseBlocks(&event_cursor, &tok_cursor, null);

    events.len = event_cursor.index;

    return Document{
        .source = source,
        .events = events.toOwnedSlice(),
    };
}

pub const EventCursor = struct {
    allocator: std.mem.Allocator,
    events: *std.MultiArrayList(StructTaggedUnion(Event)),
    index: Index,

    pub const Index = u32;

    pub fn append(this: *@This(), event: Event) !Index {
        const index = this.index;
        this.index += 1;
        try this.events.resize(this.allocator, index + 1);

        this.events.set(index, StructTaggedUnion(Event).fromUnion(event));

        return index;
    }

    pub fn set(this: *@This(), index: Index, event: Event) void {
        std.debug.assert(index < this.index);
        this.events.set(index, StructTaggedUnion(Event).fromUnion(event));
    }
};

// Takes a `union(enum)` and returns a struct with an untagged union and a
// and a tag field.
pub fn StructTaggedUnion(TaggedUnion: type) type {
    std.debug.assert(std.meta.activeTag(@typeInfo(TaggedUnion)) == .Union);
    const tagged_union_info = @typeInfo(TaggedUnion).Union;
    std.debug.assert(tagged_union_info.tag_type != null);

    const Tag = std.meta.Tag(TaggedUnion);
    const UntaggedUnion = @Type(.{ .Union = .{
        .tag_type = null,
        .layout = tagged_union_info.layout,
        .decls = &.{},
        .fields = tagged_union_info.fields,
    } });

    return struct {
        tag: Tag,
        data: UntaggedUnion,

        pub fn fromUnion(tagged_union: TaggedUnion) @This() {
            const tag = std.meta.activeTag(tagged_union);
            inline for (tagged_union_info.fields) |field| {
                if (tag == std.meta.stringToEnum(Tag, field.name).?) {
                    const tag_name = field.name;
                    return @This(){
                        .tag = std.meta.activeTag(tagged_union),
                        .data = @unionInit(UntaggedUnion, tag_name, @field(tagged_union, tag_name)),
                    };
                }
            }
            std.debug.panic("Unable to find matching tag; perhaps the tag is undefined? {}", .{tag});
        }

        pub fn toUnion(this: @This()) TaggedUnion {
            inline for (tagged_union_info.fields) |field| {
                if (this.tag == std.meta.stringToEnum(Tag, field.name).?) {
                    const tag_name = field.name;
                    return @unionInit(TaggedUnion, tag_name, @field(this.data, tag_name));
                }
            }
            std.debug.panic("Unable to find matching tag; perhaps the tag is undefined? {}", .{this.tag});
        }
    };
}

pub const TokCursor = struct {
    source: []const u8,
    tokens: *const Token.Slice,
    index: Index,

    pub const Index = u32;

    /// Create TokCursor with the specified index
    pub fn withIndex(this: @This(), index: Index) @This() {
        return @This(){
            .source = this.source,
            .tokens = this.tokens,
            .index = index,
        };
    }

    pub fn current(this: @This()) ?Token.Tok {
        if (this.index < this.tokens.len) {
            return this.tokOf(this.index);
        }
        return null;
    }

    pub fn next(this: *@This()) ?Token.Tok {
        const index = this.index;
        if (bolt.raw.next(Token.Kind, Index, this.tokens.items(.kind), &this.index)) |kind| {
            return Token.Tok{
                .start = this.tokens.items(.start)[index],
                .kind = kind,
            };
        }
        return null;
    }

    pub fn expect(this: *@This(), expected: Token.Kind) ?Index {
        return bolt.raw.expect(Token.Kind, Index, this.tokens.items(.kind), &this.index, expected);
    }

    pub fn expectInList(this: *@This(), list: []const Token.Kind) ?Index {
        return bolt.raw.expectInList(Token.Kind, Index, this.tokens.items(.kind), &this.index, list);
    }

    pub fn expectString(this: *@This(), string: []const Token.Kind) ?[2]Index {
        return bolt.raw.expectString(Token.Kind, Index, this.tokens.items(.kind), &this.index, string);
    }

    pub fn startOf(this: @This(), index: Index) u32 {
        return this.tokens.items(.start)[index];
    }

    pub fn kindOf(this: @This(), index: Index) Token.Kind {
        return this.tokens.items(.kind)[index];
    }

    pub fn tokOf(this: @This(), index: Index) Token.Tok {
        return Token.Tok{
            .start = this.startOf(index),
            .kind = this.kindOf(index),
        };
    }

    pub fn token(this: @This(), index: Index) Token {
        return Token.parse(this.source, this.tokens.items(.start)[index]);
    }

    pub fn text(this: @This(), index: Index) []const u8 {
        const tok = this.token(index);
        return this.source[tok.start..tok.end];
    }
};

pub const Error = std.mem.Allocator.Error || error{
    // TODO: Remove this
    WouldLoop,
};

comptime {
    _ = @import("./Block.zig");
}
