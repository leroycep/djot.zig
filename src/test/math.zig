const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.math 0" {
    try testDjotToHtml(
        \\$`e=mc^2`
        \\
    ,
        \\<p><span class="math inline">\(e=mc^2\)</span></p>
        \\
    );
}

test "html.math 1" {
    try testDjotToHtml(
        \\My equation: $`e=mc^2`
        \\
    ,
        \\<p>My equation: <span class="math inline">\(e=mc^2\)</span></p>
        \\
    );
}

test "html.math 2" {
    try testDjotToHtml(
        \\$$`e=mc^2`
        \\
    ,
        \\<p><span class="math display">\[e=mc^2\]</span></p>
        \\
    );
}

test "html.math 3" {
    try testDjotToHtml(
        \\My equation: $$`e=mc^2`
        \\
    ,
        \\<p>My equation: <span class="math display">\[e=mc^2\]</span></p>
        \\
    );
}

test "html.math 4" {
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
    try testDjotToHtml(
        \\$`e=\text{the number $\pi$}`
        \\
    ,
        \\<p><span class="math inline">\(e=\text{the number $\pi$}\)</span></p>
        \\
    );
}

