#!/usr/bin/env perl
# Tests for Zepto::ThemeDetect
#
# Every test injects `run` / `command_exists` / `platform` — this module
# must never shell out during unit tests. If a test here ever calls a real
# subprocess, that's a bug in the test, not a feature of the module.
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::ThemeDetect;

# ============================================================================
# macOS detection
# ============================================================================
subtest 'macOS: AppleInterfaceStyle=Dark -> dark' => sub {
    my $result = Zepto::ThemeDetect::detect(
        platform => 'darwin',
        run => sub {
            my (@cmd) = @_;
            is_deeply(\@cmd, ['defaults', 'read', '-g', 'AppleInterfaceStyle'],
                'Exact command invoked');
            return ("Dark\n", 0);
        },
    );
    is($result, 'dark', 'Dark mode detected');
};

subtest 'macOS: key absent (nonzero exit) -> light' => sub {
    # `defaults read -g AppleInterfaceStyle` only exists when Dark mode is
    # on — absence (nonzero exit, no stdout) means Light mode.
    my $result = Zepto::ThemeDetect::detect(
        platform => 'darwin',
        run => sub { return ('', 1); },
    );
    is($result, 'light', 'Nonzero exit -> light');
};

subtest 'macOS: exit 0 but empty output -> light' => sub {
    my $result = Zepto::ThemeDetect::detect(
        platform => 'darwin',
        run => sub { return ('', 0); },
    );
    is($result, 'light', 'Empty output -> light');
};

subtest 'macOS: unexpected non-dark value -> light' => sub {
    my $result = Zepto::ThemeDetect::detect(
        platform => 'darwin',
        run => sub { return ("Light\n", 0); },
    );
    is($result, 'light', 'Explicit non-dark value -> light');
};

# ============================================================================
# Linux detection (GNOME via gsettings)
# ============================================================================
subtest 'Linux: gsettings prefer-dark -> dark' => sub {
    my $result = Zepto::ThemeDetect::detect(
        platform => 'linux',
        command_exists => sub { return $_[0] eq 'gsettings' ? 1 : 0; },
        run => sub {
            my (@cmd) = @_;
            is_deeply(\@cmd,
                ['gsettings', 'get', 'org.gnome.desktop.interface', 'color-scheme'],
                'Exact command invoked');
            return ("'prefer-dark'\n", 0);
        },
    );
    is($result, 'dark', 'prefer-dark detected');
};

subtest 'Linux: gsettings default -> light' => sub {
    my $result = Zepto::ThemeDetect::detect(
        platform => 'linux',
        command_exists => sub { return 1; },
        run => sub { return ("'default'\n", 0); },
    );
    is($result, 'light', 'default (non-dark) scheme -> light');
};

subtest 'Linux: gsettings prefer-light -> light' => sub {
    my $result = Zepto::ThemeDetect::detect(
        platform => 'linux',
        command_exists => sub { return 1; },
        run => sub { return ("'prefer-light'\n", 0); },
    );
    is($result, 'light', 'prefer-light -> light');
};

subtest 'Linux: no gsettings -> inconclusive -> dark' => sub {
    my $ran_command = 0;
    my $result = Zepto::ThemeDetect::detect(
        platform => 'linux',
        command_exists => sub { return 0; },
        run => sub { $ran_command = 1; return ('', 0); },
    );
    is($result, 'dark', 'Falls back to dark when gsettings is unavailable');
    ok(!$ran_command, 'Never attempted to run gsettings when absent');
};

# ============================================================================
# Other platforms: inconclusive -> dark
# ============================================================================
subtest 'Unknown platform -> inconclusive -> dark' => sub {
    my $result = Zepto::ThemeDetect::detect(platform => 'freebsd');
    is($result, 'dark', 'No detection source -> dark fallback');
};

# ============================================================================
# platform_supports_polling
# ============================================================================
subtest 'Polling support matrix' => sub {
    ok(Zepto::ThemeDetect::platform_supports_polling(platform => 'darwin'),
        'macOS always supports cheap polling');

    ok(Zepto::ThemeDetect::platform_supports_polling(
        platform => 'linux', command_exists => sub { 1 },
    ), 'Linux with gsettings supports polling');

    ok(!Zepto::ThemeDetect::platform_supports_polling(
        platform => 'linux', command_exists => sub { 0 },
    ), 'Linux without gsettings does not support polling');

    ok(!Zepto::ThemeDetect::platform_supports_polling(platform => 'freebsd'),
        'Unknown platform does not support polling');
};

done_testing();
