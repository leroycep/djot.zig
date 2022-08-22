const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.super-subscript 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\H~2~O
        \\
    ,
        \\<p>H<sub>2</sub>O</p>
        \\
    );
}

test "html.super-subscript 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\mc^2^
        \\
    ,
        \\<p>mc<sup>2</sup></p>
        \\
    );
}

test "html.super-subscript 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\test^of superscript ~with subscript~^
        \\
    ,
        \\<p>test<sup>of superscript <sub>with subscript</sub></sup></p>
        \\
    );
}

test "html.super-subscript 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\H{~2 ~}O
        \\
    ,
        \\<p>H<sub>2 </sub>O</p>
        \\
    );
}
