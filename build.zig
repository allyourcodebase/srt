const std = @import("std");
const Build = std.Build;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flags = get_flags(b, target) catch @panic("OOM");
    const srt_dep = b.dependency("srt", .{});

    const mbedtls_dep = b.dependency("mbedtls", .{
        .target = target,
        .optimize = optimize,
    });

    const googletest_dep = b.dependency("googletest", .{
        .target = target,
        .optimize = optimize,
    });

    const haicrypt = b.addStaticLibrary(.{
        .name = "haicrypt",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    set_defines(haicrypt, target);
    haicrypt.linkLibCpp();
    haicrypt.linkLibrary(mbedtls_dep.artifact("mbedtls"));
    haicrypt.installHeader(srt_dep.path("haicrypt/haicrypt.h"), "haicrypt.h");
    haicrypt.installHeader(srt_dep.path("haicrypt/hcrypt_ctx.h"), "hcrypt_ctx.h");
    haicrypt.installHeader(srt_dep.path("haicrypt/hcrypt_msg.h"), "hcrypt_msg.h");
    haicrypt.installLibraryHeaders(mbedtls_dep.artifact("mbedtls"));
    haicrypt.addIncludePath(srt_dep.path("common"));

    inline for (haicrypt_files) |file|
        haicrypt.addCSourceFile(.{
            .file = srt_dep.path(b.fmt("haicrypt/{s}", .{file})),
            .flags = flags,
        });

    const version_header = b.addConfigHeader(.{
        .style = .{
            .cmake = srt_dep.path("srtcore/version.h.in"),
        },
    }, .{
        .SRT_VERSION_MAJOR = "1",
        .SRT_VERSION_MINOR = "5",
        .SRT_VERSION_PATCH = "3",
        .SRT_VERSION = "1.5.3",
        .CI_BUILD_NUMBER_STRING = "0",
    });

    const srtcore = b.addStaticLibrary(.{
        .name = "srt",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    srtcore.linkLibCpp();
    srtcore.linkLibrary(haicrypt);
    set_defines(srtcore, target);
    srtcore.addIncludePath(version_header.getOutput().dirname());
    srtcore.addIncludePath(srt_dep.path("haicrypt"));
    srtcore.addIncludePath(srt_dep.path("srtcore"));
    srtcore.addIncludePath(srt_dep.path("common"));
    srtcore.installHeader(srt_dep.path("srtcore/srt.h"), "srt.h");
    srtcore.installHeader(srt_dep.path("srtcore/logging_api.h"), "logging_api.h");
    srtcore.installHeader(srt_dep.path("srtcore/access_control.h"), "access_control.h");
    srtcore.installConfigHeader(version_header);

    inline for (srtcore_files) |file|
        srtcore.addCSourceFile(.{
            .file = srt_dep.path(b.fmt("srtcore/{s}", .{file})),
            .flags = flags,
        });

    switch (target.result.os.tag) {
        .linux, .macos => {
            srtcore.addCSourceFile(.{
                .file = srt_dep.path("srtcore/sync_posix.cpp"),
                .flags = flags,
            });
        },
        .windows => {
            srtcore.defineCMacro("ENABLE_STDCXX_SYNC", "1");
            srtcore.addCSourceFile(.{
                .file = srt_dep.path("srtcore/sync_cxx11.cpp"),
                .flags = flags,
            });
        },
        else => {},
    }

    b.installArtifact(srtcore);

    const tests = b.addExecutable(.{
        .name = "tests",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    set_defines(tests, target);
    tests.linkLibCpp();
    tests.linkLibrary(googletest_dep.artifact("gtest"));
    tests.linkLibrary(srtcore);
    tests.linkLibrary(haicrypt);
    tests.addIncludePath(srt_dep.path("srtcore"));
    tests.addIncludePath(srt_dep.path("haicrypt"));
    tests.addIncludePath(srt_dep.path("common"));

    inline for (test_files) |file|
        tests.addCSourceFile(.{
            .file = srt_dep.path(b.fmt("test/{s}", .{file})),
            .flags = flags,
        });

    b.getInstallStep().dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

fn set_defines(lib: *Build.Step.Compile, target: Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .linux => {
            lib.defineCMacro("LINUX", "1");
            lib.defineCMacro("SRT_ENABLE_BINDTODEVICE", null);
        },
        .windows => {
            lib.defineCMacro("WIN32", "1");
            lib.defineCMacro("PTW32_STATIC_LIB", "1");
        },
        .freebsd, .netbsd, .openbsd, .dragonfly => lib.defineCMacro("BSD", "1"),
        else => {},
    }

    lib.defineCMacro("HAVE_CXX_STD_PUT_TIME", "1");
    lib.defineCMacro("USE_MBEDTLS", "1");
    lib.defineCMacro("SRT_ENABLE_ENCRYPTION", "1");
    lib.defineCMacro("_GNU_SOURCE", null);
    lib.defineCMacro("HAI_PATCH", "1");
    lib.defineCMacro("HAI_ENABLE_SRT", "1");
    lib.defineCMacro("SRT_VERSION", "\"1.5.3\"");
}

fn get_flags(b: *Build, target: Build.ResolvedTarget) ![]const []const u8 {
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.append("-fno-sanitize=undefined");

    switch (target.result.os.tag) {
        else => {},
    }

    return try flags.toOwnedSlice();
}

const srtcore_files = &.{
    "api.cpp",
    "buffer_snd.cpp",
    "buffer_rcv.cpp",
    "buffer_tools.cpp",
    "cache.cpp",
    "channel.cpp",
    "common.cpp",
    "core.cpp",
    "crypto.cpp",
    "epoll.cpp",
    "fec.cpp",
    "handshake.cpp",
    "list.cpp",
    "logger_default.cpp",
    "logger_defs.cpp",

    "md5.cpp",
    "packet.cpp",
    "packetfilter.cpp",
    "queue.cpp",
    "congctl.cpp",
    "socketconfig.cpp",
    "srt_c_api.cpp",
    "srt_compat.c",
    "strerror_defs.cpp",
    "sync.cpp",
    "tsbpd_time.cpp",
    "window.cpp",
};

const haicrypt_files = &.{
    "cryspr.c",
    "cryspr-mbedtls.c",
    "hcrypt.c",
    "hcrypt_ctx_rx.c",
    "hcrypt_ctx_tx.c",
    "hcrypt_rx.c",
    "hcrypt_sa.c",
    "hcrypt_tx.c",
    "hcrypt_xpt_srt.c",
    "haicrypt_log.cpp",
};

const test_files = &.{
    "test_main.cpp",
    "test_buffer_rcv.cpp",
    "test_common.cpp",
    "test_connection_timeout.cpp",
    "test_crypto.cpp",
    "test_cryspr.cpp",
    "test_enforced_encryption.cpp",
    "test_epoll.cpp",
    "test_fec_rebuilding.cpp",
    "test_file_transmission.cpp",
    "test_ipv6.cpp",
    "test_listen_callback.cpp",
    "test_losslist_rcv.cpp",
    "test_losslist_snd.cpp",
    "test_many_connections.cpp",
    "test_muxer.cpp",
    "test_seqno.cpp",
    "test_socket_options.cpp",
    "test_sync.cpp",
    "test_threadname.cpp",
    "test_timer.cpp",
    "test_unitqueue.cpp",
    "test_utilities.cpp",
    "test_reuseaddr.cpp",
    "test_socketdata.cpp",
    "test_snd_rate_estimator.cpp",
};
