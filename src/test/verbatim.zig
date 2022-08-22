const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.verbatim 0" {
    try testDjotToHtml(
        \\Some `code`
        \\
    ,
        \\<p>Some <code>code</code></p>
        \\
    );
}

test "html.verbatim 1" {
    try testDjotToHtml(
        \\Some `code
        \\with a line break`
        \\
    ,
        \\<p>Some <code>code
        \\with a line break</code></p>
        \\
    );
}

test "html.verbatim 2" {
    try testDjotToHtml(
        \\Special characters: `*hi*`
        \\
    ,
        \\<p>Special characters: <code>*hi*</code></p>
        \\
    );
}

test "html.verbatim 3" {
    try testDjotToHtml(
        \\*foo`*`
        \\
    ,
        \\<p>*foo<code>*</code></p>
        \\
    );
}

test "html.verbatim 4" {
    try testDjotToHtml(
        \\`````a`a``a```a````a``````a`````
        \\
    ,
        \\<p><code>a`a``a```a````a``````a</code></p>
        \\
    );
}

test "html.verbatim 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\` ``a`` `
        \\
    ,
        \\<p><code>``a``</code></p>
        \\
    );
}

test "html.verbatim 6" {
    try testDjotToHtml(
        \\` a
        \\c
        \\
    ,
        \\<p><code> a
        \\c</code></p>
        \\
    );
}
