const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.task_lists 0" {
    try testDjotToHtml(
        \\- [ ] an unchecked task list item
        \\- [x] checked item
        \\
    ,
        \\<ul class="task-list">
        \\<li class="unchecked">
        \\an unchecked task list item
        \\</li>
        \\<li class="checked">
        \\checked item
        \\</li>
        \\</ul>
        \\
    );
}

test "html.task_lists 1" {
    try testDjotToHtml(
        \\* [ ] an unchecked task list item
        \\
        \\  with two paragraphs
        \\
        \\* [x] checked item
        \\
    ,
        \\<ul class="task-list">
        \\<li class="unchecked">
        \\<p>an unchecked task list item</p>
        \\<p>with two paragraphs</p>
        \\</li>
        \\<li class="checked">
        \\<p>checked item</p>
        \\</li>
        \\</ul>
        \\
    );
}

