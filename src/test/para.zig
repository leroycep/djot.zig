const testDjotToHtml = @import("../html_tests.zig").testDjotToHtml;

test "html.para 0" {
    try testDjotToHtml(
        \\hi  
        \\there  
        \\
    ,
        \\<p>hi  
        \\there</p>
        \\
    );
}

