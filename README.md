# djot.zig

From <https://djot.net/>:

> Djot is a light markup syntax. It derives most of its features from commonmark,
but it fixes a few things that make commonmark's syntax complex and difficult to
parse efficiently. It is also much fuller-featured than commonmark, with support
for definition lists, footnotes, tables, several new kinds of inline formatting
(insert, delete, highlight, superscript, subscript), math, smart punctuation,
attributes that can be applied to any element, and generic containers for
block-level, inline-level, and raw content.

"djot.zig" is a library for parsing djot files and converting them to HTML. It
also includes a command line interface for converting djot to HTML.

## State of djot.zig

djot.zig is very much a work in progress. There are many features to implement,
and the API will almost certainly change. If you want a fully featured version
of djot, consider using the [official version implemented in Lua](https://github.com/jgm/djot).

### Tests

djot.zig uses the HTML test cases from the [official version implemented in Lua](https://github.com/jgm/djot/tree/47f9b3b3db91985180603ca5263ea2ec83d3e75d/test),
and a couple other test cases taken from the [syntax description](https://htmlpreview.github.io/?https://github.com/jgm/djot/blob/master/doc/syntax.html).

Test results as of 2022-08-19:

```
$ zig build -fno-stage1 test
66 passed; 0 skipped; 169 failed.
```

That's 66/235 test cases passing; or about 28% of the tests passing.

### Inline Syntax

| Feature | Implemented? |
|---------|-------|
| inline links | partially |
| reference links | no |
| images | no |
| autolinks | yes |
| inline verbatim | yes |
| inline verbatim space removal | no |
| emphasis/strong | yes |
| inline highlight | no |
| super/subscript | no |
| insert/delete | no |
| smart punctuation | no |
| inline math | no |
| footnote references | no |
| hard line break | no |
| comments | no |
| emoji aliases | no |
| raw inline | no |
| spans | no |
| inline attributes | no |

### Block syntax

| Feature | Implemented? |
|---------|-------|
| paragraphs | yes |
| block quotes | yes |
| lists | partially |
| code blocks | no |
| thematic breaks | no |
| raw blocks | no |
| div blocks | no |
| pipe tables | no |
| reference link definitions | no |
| footnote definitions | no |
| block attributes | no |
| implicit heading reference links | no |

## How to use

### Command Line Interface

Requires zig >= `0.10.0-dev.3567+95573dbee`.

```
$ git clone https://github.com/leroycep/djot.zig
$ cd djot.zig
$ zig build install -fno-stage1
$ echo "*Hello, world!*" | ./zig-out/bin/djot.zig
<p><strong>Hello, world!*"</strong></p>"
```

### Using `djot.zig` as a Library

Requires zig stage2 >= `0.10.0-dev.3567+95573dbee`.

Let's make an application that extracts djot links from stdin! To get started
we'll create a new zig project using `zig init-exe` and cloning `djot.zig`:

```bash
$ mkdir new-project
$ cd new-project
$ zig init-exe

$ git clone https://github.com/leroycep/djot.zig
```

Now let's add `djot.zig` as a package:

```diff
--- old-build.zig
+++ build.zig
@@ -15,6 +15,7 @@
     exe.setTarget(target);
     exe.setBuildMode(mode);
     exe.install();
+    exe.addPackagePath("djot", "./djot.zig/src/djot.zig");
 
     const run_cmd = exe.run();
     run_cmd.step.dependOn(b.getInstallStep());
```

And replace the auto-generated main function for one that extracts links from
djot markup:

```diff
--- src/old-main.zig	2022-08-19 20:06:28.272239304 -0600
+++ src/main.zig	2022-08-19 20:23:15.261355146 -0600
@@ -1,19 +1,30 @@
 const std = @import("std");
+const djot = @import("djot");
 
+/// Extract all the links from djot markup that is passed to stdin
 pub fn main() !void {
-    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
-    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
+    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
+    defer _ = gpa.deinit();
 
-    // stdout is for the actual output of your application, for example if you
-    // are implementing gzip, then only the compressed bytes should be sent to
-    // stdout, not any debugging messages.
-    const stdout_file = std.io.getStdOut().writer();
-    var bw = std.io.bufferedWriter(stdout_file);
-    const stdout = bw.writer();
+    const stdin = std.io.getStdIn();
+    const source = try stdin.readToEndAlloc(gpa.allocator(), 50 * 1024 * 1024);
+    defer gpa.allocator().free(source);
 
-    try stdout.print("Run `zig build test` to run the tests.\n", .{});
+    var document = try djot.parse(gpa.allocator(), source);
+    defer document.deinit(gpa.allocator());
 
-    try bw.flush(); // don't forget to flush!
+    const stdout = std.io.getStdOut();
+    for (document.events.items(.tag)) |event_tag, event_index| {
+        switch (event_tag) {
+            .autolink,
+            .start_link,
+            .start_image_link,
+            => {
+                try stdout.writer().print("- {s}\n", .{document.asText(event_index)});
+            },
+            else => {},
+        }
+    }
 }
 
 test "simple test" {
```

Now let's test it out:

```bash
$ echo "fav websites: <https://ziglang.org>, <https://djot.net>" | zig build -fno-stage1 run
- https://ziglang.org
- https://djot.net
```
