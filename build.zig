const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("djot.zig", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    buildDjotHtmlTests(b, target, mode);
}

fn buildDjotHtmlTests(b: *std.build.Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode) void {
    const exe = b.addExecutable("djot-html-tests", "test/djot-html-tests.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("djot", "src/djot.zig");

    const run_cmd = exe.run();

    if (b.option([]const u8, "test-file", "Set the file for test-djot-html to use")) |test_file| {
        run_cmd.addFileSourceArg(.{ .path = test_file });
    } else {
        run_cmd.addFileSourceArg(.{ .path = "djot/test/attributes.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/blockquote.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/code_blocks.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/definition-lists.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/emoji.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/emphasis.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/escapes.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/fenced_divs.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/footnotes.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/headings.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/insert-delete-mark.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/links_and_images.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/lists.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/math.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/para.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/raw.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/smart.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/spans.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/super-subscript.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/tables.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/task_lists.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/thematic_breaks.test" });
        run_cmd.addFileSourceArg(.{ .path = "djot/test/verbatim.test" });
    }

    const run_step = b.step("test-djot-html", "Run the tests from github:jgm/djot");
    run_step.dependOn(&run_cmd.step);
}
