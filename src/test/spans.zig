const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.spans 0" {
    try testDjotToHtml(
        \\This is a [test of
        \\*color*]{.blue}.
        \\
    ,
        \\<p>This is a <span class="blue">test of
        \\<strong>color</strong></span>.</p>
        \\
    );
}

test "html.spans 1" {
    try testDjotToHtml(
        \\not a [span] {#id}.
        \\
    ,
        \\<p>not a [span] .</p>
        \\
    );
}

test "html.spans 2" {
    try testDjotToHtml(
        \\[nested [span]{.blue}]{#ident}
        \\
    ,
        \\<p><span id="ident">nested <span class="blue">span</span></span></p>
        \\
    );
}

