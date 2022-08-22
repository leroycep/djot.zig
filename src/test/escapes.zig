const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.escapes 0" {
    try testDjotToHtml(
        \\\`\*\_\[\#
        \\
    ,
        \\<p>`*_[#</p>
        \\
    );
}

test "html.escapes 1" {
    try testDjotToHtml(
        \\\a\«
        \\
    ,
        \\<p>\a\«</p>
        \\
    );
}

test "html.escapes 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\ab\
        \\c
        \\
    ,
        \\<p>ab<br>
        \\c</p>
        \\
    );
}

test "html.escapes 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\ab\	  
        \\c
        \\
    ,
        \\<p>ab<br>
        \\c</p>
        \\
    );
}

test "html.escapes 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\ab 	 \  	
        \\c
        \\
    ,
        \\<p>ab<br>
        \\c</p>
        \\
    );
}

test "html.escapes 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\a\ b
        \\
    ,
        \\<p>a&nbsp;b</p>
        \\
    );
}
