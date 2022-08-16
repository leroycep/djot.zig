const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.footnotes 0" {
    try testDjotToHtml(
        \\test[^a] and another[^foo_bar].
        \\
        \\[^a]: This is a note.
        \\
        \\  Second paragraph.
        \\
        \\[^foo_bar]:
        \\  ```
        \\  code
        \\  ```
        \\
        \\another ref to the first note[^a].
        \\
    ,
        \\<p>test<a href="#fn1" role="doc-noteref"><sup>1</sup></a> and another<a href="#fn2" role="doc-noteref"><sup>2</sup></a>.</p>
        \\<p>another ref to the first note<a href="#fn1" role="doc-noteref"><sup>1</sup></a>.</p>
        \\<section role="doc-endnotes">
        \\<hr>
        \\<ol>
        \\<li id="fn1">
        \\<p>This is a note.</p>
        \\<p>Second paragraph.<a href="#fnref1" role="doc-backlink">↩︎︎</a></p>
        \\</li>
        \\<li id="fn2">
        \\<pre><code>code
        \\</code></pre>
        \\<p><a href="#fnref2" role="doc-backlink">↩︎︎</a></p>
        \\</li>
        \\</ol>
        \\</section>
        \\
    );
}

test "html.footnotes 1" {
    try testDjotToHtml(
        \\test[^nonexistent]
        \\
        \\[^unused]: note
        \\
        \\  more
        \\
    ,
        \\<p>test<a href="#fn1" role="doc-noteref"><sup>1</sup></a></p>
        \\<section role="doc-endnotes">
        \\<hr>
        \\<ol>
        \\</ol>
        \\</section>
        \\
    );
}

