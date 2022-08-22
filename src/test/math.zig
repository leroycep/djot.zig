const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.math 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\$`e=mc^2`
        \\
    ,
        \\<p><span class="math inline">\(e=mc^2\)</span></p>
        \\
    );
}

test "html.math 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\My equation: $`e=mc^2`
        \\
    ,
        \\<p>My equation: <span class="math inline">\(e=mc^2\)</span></p>
        \\
    );
}

test "html.math 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\$$`e=mc^2`
        \\
    ,
        \\<p><span class="math display">\[e=mc^2\]</span></p>
        \\
    );
}

test "html.math 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\My equation: $$`e=mc^2`
        \\
    ,
        \\<p>My equation: <span class="math display">\[e=mc^2\]</span></p>
        \\
    );
}

test "html.math 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\$`e=
        \\mc^2`
        \\
    ,
        \\<p><span class="math inline">\(e=
        \\mc^2\)</span></p>
        \\
    );
}

test "html.math 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\$`e=\text{the number $\pi$}`
        \\
    ,
        \\<p><span class="math inline">\(e=\text{the number $\pi$}\)</span></p>
        \\
    );
}
