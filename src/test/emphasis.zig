const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.emphasis 0" {
    try testDjotToHtml(
        \\*foo bar*
        \\
    ,
        \\<p><strong>foo bar</strong></p>
        \\
    );
}

test "html.emphasis 1" {
    try testDjotToHtml(
        \\a* foo bar*
        \\
    ,
        \\<p>a* foo bar*</p>
        \\
    );
}

test "html.emphasis 2" {
    try testDjotToHtml(
        \\*foo bar *
        \\
    ,
        \\<p>*foo bar *</p>
        \\
    );
}

test "html.emphasis 3" {
    try testDjotToHtml(
        \\* a *
        \\
    ,
        \\<p><strong> a </strong></p>
        \\
    );
}

test "html.emphasis 4" {
    try testDjotToHtml(
        \\foo*bar*baz
        \\
    ,
        \\<p>foo<strong>bar</strong>baz</p>
        \\
    );
}

test "html.emphasis 5" {
    try testDjotToHtml(
        \\_foo bar_
        \\
    ,
        \\<p><em>foo bar</em></p>
        \\
    );
}

test "html.emphasis 6" {
    try testDjotToHtml(
        \\_ foo bar_
        \\
    ,
        \\<p>_ foo bar_</p>
        \\
    );
}

test "html.emphasis 7" {
    try testDjotToHtml(
        \\_foo bar _
        \\
    ,
        \\<p>_foo bar _</p>
        \\
    );
}

test "html.emphasis 8" {
    try testDjotToHtml(
        \\_ a _
        \\
    ,
        \\<p><em> a </em></p>
        \\
    );
}

test "html.emphasis 9" {
    try testDjotToHtml(
        \\foo_bar_baz
        \\
    ,
        \\<p>foo<em>bar</em>baz</p>
        \\
    );
}

test "html.emphasis 10" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\aa_"bb"_cc
        \\
    ,
        \\<p>aa<em>&ldquo;bb&rdquo;</em>cc</p>
        \\
    );
}

test "html.emphasis 11" {
    try testDjotToHtml(
        \\*foo_
        \\
    ,
        \\<p>*foo_</p>
        \\
    );
}

test "html.emphasis 12" {
    try testDjotToHtml(
        \\_foo*
        \\
    ,
        \\<p>_foo*</p>
        \\
    );
}

test "html.emphasis 13" {
    try testDjotToHtml(
        \\_foo bar
        \\_
        \\
    ,
        \\<p>_foo bar
        \\_</p>
        \\
    );
}

test "html.emphasis 14" {
    try testDjotToHtml(
        \\_	a_
        \\
    ,
        \\<p>_	a_</p>
        \\
    );
}

test "html.emphasis 15" {
    try testDjotToHtml(
        \\_(_foo_)_
        \\
    ,
        \\<p><em>(</em>foo<em>)</em></p>
        \\
    );
}

test "html.emphasis 16" {
    try testDjotToHtml(
        \\_({_foo_})_
        \\
    ,
        \\<p><em>(<em>foo</em>)</em></p>
        \\
    );
}

test "html.emphasis 17" {
    try testDjotToHtml(
        \\_(*foo*)_
        \\
    ,
        \\<p><em>(<strong>foo</strong>)</em></p>
        \\
    );
}

test "html.emphasis 18" {
    try testDjotToHtml(
        \\_foo *bar_ baz*
        \\
    ,
        \\<p><em>foo *bar</em> baz*</p>
        \\
    );
}

test "html.emphasis 19" {
    try testDjotToHtml(
        \\_foo
        \\bar_
        \\
    ,
        \\<p><em>foo
        \\bar</em></p>
        \\
    );
}

test "html.emphasis 20" {
    try testDjotToHtml(
        \\*foo [link](url) `*`*
        \\
    ,
        \\<p><strong>foo <a href="url">link</a> <code>*</code></strong></p>
        \\
    );
}

test "html.emphasis 21" {
    try testDjotToHtml(
        \\___
        \\
    ,
        \\<p>___</p>
        \\
    );
}

test "html.emphasis 22" {
    try testDjotToHtml(
        \\_\__
        \\
    ,
        \\<p><em>_</em></p>
        \\
    );
}

test "html.emphasis 23" {
    try testDjotToHtml(
        \\__
        \\
    ,
        \\<p>__</p>
        \\
    );
}

test "html.emphasis 24" {
    try testDjotToHtml(
        \\_}b_
        \\
    ,
        \\<p>_}b_</p>
        \\
    );
}

test "html.emphasis 25" {
    try testDjotToHtml(
        \\_\}b_
        \\
    ,
        \\<p><em>}b</em></p>
        \\
    );
}

test "html.emphasis 26" {
    try testDjotToHtml(
        \\_ab\_c_
        \\
    ,
        \\<p><em>ab_c</em></p>
        \\
    );
}

test "html.emphasis 27" {
    try testDjotToHtml(
        \\*****a*****
        \\
    ,
        \\<p><strong><strong><strong><strong><strong>a</strong></strong></strong></strong></strong></p>
        \\
    );
}

test "html.emphasis 28" {
    try testDjotToHtml(
        \\_[bar_](url)
        \\
    ,
        \\<p><em>[bar</em>](url)</p>
        \\
    );
}

test "html.emphasis 29" {
    try testDjotToHtml(
        \\\_[bar_](url)
        \\
    ,
        \\<p>_<a href="url">bar_</a></p>
        \\
    );
}

test "html.emphasis 30" {
    try testDjotToHtml(
        \\_`a_`b
        \\
    ,
        \\<p>_<code>a_</code>b</p>
        \\
    );
}

test "html.emphasis 31" {
    try testDjotToHtml(
        \\_<http://example.com/a_b>
        \\
    ,
        \\<p>_<a href="http://example.com/a_b">http://example.com/a_b</a></p>
        \\
    );
}
