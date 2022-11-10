const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.attributes 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\a *b{#id key="*"}*
        \\
    ,
        \\<p>a <strong><span id="id" key="*">b</span></strong></p>
        \\
    );
}

test "html.attributes 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\a *b{#id key="*"}o
        \\
    ,
        \\<p>a *<span id="id" key="*">b</span>o</p>
        \\
    );
}

test "html.attributes 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\hi{key="{#hi"}
        \\
    ,
        \\<p>hi{key=&ldquo;{#hi&rdquo;</p>
        \\
    );
}

test "html.attributes 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\hi\{key="abc{#hi}"
        \\
    ,
        \\<p>hi{key=&ldquo;<span id="hi">abc</span>&rdquo;</p>
        \\
    );
}

test "html.attributes 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\hi{key="\{#hi"}
        \\
    ,
        \\<p><span key="{#hi">hi</span></p>
        \\
    );
}

test "html.attributes 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\hi{#id .class
        \\key="value"}
        \\
    ,
        \\<p><span id="id" class="class" key="value">hi</span></p>
        \\
    );
}

test "html.attributes 6" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#id} at beginning
        \\
    ,
        \\<p> at beginning</p>
        \\
    );
}

test "html.attributes 7" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\After {#id} space
        \\{.class}
        \\
    ,
        \\<p>After  space
        \\</p>
        \\
    );
}

test "html.attributes 8" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#id .class}
        \\A paragraph
        \\
    ,
        \\<p id="id" class="class">A paragraph</p>
        \\
    );
}

test "html.attributes 9" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#id .class
        \\  style="color:red"}
        \\A paragraph
        \\
    ,
        \\<p id="id" class="class" style="color:red">A paragraph</p>
        \\
    );
}

test "html.attributes 10" {
    try testDjotToHtml(
        \\{#id .cla*ss*
        \\
    ,
        \\<p>{#id .cla<strong>ss</strong></p>
        \\
    );
}

test "html.attributes 11" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#id}
        \\{key=val}
        \\{.foo .bar}
        \\{key=val2}
        \\{.baz}
        \\{#id2}
        \\Okay
        \\
    ,
        \\<p id="id2" key="val2" class="foo bar baz">Okay</p>
        \\
    );
}

test "html.attributes 12" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#id}
        \\> Block quote
        \\
    ,
        \\<blockquote id="id">
        \\<p>Block quote</p>
        \\</blockquote>
        \\
    );
}

test "html.attributes 13" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#id}
        \\# Heading
        \\
    ,
        \\<h1 id="id">Heading</h1>
        \\
    );
}

test "html.attributes 14" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{.blue}
        \\- - - - -
        \\
    ,
        \\<hr class="blue">
        \\
    );
}

test "html.attributes 15" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{highlight=3}
        \\``` ruby
        \\x = 3
        \\```
        \\
    ,
        \\<pre highlight="3"><code class="language-ruby">x = 3
        \\</code></pre>
        \\
    );
}

test "html.attributes 16" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{.special}
        \\1. one
        \\2. two
        \\
    ,
        \\<ol class="special">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.attributes 17" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\> {.foo}
        \\> > {.bar}
        \\> > nested
        \\
    ,
        \\<blockquote>
        \\<blockquote class="foo">
        \\<p class="bar">nested</p>
        \\</blockquote>
        \\</blockquote>
        \\
    );
}

test "html.attributes 18" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\foo{#ident % this is a comment % .class}
        \\
    ,
        \\<p><span id="ident" class="class">foo</span></p>
        \\
    );
}

test "html.attributes 19" {
    try testDjotToHtml(
        \\{% This is  a comment before a
        \\  block-level item. %}
        \\Paragraph.
        \\
    ,
        \\<p>Paragraph.</p>
        \\
    );
}
