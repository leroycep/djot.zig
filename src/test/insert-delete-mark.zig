const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.insert-delete-mark 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\This is {-deleted
        \\_text_-}. The braces are -required-.
        \\And they must be in the -}right order{-.
        \\
    ,
        \\<p>This is <del>deleted
        \\<em>text</em></del>. The braces are -required-.
        \\And they must be in the -}right order{-.</p>
        \\
    );
}

test "html.insert-delete-mark 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{+ Inserted text +}
        \\
    ,
        \\<p><ins> Inserted text </ins></p>
        \\
    );
}

test "html.insert-delete-mark 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{--hello--}
        \\
    ,
        \\<p><del>-hello-</del></p>
        \\
    );
}

test "html.insert-delete-mark 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\This is {=marked *text*=}.
        \\
    ,
        \\<p>This is <mark>marked <strong>text</strong></mark>.</p>
        \\
    );
}
