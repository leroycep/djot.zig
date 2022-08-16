const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.code_blocks 0" {
    try testDjotToHtml(
        \\~~~
        \\code
        \\  block
        \\~~~
        \\
    ,
        \\<pre><code>code
        \\  block
        \\</code></pre>
        \\
    );
}

test "html.code_blocks 1" {
    try testDjotToHtml(
        \\``` python
        \\x = y + 3
        \\```
        \\
    ,
        \\<pre><code class="language-python">x = y + 3
        \\</code></pre>
        \\
    );
}

test "html.code_blocks 2" {
    try testDjotToHtml(
        \\  ``` python
        \\  if true:
        \\    x = 3
        \\  ```
        \\
    ,
        \\<pre><code class="language-python">if true:
        \\  x = 3
        \\</code></pre>
        \\
    );
}

test "html.code_blocks 3" {
    try testDjotToHtml(
        \\``` not a code block ```
        \\
    ,
        \\<p><code> not a code block </code></p>
        \\
    );
}

test "html.code_blocks 4" {
    try testDjotToHtml(
        \\``` not a code block
        \\
    ,
        \\<p><code> not a code block</code></p>
        \\
    );
}

test "html.code_blocks 5" {
    try testDjotToHtml(
        \\```
        \\hi
        \\```
        \\```
        \\two
        \\```
        \\
    ,
        \\<pre><code>hi
        \\</code></pre>
        \\<pre><code>two
        \\</code></pre>
        \\
    );
}

