const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.fenced_divs 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\:::::::::: foo
        \\Hi
        \\
        \\> A block quote.
        \\:::::::::::
        \\
    ,
        \\<div class="foo">
        \\<p>Hi</p>
        \\<blockquote>
        \\<p>A block quote.</p>
        \\</blockquote>
        \\</div>
        \\
    );
}

test "html.fenced_divs 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#bar .foo}
        \\:::
        \\Hi
        \\
        \\> A block quote.
        \\:::::::::::::
        \\
    ,
        \\<div id="bar" class="foo">
        \\<p>Hi</p>
        \\<blockquote>
        \\<p>A block quote.</p>
        \\</blockquote>
        \\</div>
        \\
    );
}

test "html.fenced_divs 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{#bar .foo}
        \\::::
        \\Hi
        \\
        \\::: baz
        \\> A block quote.
        \\:::
        \\::::
        \\
    ,
        \\<div id="bar" class="foo">
        \\<p>Hi</p>
        \\<div class="baz">
        \\<blockquote>
        \\<p>A block quote.</p>
        \\</blockquote>
        \\</div>
        \\</div>
        \\
    );
}

test "html.fenced_divs 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\Paragraph text
        \\::::
        \\Hi
        \\::::
        \\
    ,
        \\<p>Paragraph text
        \\::::
        \\Hi
        \\::::</p>
        \\
    );
}

test "html.fenced_divs 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\::::
        \\Hi
        \\::::
        \\
    ,
        \\<div>
        \\<p>Hi</p>
        \\</div>
        \\
    );
}

test "html.fenced_divs 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\::::::::: foo
        \\Hi
        \\::::
        \\
    ,
        \\<div class="foo">
        \\<p>Hi
        \\::::</p>
        \\</div>
        \\
    );
}

test "html.fenced_divs 6" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\> :::: foo
        \\> Hi
        \\
    ,
        \\<blockquote>
        \\<div class="foo">
        \\<p>Hi</p>
        \\</div>
        \\</blockquote>
        \\
    );
}
