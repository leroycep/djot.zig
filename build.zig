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

    const exe_tests = b.addTestExe("djot-test", "src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    exe_tests.setFilter(b.option([]const u8, "test-filter", "Set the test filter"));

    if (b.option(bool, "djot-test", "Install djot-test (default: false)") orelse false) {
        exe_tests.install();
    }

    const test_step = b.step("test", "Run unit tests");
    if (b.option(bool, "fancy-test-results", "Generate an HTML page of the results (default: true)") orelse true) {
        const fancy_exe = b.addExecutable("fancy-test-results", "tools/fancy-test-results.zig");
        fancy_exe.setTarget(target);
        fancy_exe.setBuildMode(mode);
        fancy_exe.addPackagePath("bolt", "src/bolt.zig");
        fancy_exe.addPackagePath("html", "src/html.zig");

        const fancy_run = fancy_exe.run();
        fancy_run.addFileSourceArg(exe_tests.getOutputSource());
        fancy_run.addArg(b.zig_exe);

        test_step.dependOn(&fancy_run.step);
    } else {
        const test_run = exe_tests.run();
        test_run.expected_exit_code = null;

        test_step.dependOn(&test_run.step);
    }

    buildConvertDjotHtmlTests(b, target, mode);
}

fn buildConvertDjotHtmlTests(b: *std.build.Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode) void {
    const exe = b.addExecutable("convert-djot-html-tests", "tools/convert-djot-html-tests.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("djot", "src/djot.zig");

    const run_cmd = exe.run();

    if (b.option([]const u8, "test-directory", "Path to the djot test cases directory")) |test_directory_path| {
        run_cmd.addFileSourceArg(.{ .path = test_directory_path });
    }

    const run_step = b.step("convert-djot-html-tests", "Convert test cases from github:jgm/djot into zig tests");
    run_step.dependOn(&run_cmd.step);
}
