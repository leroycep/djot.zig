const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.lists 0" {
    try testDjotToHtml(
        \\- one
        \\- two
        \\
    ,
        \\<ul>
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 1" {
    try testDjotToHtml(
        \\- one
        \\ - two
        \\  - three
        \\
    ,
        \\<ul>
        \\<li>
        \\one
        \\- two
        \\- three
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 2" {
    try testDjotToHtml(
        \\- one
        \\
        \\ - two
        \\
        \\  - three
        \\
    ,
        \\<ul>
        \\<li>
        \\one
        \\<ul>
        \\<li>
        \\two
        \\<ul>
        \\<li>
        \\three
        \\</li>
        \\</ul>
        \\</li>
        \\</ul>
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 3" {
    try testDjotToHtml(
        \\- one
        \\  and
        \\
        \\  another paragraph
        \\
        \\  - a list
        \\
        \\- two
        \\
    ,
        \\<ul>
        \\<li>
        \\<p>one
        \\and</p>
        \\<p>another paragraph</p>
        \\<ul>
        \\<li>
        \\a list
        \\</li>
        \\</ul>
        \\</li>
        \\<li>
        \\<p>two</p>
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- one
        \\lazy
        \\- two
        \\
    ,
        \\<ul>
        \\<li>
        \\one
        \\lazy
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\- b
        \\+ c
        \\
    ,
        \\<ul>
        \\<li>
        \\a
        \\</li>
        \\<li>
        \\b
        \\</li>
        \\</ul>
        \\<ul>
        \\<li>
        \\c
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 6" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\
        \\- b
        \\
    ,
        \\<ul>
        \\<li>
        \\<p>a</p>
        \\</li>
        \\<li>
        \\<p>b</p>
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 7" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\  - b
        \\
        \\  - c
        \\- d
        \\
    ,
        \\<ul>
        \\<li>
        \\a
        \\- b
        \\<ul>
        \\<li>
        \\c
        \\</li>
        \\</ul>
        \\</li>
        \\<li>
        \\d
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 8" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\  - b
        \\
        \\  - c
        \\
        \\- d
        \\
    ,
        \\<ul>
        \\<li>
        \\a
        \\- b
        \\<ul>
        \\<li>
        \\c
        \\</li>
        \\</ul>
        \\</li>
        \\<li>
        \\d
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 9" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\
        \\  b
        \\- c
        \\
    ,
        \\<ul>
        \\<li>
        \\<p>a</p>
        \\<p>b</p>
        \\</li>
        \\<li>
        \\<p>c</p>
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 10" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\
        \\  - b
        \\  - c
        \\- d
        \\
    ,
        \\<ul>
        \\<li>
        \\a
        \\<ul>
        \\<li>
        \\b
        \\</li>
        \\<li>
        \\c
        \\</li>
        \\</ul>
        \\</li>
        \\<li>
        \\d
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 11" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\
        \\  - b
        \\  - c
        \\
        \\- d
        \\
    ,
        \\<ul>
        \\<li>
        \\a
        \\<ul>
        \\<li>
        \\b
        \\</li>
        \\<li>
        \\c
        \\</li>
        \\</ul>
        \\</li>
        \\<li>
        \\d
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 12" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- a
        \\
        \\  * b
        \\cd
        \\
    ,
        \\<ul>
        \\<li>
        \\a
        \\<ul>
        \\<li>
        \\b
        \\cd
        \\</li>
        \\</ul>
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 13" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\- - - a
        \\
    ,
        \\<ul>
        \\<li>
        \\<ul>
        \\<li>
        \\<ul>
        \\<li>
        \\a
        \\</li>
        \\</ul>
        \\</li>
        \\</ul>
        \\</li>
        \\</ul>
        \\
    );
}

test "html.lists 14" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\1. one
        \\1. two
        \\
    ,
        \\<ol>
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 15" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\1. one
        \\
        \\ 1. two
        \\
    ,
        \\<ol>
        \\<li>
        \\one
        \\<ol>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 16" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\4. one
        \\5. two
        \\
    ,
        \\<ol start="4">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 17" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\1) one
        \\2) two
        \\
    ,
        \\<ol>
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 18" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\(1) one
        \\(2) two
        \\
    ,
        \\<ol>
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 19" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\(a) one
        \\(b) two
        \\
    ,
        \\<ol type="a">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 20" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\(D) one
        \\(E) two
        \\
    ,
        \\<ol start="4" type="A">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 21" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\a. one
        \\b. two
        \\
    ,
        \\<ol type="a">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 22" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\i. one
        \\ii. two
        \\
    ,
        \\<ol type="i">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 23" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\xli) one
        \\xlii) two
        \\
    ,
        \\<ol start="41" type="i">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 24" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\(IV) one
        \\(V) two
        \\
    ,
        \\<ol start="4" type="I">
        \\<li>
        \\one
        \\</li>
        \\<li>
        \\two
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 25" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\i. a
        \\ii. b
        \\
    ,
        \\<ol type="i">
        \\<li>
        \\a
        \\</li>
        \\<li>
        \\b
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 26" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\i. a
        \\j. b
        \\
    ,
        \\<ol start="9" type="a">
        \\<li>
        \\a
        \\</li>
        \\<li>
        \\b
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 27" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\I. a
        \\II. b
        \\E. d
        \\
    ,
        \\<ol type="I">
        \\<li>
        \\a
        \\</li>
        \\<li>
        \\b
        \\</li>
        \\</ol>
        \\<ol start="5" type="A">
        \\<li>
        \\d
        \\</li>
        \\</ol>
        \\
    );
}

test "html.lists 28" {
    try testDjotToHtml(
        \\The civil war ended in
        \\1865. And this should not start a list.
        \\
    ,
        \\<p>The civil war ended in
        \\1865. And this should not start a list.</p>
        \\
    );
}
