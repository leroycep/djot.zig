const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.thematic_breaks 0" {
    try testDjotToHtml(
        \\hello
        \\
        \\- - -
        \\
        \\there
        \\
    ,
        \\<p>hello</p>
        \\<hr>
        \\<p>there</p>
        \\
    );
}

test "html.thematic_breaks 1" {
    try testDjotToHtml(
        \\hello
        \\
        \\   **   **
        \\
        \\there
        \\
    ,
        \\<p>hello</p>
        \\<hr>
        \\<p>there</p>
        \\
    );
}

test "html.thematic_breaks 2" {
    try testDjotToHtml(
        \\hello
        \\
        \\   *-*-*-*
        \\
        \\there
        \\
    ,
        \\<p>hello</p>
        \\<hr>
        \\<p>there</p>
        \\
    );
}

test "html.thematic_breaks 3" {
    try testDjotToHtml(
        \\hello
        \\   *-*-*-*
        \\there
        \\
    ,
        \\<p>hello
        \\<strong>-</strong>-<strong>-</strong>
        \\there</p>
        \\
    );
}

