const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.raw 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\`<a>`{=html}
        \\
    ,
        \\<p><a></p>
        \\
    );
}

test "html.raw 1" {
    try testDjotToHtml(
        \\``` =html
        \\<table>
        \\```
        \\
    ,
        \\<table>
        \\
    );
}

test "html.raw 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\`<b>foo</b>`{=html #id}
        \\```
        \\
    ,
        \\<p><code>&lt;b&gt;foo&lt;/b&gt;</code>{=html #id}
        \\<code></code></p>
        \\
    );
}

test "html.raw 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{.foo}
        \\``` =html
        \\<table>
        \\```
        \\
    ,
        \\<table>
        \\
    );
}
