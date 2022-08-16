const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.definition-lists 0" {
    try testDjotToHtml(
        \\: apple
        \\
        \\  red fruit
        \\: banana
        \\
        \\  yellow fruit
        \\
    ,
        \\<dl>
        \\<dt>apple</dt>
        \\<dd>
        \\<p>red fruit</p>
        \\</dd>
        \\<dt>banana</dt>
        \\<dd>
        \\<p>yellow fruit</p>
        \\</dd>
        \\</dl>
        \\
    );
}

test "html.definition-lists 1" {
    try testDjotToHtml(
        \\: apple
        \\
        \\  red fruit
        \\
        \\: banana
        \\
        \\  yellow fruit
        \\
    ,
        \\<dl>
        \\<dt>apple</dt>
        \\<dd>
        \\<p>red fruit</p>
        \\</dd>
        \\<dt>banana</dt>
        \\<dd>
        \\<p>yellow fruit</p>
        \\</dd>
        \\</dl>
        \\
    );
}

test "html.definition-lists 2" {
    try testDjotToHtml(
        \\: apple
        \\ fruit
        \\
        \\  Paragraph one
        \\
        \\  Paragraph two
        \\
        \\  - sub
        \\  - list
        \\
        \\: orange
        \\
    ,
        \\<dl>
        \\<dt>apple
        \\fruit</dt>
        \\<dd>
        \\<p>Paragraph one</p>
        \\<p>Paragraph two</p>
        \\<ul>
        \\<li>
        \\sub
        \\</li>
        \\<li>
        \\list
        \\</li>
        \\</ul>
        \\</dd>
        \\<dt>orange</dt>
        \\</dl>
        \\
    );
}

test "html.definition-lists 3" {
    try testDjotToHtml(
        \\: ```
        \\  ok
        \\  ```
        \\
    ,
        \\<dl>
        \\<dt></dt>
        \\<dd>
        \\<pre><code>ok
        \\</code></pre>
        \\</dd>
        \\</dl>
        \\
    );
}

