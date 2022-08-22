const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.emoji 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\:+1: :scream:
        \\
    ,
        \\<p>👍 😱</p>
        \\
    );
}

test "html.emoji 1" {
    try testDjotToHtml(
        \\This is a :nonexistent: emoji.
        \\
    ,
        \\<p>This is a :nonexistent: emoji.</p>
        \\
    );
}

test "html.emoji 2" {
    try testDjotToHtml(
        \\:ice:scream:
        \\
    ,
        \\<p>:ice:scream:</p>
        \\
    );
}
