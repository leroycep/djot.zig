const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.raw 0" {
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

