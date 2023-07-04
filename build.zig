const std = @import("std");
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_model = .baseline,
        },
    });

    const ffi_libs = b.step("ffi", "Build FFI libs");

    // Zig cross-target x folder names
    const platforms = .{
        .{ "x86_64-linux-gnu", "linux-x64" },
        .{ "x86_64-windows-gnu", "win-x64" },
        .{ "x86_64-macos", "osx-x64" },
    };

    inline for (platforms) |platform| {
        const cross_target = CrossTarget.parse(.{ .arch_os_abi = platform[0], .cpu_features = "baseline" }) catch unreachable;

        inline for (.{ .dynamic, .static }) |linkage| {

            // Appends the name "lib" on windows, in order to generate the same name "libmustache" for all platforms
            const lib_name = comptime (if (std.mem.startsWith(u8, platform[1], "win")) "lib" else "") ++ "mustache";

            const lib = std.Build.Step.Compile.create(b, .{
                .name = lib_name,
                .root_source_file = .{ .path = "src/exports.zig" },
                .kind = .lib,
                .target = cross_target,
                .optimize = optimize,
                .linkage = linkage,
                .link_libc = true,
            });

            // dynamic_lib.setOutputDir("lib/" ++ platform[1]);
            b.installArtifact(lib);
            ffi_libs.dependOn(&lib.step);
        }
    }

    // C FFI Sample

    {

        // Building the static lib
        const static_lib = b.addStaticLibrary(.{
            .name = "mustache",
            .root_source_file = .{ .path = "src/exports.zig" },
            .link_libc = true,
            .target = target,
            .optimize = optimize,
        });

        const c_sample = b.addExecutable(.{
            .name = "sample",
            .root_source_file = .{ .path = "samples/c/sample.c" },
            .link_libc = true,
            .target = target,
            .optimize = optimize,
        });
        c_sample.linkLibrary(static_lib);
        b.installArtifact(c_sample);

        const run_cmd = b.addRunArtifact(c_sample);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const c_sample_build = b.step("c_sample", "Run the C sample");
        c_sample_build.dependOn(&run_cmd.step);
    }

    // Tests

    var comptime_tests = b.addOptions();
    const comptime_tests_enabled = b.option(bool, "comptime-tests", "Run comptime tests") orelse true;
    comptime_tests.addOption(bool, "comptime_tests_enabled", comptime_tests_enabled);

    {
        const main_tests = b.addTest(.{
          .root_source_file = .{ .path = "src/mustache.zig" },
          .target = target,
          .optimize = optimize,
        });

        main_tests.addOptions("build_comptime_tests", comptime_tests);
        const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;

        if (coverage) {

            // with kcov
            main_tests.setExecCmd(&[_]?[]const u8{
                "kcov",
                "--exclude-pattern",
                "lib/std",
                "kcov-output",
                null, // to get zig to use the --test-cmd-bin flag
            });
        }

        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&main_tests.step);
    }

    {
        const test_exe = b.addExecutable(.{
            .name = "tests",
            .root_source_file = .{ .path = "src/mustache.zig" },
            .optimize = optimize,
            .target = target,
        });
        test_exe.addOptions("build_comptime_tests", comptime_tests);

        const test_exe_install = b.addInstallArtifact(test_exe);

        const test_build = b.step("build_tests", "Build library tests");
        test_build.dependOn(&test_exe_install.step);
    }
}
