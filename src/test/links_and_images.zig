const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.links_and_images 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[basic _link_][a_b_]
        \\
        \\[a_b_]: url
        \\
    ,
        \\<p><a href="url">basic <em>link</em></a></p>
        \\
    );
}

test "html.links_and_images 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\![basic _image_][a_b_]
        \\
        \\[a_b_]: url
        \\
    ,
        \\<p><img alt="basic image" src="url"></p>
        \\
    );
}

test "html.links_and_images 2" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][]
        \\
        \\[link]: url
        \\
    ,
        \\<p><a href="url">link</a></p>
        \\
    );
}

test "html.links_and_images 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][]
        \\
        \\[link]:
        \\ url
        \\
    ,
        \\<p><a href="url">link</a></p>
        \\
    );
}

test "html.links_and_images 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][]
        \\
        \\[link]:
        \\ url
        \\  andurl
        \\
    ,
        \\<p><a href="urlandurl">link</a></p>
        \\
    );
}

test "html.links_and_images 5" {
    try testDjotToHtml(
        \\[link](url
        \\andurl)
        \\
    ,
        \\<p><a href="urlandurl">link</a></p>
        \\
    );
}

test "html.links_and_images 6" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][]
        \\
        \\[link]:
        \\[link2]: url
        \\
    ,
        \\<p><a href="">link</a></p>
        \\
    );
}

test "html.links_and_images 7" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][]
        \\[link][link2]
        \\
        \\[link2]:
        \\  url2
        \\[link]:
        \\ url
        \\
    ,
        \\<p><a href="url">link</a>
        \\<a href="url2">link</a></p>
        \\
    );
}

test "html.links_and_images 8" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][a and
        \\b]
        \\
        \\[a and b]: url
        \\
    ,
        \\<p><a href="url">link</a></p>
        \\
    );
}

test "html.links_and_images 9" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][a and
        \\b]
        \\
    ,
        \\<p><a>link</a></p>
        \\
    );
}

test "html.links_and_images 10" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link][a and
        \\b]
        \\
        \\[a and
        \\b]: url
        \\
    ,
        \\<p><a>link</a></p>
        \\<p>[a and
        \\b]: url</p>
        \\
    );
}

test "html.links_and_images 11" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[Link][]
        \\
        \\[link]: /url
        \\
    ,
        \\<p><a>Link</a></p>
        \\
    );
}

test "html.links_and_images 12" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{title=foo}
        \\[ref]: /url
        \\
        \\[ref][]
        \\
    ,
        \\<p><a title="foo" href="/url">ref</a></p>
        \\
    );
}

test "html.links_and_images 13" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\{title=foo}
        \\[ref]: /url
        \\
        \\[ref][]{title=bar}
        \\
    ,
        \\<p><a title="bar" href="/url">ref</a></p>
        \\
    );
}

test "html.links_and_images 14" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\[link _and_ link][]
        \\
        \\[link and link]: url
        \\
    ,
        \\<p><a href="url">link <em>and</em> link</a></p>
        \\
    );
}

test "html.links_and_images 15" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\![basic _image_](url)
        \\
    ,
        \\<p><img alt="basic image" src="url"></p>
        \\
    );
}

test "html.links_and_images 16" {
    try testDjotToHtml(
        \\[![image](img.jpg)](url)
        \\
    ,
        \\<p><a href="url"><img alt="image" src="img.jpg"></a></p>
        \\
    );
}

test "html.links_and_images 17" {
    try testDjotToHtml(
        \\[unclosed](hello *a
        \\b*
        \\
    ,
        \\<p>[unclosed](hello <strong>a
        \\b</strong></p>
        \\
    );
}

test "html.links_and_images 18" {
    try testDjotToHtml(
        \\[closed](hello *a
        \\b*)
        \\
    ,
        \\<p><a href="hello *ab*">closed</a></p>
        \\
    );
}

test "html.links_and_images 19" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\*[closed](hello*)
        \\
    ,
        \\<p><strong>[closed](hello</strong>)</p>
        \\
    );
}

test "html.links_and_images 20" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\*[closed](hello\*)
        \\
    ,
        \\<p>*<a href="hello*">closed</a></p>
        \\
    );
}

test "html.links_and_images 21" {
    try testDjotToHtml(
        \\[[foo](bar)](baz)
        \\
    ,
        \\<p><a href="baz"><a href="bar">foo</a></a></p>
        \\
    );
}

test "html.links_and_images 22" {
    try testDjotToHtml(
        \\![[link](url)](img)
        \\
    ,
        \\<p><img alt="link" src="img"></p>
        \\
    );
}

test "html.links_and_images 23" {
    try testDjotToHtml(
        \\[![image](img)](url)
        \\
    ,
        \\<p><a href="url"><img alt="image" src="img"></a></p>
        \\
    );
}

test "html.links_and_images 24" {
    try testDjotToHtml(
        \\<http://example.com/foo>
        \\<me@example.com>
        \\
    ,
        \\<p><a href="http://example.com/foo">http://example.com/foo</a>
        \\<a href="mailto:me@example.com">me@example.com</a></p>
        \\
    );
}
