const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.tables 0" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\| a |
        \\
    ,
        \\<table>
        \\<tr>
        \\<td>a</td>
        \\</tr>
        \\</table>
        \\
    );
}

test "html.tables 1" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\|a|   *b*|
        \\|*c| d* |
        \\
    ,
        \\<table>
        \\<tr>
        \\<td>a</td>
        \\<td><strong>b</strong></td>
        \\</tr>
        \\<tr>
        \\<td>*c</td>
        \\<td>d*</td>
        \\</tr>
        \\</table>
        \\
    );
}

test "html.tables 2" {
    try testDjotToHtml(
        \\| `a |`
        \\
    ,
        \\<p>| <code>a |</code></p>
        \\
    );
}

test "html.tables 3" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\| a | b |
        \\
        \\^ With a _caption_
        \\and another line.
        \\
    ,
        \\<table>
        \\<caption>With a <em>caption</em>
        \\and another line.</caption>
        \\<tr>
        \\<td>a</td>
        \\<td>b</td>
        \\</tr>
        \\</table>
        \\
    );
}

test "html.tables 4" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\|a|b|
        \\|:-|---:|
        \\|c|d|
        \\|cc|dd|
        \\|-:|:-:|
        \\|e|f|
        \\|g|h|
        \\
    ,
        \\<table>
        \\<tr>
        \\<th style="text-align: left;">a</th>
        \\<th style="text-align: right;">b</th>
        \\</tr>
        \\<tr>
        \\<td style="text-align: left;">c</td>
        \\<td style="text-align: right;">d</td>
        \\</tr>
        \\<tr>
        \\<th style="text-align: right;">cc</th>
        \\<th style="text-align: center;">dd</th>
        \\</tr>
        \\<tr>
        \\<td style="text-align: right;">e</td>
        \\<td style="text-align: center;">f</td>
        \\</tr>
        \\<tr>
        \\<td style="text-align: right;">g</td>
        \\<td style="text-align: center;">h</td>
        \\</tr>
        \\</table>
        \\
    );
}

test "html.tables 5" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\|--|--|
        \\
    ,
        \\<table>
        \\</table>
        \\
    );
}

test "html.tables 6" {
    if (true) return error.SkipZigTest;
    try testDjotToHtml(
        \\|---|---|
        \\| a | b |
        \\
    ,
        \\<table>
        \\<tr>
        \\<td>a</td>
        \\<td>b</td>
        \\</tr>
        \\</table>
        \\
    );
}
