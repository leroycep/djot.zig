const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.smart 0" {
    try testDjotToHtml(
        \\"Hello," said the spider.
        \\"'Shelob' is my name."
        \\
    ,
        \\<p>&ldquo;Hello,&rdquo; said the spider.
        \\&ldquo;&lsquo;Shelob&rsquo; is my name.&rdquo;</p>
        \\
    );
}

test "html.smart 1" {
    try testDjotToHtml(
        \\'A', 'B', and 'C' are letters.
        \\
    ,
        \\<p>&lsquo;A&rsquo;, &lsquo;B&rsquo;, and &lsquo;C&rsquo; are letters.</p>
        \\
    );
}

test "html.smart 2" {
    try testDjotToHtml(
        \\'Oak,' 'elm,' and 'beech' are names of trees.
        \\So is 'pine.'
        \\
    ,
        \\<p>&lsquo;Oak,&rsquo; &lsquo;elm,&rsquo; and &lsquo;beech&rsquo; are names of trees.
        \\So is &lsquo;pine.&rsquo;</p>
        \\
    );
}

test "html.smart 3" {
    try testDjotToHtml(
        \\'He said, "I want to go."'
        \\
    ,
        \\<p>&lsquo;He said, &ldquo;I want to go.&rdquo;&rsquo;</p>
        \\
    );
}

test "html.smart 4" {
    try testDjotToHtml(
        \\Were you alive in the '70s?
        \\
    ,
        \\<p>Were you alive in the &rsquo;70s?</p>
        \\
    );
}

test "html.smart 5" {
    try testDjotToHtml(
        \\Here is some quoted '`code`' and a "[quoted link](url)".
        \\
    ,
        \\<p>Here is some quoted &lsquo;<code>code</code>&rsquo; and a &ldquo;<a href="url">quoted link</a>&rdquo;.</p>
        \\
    );
}

test "html.smart 6" {
    try testDjotToHtml(
        \\'tis the season to be 'jolly'
        \\
    ,
        \\<p>&rsquo;tis the season to be &lsquo;jolly&rsquo;</p>
        \\
    );
}

test "html.smart 7" {
    try testDjotToHtml(
        \\'We'll use Jane's boat and John's truck,' Jenna said.
        \\
    ,
        \\<p>&lsquo;We&rsquo;ll use Jane&rsquo;s boat and John&rsquo;s truck,&rsquo; Jenna said.</p>
        \\
    );
}

test "html.smart 8" {
    try testDjotToHtml(
        \\"A paragraph with no closing quote.
        \\
        \\"Second paragraph by same speaker, in fiction."
        \\
    ,
        \\<p>&ldquo;A paragraph with no closing quote.</p>
        \\<p>&ldquo;Second paragraph by same speaker, in fiction.&rdquo;</p>
        \\
    );
}

test "html.smart 9" {
    try testDjotToHtml(
        \\[a]'s b'
        \\
    ,
        \\<p>[a]&rsquo;s b&rsquo;</p>
        \\
    );
}

test "html.smart 10" {
    try testDjotToHtml(
        \\\"This is not smart.\"
        \\This isn\'t either.
        \\5\'8\"
        \\
    ,
        \\<p>"This is not smart."
        \\This isn't either.
        \\5'8"</p>
        \\
    );
}

test "html.smart 11" {
    try testDjotToHtml(
        \\''hi''
        \\
    ,
        \\<p>&lsquo;&lsquo;hi&rsquo;&rsquo;</p>
        \\
    );
}

test "html.smart 12" {
    try testDjotToHtml(
        \\{''}hi{''}
        \\
    ,
        \\<p>&lsquo;&rsquo;hi&lsquo;&rsquo;</p>
        \\
    );
}

test "html.smart 13" {
    try testDjotToHtml(
        \\Some dashes:  em---em
        \\en--en
        \\em --- em
        \\en -- en
        \\2--3
        \\
    ,
        \\<p>Some dashes:  em&mdash;em
        \\en&ndash;en
        \\em &mdash; em
        \\en &ndash; en
        \\2&ndash;3</p>
        \\
    );
}

test "html.smart 14" {
    try testDjotToHtml(
        \\one-
        \\two--
        \\three---
        \\four----
        \\five-----
        \\six------
        \\seven-------
        \\eight--------
        \\nine---------
        \\thirteen-------------.
        \\
    ,
        \\<p>one-
        \\two&ndash;
        \\three&mdash;
        \\four&ndash;&ndash;
        \\five&mdash;&ndash;
        \\six&mdash;&mdash;
        \\seven&mdash;&ndash;&ndash;
        \\eight&ndash;&ndash;&ndash;&ndash;
        \\nine&mdash;&mdash;&mdash;
        \\thirteen&mdash;&mdash;&mdash;&ndash;&ndash;.</p>
        \\
    );
}

test "html.smart 15" {
    try testDjotToHtml(
        \\Escaped hyphens: \-- \-\-\-.
        \\
    ,
        \\<p>Escaped hyphens: -- ---.</p>
        \\
    );
}

test "html.smart 16" {
    try testDjotToHtml(
        \\Ellipses...and...and....
        \\
    ,
        \\<p>Ellipses&hellip;and&hellip;and&hellip;.</p>
        \\
    );
}

test "html.smart 17" {
    try testDjotToHtml(
        \\No ellipses\.\.\.
        \\
    ,
        \\<p>No ellipses...</p>
        \\
    );
}

