const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.blockquote 0" {
    try testDjotToHtml(
        \\> Basic
        \\> block _quote_.
        \\
    ,
        \\<blockquote>
        \\<p>Basic
        \\block <em>quote</em>.</p>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 1" {
    try testDjotToHtml(
        \\> Lazy
        \\block _quote_.
        \\
    ,
        \\<blockquote>
        \\<p>Lazy
        \\block <em>quote</em>.</p>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 2" {
    try testDjotToHtml(
        \\> block
        \\>
        \\> quote
        \\
    ,
        \\<blockquote>
        \\<p>block</p>
        \\<p>quote</p>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 3" {
    try testDjotToHtml(
        \\> block
        \\
        \\> quote
        \\
    ,
        \\<blockquote>
        \\<p>block</p>
        \\</blockquote>
        \\<blockquote>
        \\<p>quote</p>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 4" {
    try testDjotToHtml(
        \\> > > nested
        \\
    ,
        \\<blockquote>
        \\<blockquote>
        \\<blockquote>
        \\<p>nested</p>
        \\</blockquote>
        \\</blockquote>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\> > > nested
        \\lazy
        \\
    ,
        \\<blockquote>
        \\<blockquote>
        \\<blockquote>
        \\<p>nested
        \\lazy</p>
        \\</blockquote>
        \\</blockquote>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 6" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\> > > nested
        \\> lazy
        \\
    ,
        \\<blockquote>
        \\<blockquote>
        \\<blockquote>
        \\<p>nested
        \\lazy</p>
        \\</blockquote>
        \\</blockquote>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 7" {
    try testDjotToHtml(
        \\> nested
        \\>
        \\> > more
        \\
    ,
        \\<blockquote>
        \\<p>nested</p>
        \\<blockquote>
        \\<p>more</p>
        \\</blockquote>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 8" {
    try testDjotToHtml(
        \\>not blockquote
        \\
    ,
        \\<p>&gt;not blockquote</p>
        \\
    );
}

test "html.blockquote 9" {
    try testDjotToHtml(
        \\>> not blockquote
        \\
    ,
        \\<p>&gt;&gt; not blockquote</p>
        \\
    );
}

test "html.blockquote 10" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\>
        \\
    ,
        \\<blockquote>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 11" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\> # Heading
        \\
    ,
        \\<blockquote>
        \\<h1 id="Heading">Heading</h1>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 12" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\> hi
        \\>there
        \\
    ,
        \\<blockquote>
        \\<p>hi
        \\&gt;there</p>
        \\</blockquote>
        \\
    );
}

test "html.blockquote 13" {
    try testDjotToHtml(
        \\aaa
        \\> bbb
        \\
    ,
        \\<p>aaa
        \\&gt; bbb</p>
        \\
    );
}

test "html.blockquote 14" {
    try testDjotToHtml(
        \\aaa
        \\
        \\> bbb
        \\
    ,
        \\<p>aaa</p>
        \\<blockquote>
        \\<p>bbb</p>
        \\</blockquote>
        \\
    );
}
