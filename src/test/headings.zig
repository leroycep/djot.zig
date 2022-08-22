const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.headings 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\## Heading
        \\
    ,
        \\<h2 id="Heading">Heading</h2>
        \\
    );
}

test "html.headings 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\# Heading
        \\# another
        \\
    ,
        \\<h1 id="Heading">Heading</h1>
        \\<h1 id="another">another</h1>
        \\
    );
}

test "html.headings 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\##
        \\heading
        \\
        \\para
        \\
    ,
        \\<h2 id="heading">heading</h2>
        \\<p>para</p>
        \\
    );
}

test "html.headings 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\##
        \\
    ,
        \\<h2 id=""></h2>
        \\
    );
}

test "html.headings 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\## Heading
        \\### Next level
        \\
    ,
        \\<h2 id="Heading">Heading</h2>
        \\<h3 id="Next-level">Next level</h3>
        \\
    );
}

test "html.headings 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\# Heading
        \\lazy
        \\
    ,
        \\<h1 id="Heading-lazy">Heading
        \\lazy</h1>
        \\
    );
}

test "html.headings 6" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\##Notheading
        \\
    ,
        \\<p>##Notheading</p>
        \\
    );
}

test "html.headings 7" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\   ##    Heading
        \\
    ,
        \\<h2 id="Heading">Heading</h2>
        \\
    );
}

test "html.headings 8" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\## heading ##
        \\
    ,
        \\<h2 id="heading">heading</h2>
        \\
    );
}

test "html.headings 9" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\## heading \##
        \\
    ,
        \\<h2 id="heading">heading ##</h2>
        \\
    );
}

test "html.headings 10" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#Foo-bar}
        \\Paragraph
        \\
        \\# Foo bar
        \\
        \\## Foo  bar
        \\
        \\{#baz}
        \\# Foo bar
        \\
    ,
        \\<p id="Foo-bar">Paragraph</p>
        \\<h1 id="Foo-bar1">Foo bar</h1>
        \\<h2 id="Foo-bar2">Foo  bar</h2>
        \\<h1 id="baz">Foo bar</h1>
        \\
    );
}

test "html.headings 11" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\See [Introduction][].
        \\
        \\# Introduction
        \\
    ,
        \\<p>See <a href="#Introduction">Introduction</a>.</p>
        \\<h1 id="Introduction">Introduction</h1>
        \\
    );
}

test "html.headings 12" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\See [Introduction][].
        \\
        \\{#foo}
        \\# Introduction
        \\
    ,
        \\<p>See <a href="#foo">Introduction</a>.</p>
        \\<h1 id="foo">Introduction</h1>
        \\
    );
}

test "html.headings 13" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\See [Introduction][].
        \\
        \\# Introduction
        \\
        \\[Introduction]: #bar
        \\
    ,
        \\<p>See <a href="#bar">Introduction</a>.</p>
        \\<h1 id="Introduction">Introduction</h1>
        \\
    );
}
