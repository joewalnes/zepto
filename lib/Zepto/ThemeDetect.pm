package Zepto::ThemeDetect;
# =============================================================================
# ThemeDetect: System dark/light appearance detection for the "auto" theme
# =============================================================================
#
# Detects the OS/desktop appearance preference so the "auto" theme
# preference (see Zepto::Preferences) can pick a matching editor theme.
# Perl core only — no CPAN, no network. Subprocess exec uses list-form
# `open(my $fh, '-|')` + `exec(@cmd)` (never shell interpolation), per
# docs/SECURITY.md.
#
# Detection matrix:
#   macOS ($^O eq 'darwin')
#     `defaults read -g AppleInterfaceStyle`
#     Key only exists when Dark mode is on. Present + matches /dark/i =>
#     dark. Absent (nonzero exit) or anything else => light.
#
#   Linux ($^O eq 'linux')
#     If `gsettings` is on PATH:
#       `gsettings get org.gnome.desktop.interface color-scheme`
#       Value containing "prefer-dark" => dark, else light.
#     Without gsettings: inconclusive. (A terminal OSC 11 background-color
#     query was considered as a further fallback here, but was deliberately
#     scoped out of v1 — see bugs.md P3 "Automatic dark/light mode" for the
#     reasoning. Detection just falls back to dark, same as any other
#     inconclusive case.)
#
#   Any other platform: inconclusive.
#
# Inconclusive detection always resolves to 'dark' — the editor's
# long-standing default theme — so "auto" never surprises a user with no
# usable signal.
#
# Every function accepts optional injected collaborators so tests never
# shell out (see tests/theme_detect.t):
#   platform       => override for $^O
#   run            => sub { my (@cmd) = @_; ...; return ($stdout, $exit_code); }
#   command_exists => sub { my ($name) = @_; return 0|1; }
# =============================================================================

use strict;
use warnings;

# Detect the current system appearance. Returns 'dark' or 'light' — never
# undef, never anything else.
sub detect {
    my (%opts) = @_;
    my $platform = $opts{platform} // $^O;
    my $run       = $opts{run} // \&_run_capture;
    my $cmd_exists = $opts{command_exists} // \&_command_exists;

    if ($platform eq 'darwin') {
        return _detect_macos($run);
    }
    if ($platform eq 'linux') {
        return _detect_linux($run, $cmd_exists);
    }

    return 'dark';  # No known detection source on this platform
}

# Whether cheap (single subprocess, no terminal round-trip) runtime
# re-polling is worthwhile on this platform. Editor.pm's idle-loop poll is
# gated on this so it never shells out on platforms/desktops where there's
# no dependable signal at all (e.g. Linux without gsettings).
sub platform_supports_polling {
    my (%opts) = @_;
    my $platform = $opts{platform} // $^O;
    my $cmd_exists = $opts{command_exists} // \&_command_exists;

    return 1 if $platform eq 'darwin';
    return 1 if $platform eq 'linux' && $cmd_exists->('gsettings');
    return 0;
}

sub _detect_macos {
    my ($run) = @_;
    my ($out, $exit) = $run->('defaults', 'read', '-g', 'AppleInterfaceStyle');
    return 'light' if !defined $out || $exit != 0;
    chomp $out;
    return 'light' if $out eq '';
    return ($out =~ /dark/i) ? 'dark' : 'light';
}

sub _detect_linux {
    my ($run, $cmd_exists) = @_;
    return 'dark' unless $cmd_exists->('gsettings');  # inconclusive -> default

    my ($out, undef) = $run->('gsettings', 'get', 'org.gnome.desktop.interface', 'color-scheme');
    return 'dark' unless defined $out && $out ne '';  # inconclusive -> default
    return ($out =~ /prefer-dark/i) ? 'dark' : 'light';
}

# Run a command with list-form exec (no shell interpretation), suppressing
# stderr. Returns (stdout, exit_code). Deliberately duplicated (rather than
# imported) from Terminal.pm's _safe_backtick/_command_exists so this
# module has no dependency on Terminal.pm.
sub _run_capture {
    my (@cmd) = @_;
    my $pid = open(my $fh, '-|');
    return ('', -1) unless defined $pid;
    if ($pid == 0) {
        open(STDERR, '>', '/dev/null');
        exec(@cmd) or exit(127);
    }
    my $output = do { local $/; <$fh> };
    close($fh);
    my $exit_code = $? >> 8;
    return (defined $output ? $output : '', $exit_code);
}

sub _command_exists {
    my ($name) = @_;
    my ($out, $exit) = _run_capture('which', $name);
    return defined $out && $out ne '' && $exit == 0;
}

1;
