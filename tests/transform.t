#!/usr/bin/env perl
# Tests for the shell transform pump (bugs.md P1 "cmd_transform open3
# sequential-slurp can deadlock/hang UI indefinitely").
#
# _run_shell_pump replaced sequential blocking IPC::Open3 reads/writes with
# a select()-driven pump plus a hard wall-clock timeout, to eliminate two
# deadlock scenarios: (1) child fills the stderr pipe while we're still
# blocked reading stdout, (2) input larger than the stdin pipe buffer that
# the child doesn't drain fast enough for a single blocking write to
# complete.
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time);
use lib 'lib';

use Zepto::Editor;
use Zepto::Terminal;
use Zepto::Document;
use Zepto::View;
use Zepto::FindEngine;
use Zepto::Highlighter;
use File::Temp qw(tempfile);

# ============================================================================
# Helpers (mirrors tests/editor.t)
# ============================================================================
sub mock_terminal {
    my ($in_fh, $in_name) = tempfile(UNLINK => 1);
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    return Zepto::Terminal->new(in => $in_fh, out => $out_fh);
}

sub create_temp_file {
    my ($content) = @_;
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh $content;
    close $fh;
    return $filename;
}

sub setup_editor_doc {
    my ($editor, $filename) = @_;
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(document => $doc);
    my $find_engine = Zepto::FindEngine->new(document => $doc);
    my $highlighter = Zepto::Highlighter->new();
    $editor->{tab_manager}->add_tab(
        document    => $doc,
        view        => $view,
        find_engine => $find_engine,
        highlighter => $highlighter,
        file_path   => $filename,
    );
    return ($doc, $view);
}

# ============================================================================
# _run_shell_pump — direct pump tests
# ============================================================================

subtest 'Fast command: normal round trip works' => sub {
    my $result = Zepto::Editor::_run_shell_pump('tr a-z A-Z', "hello\n", 10);
    ok(!$result->{timed_out}, 'Not timed out');
    is($result->{exit_code}, 0, 'Exit code 0');
    is($result->{output}, "HELLO\n", 'Output transformed correctly');
};

subtest 'Command with no input still works (stdin closed immediately)' => sub {
    my $result = Zepto::Editor::_run_shell_pump('echo fixed-output', '', 10);
    ok(!$result->{timed_out}, 'Not timed out');
    is($result->{exit_code}, 0, 'Exit code 0');
    is($result->{output}, "fixed-output\n", 'Output captured');
};

subtest 'Non-zero exit code and stderr are both captured' => sub {
    my $result = Zepto::Editor::_run_shell_pump(
        'echo boom 1>&2; exit 3', '', 10
    );
    ok(!$result->{timed_out}, 'Not timed out');
    is($result->{exit_code}, 3, 'Exit code captured');
    like($result->{stderr}, qr/boom/, 'Stderr captured');
};

subtest 'Stderr-heavy command does not deadlock (classic sequential-read hang)' => sub {
    # The old code did `$output = <$out_fh>; $stderr_text = <$err_fh>;`
    # sequentially. A child that writes enough to stderr to fill its pipe
    # buffer (commonly 64KB) BEFORE we finish reading stdout would block
    # forever: the child blocks writing to stderr, we're still blocked
    # reading stdout. Simulate exactly that: write to stderr first, in a
    # size well over typical pipe buffers, then stdout.
    my $cmd = q{perl -e 'print STDERR "e" x 200000; print STDOUT "done\n";'};
    my $start = time();
    my $result = Zepto::Editor::_run_shell_pump($cmd, '', 10);
    my $elapsed = time() - $start;

    ok(!$result->{timed_out}, 'Not timed out (would hang under the old code)');
    ok($elapsed < 5, "Completed quickly ($elapsed sec), not deadlocked");
    is($result->{output}, "done\n", 'Stdout captured correctly');
    is(length($result->{stderr}), 200000, 'All 200000 stderr bytes captured, none dropped');
};

subtest 'Large round trip: >64KB both directions via cat' => sub {
    my $input = ('A'..'Z')[0] x 70000 . "\n";  # > 64KB stdin
    # cat both echoes stdin to stdout AND we ask it to also produce output
    # on stderr via a wrapper, to exercise both directions over 64KB.
    my $cmd = q{cat; head -c 70000 /dev/zero | tr '\0' 'B' 1>&2};
    my $result = Zepto::Editor::_run_shell_pump($cmd, $input, 15);

    ok(!$result->{timed_out}, 'Not timed out');
    is($result->{exit_code}, 0, 'Exit code 0');
    is(length($result->{output}), length($input), 'Full >64KB stdout round-trip, no truncation');
    is($result->{output}, $input, 'Stdout content matches input exactly');
    is(length($result->{stderr}), 70000, 'Full >64KB stderr captured, no truncation');
};

subtest 'Timeout: hung command is killed and reported, does not hang the test' => sub {
    my $start = time();
    my $result = Zepto::Editor::_run_shell_pump('sleep 30', '', 0.3);
    my $elapsed = time() - $start;

    ok($result->{timed_out}, 'Reported as timed out');
    ok($elapsed < 3, "Returned promptly ($elapsed sec) rather than waiting the full 30s sleep");
};

subtest 'Timeout: pipeline grandchildren are killed too, not orphaned' => sub {
    # `sh -c $cmd` can spawn a pipeline of its own children. Killing just
    # the immediate `sh` pid would leave those orphaned and still running
    # — verify the whole process group actually dies. Use a marker file
    # each stage removes on exit via a trap, so we can tell whether the
    # grandchild was actually killed (still running -> file still exists
    # after we've waited past when it would have deleted it) vs completed
    # normally (n/a here, since it should never reach that point).
    my ($fh, $marker) = tempfile(UNLINK => 0);
    close $fh;
    unlink $marker;  # start absent; grandchild creates it only once killed via trap

    # Grandchild: trap TERM/EXIT to touch the marker file, then sleep.
    # If it's still alive and gets killed, the trap fires and creates the
    # marker. If it were orphaned (not killed), it would still be asleep
    # and the marker would NOT appear within our short check window.
    my $cmd = qq{sh -c 'trap "touch $marker; exit" TERM; sleep 30' & wait};

    my $result = Zepto::Editor::_run_shell_pump($cmd, '', 0.3);
    ok($result->{timed_out}, 'Reported as timed out');

    # Give the killed grandchild's trap a brief moment to run.
    my $deadline = time() + 3;
    my $marker_appeared = 0;
    while (time() < $deadline) {
        if (-e $marker) { $marker_appeared = 1; last; }
        select(undef, undef, undef, 0.1);
    }
    ok($marker_appeared, 'Grandchild process was actually signaled (marker file created), not orphaned');
    unlink $marker;
};

subtest 'Success path: process that closes its pipes but lingers does not hang the pump' => sub {
    # Reaching EOF on both stdout and stderr does NOT guarantee the
    # process itself has exited yet — a security review of this pump
    # flagged that the original success-path tail did a bare
    # `waitpid($pid, 0)` with no bound, which would hang forever on a
    # process that explicitly closes its output fds (e.g. a daemonizing
    # helper, or something that dup2's its fds away) and then keeps
    # running. Simulate exactly that: close fd 1 and 2, THEN sleep well
    # past _bounded_reap's grace period, so our read loop sees EOF almost
    # immediately while the process itself lingers.
    my $cmd = q{exec 1>&-; exec 2>&-; sleep 30};
    my $start = time();
    my $result = Zepto::Editor::_run_shell_pump($cmd, '', 10);
    my $elapsed = time() - $start;

    ok(!$result->{timed_out}, 'Not reported as a pump timeout (EOF was seen well within the 10s budget)');
    ok($elapsed < 6, "Returned promptly (${elapsed}s) instead of hanging on the lingering process");
};

subtest 'Timeout: command ignoring input (broken pipe) does not hang the write side' => sub {
    # A command that never reads stdin at all — exercises the EPIPE/SIGPIPE
    # handling path on the write side.
    my $big_input = 'x' x 200000;
    my $start = time();
    my $result = Zepto::Editor::_run_shell_pump('true', $big_input, 5);
    my $elapsed = time() - $start;

    ok(!$result->{timed_out}, 'Not timed out');
    ok($elapsed < 5, "Completed promptly ($elapsed sec)");
};

# ============================================================================
# cmd_transform integration — driven via the editor object
# ============================================================================

subtest 'cmd_transform: happy path replaces selection with command output' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("hello world\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    my ($doc, $view) = setup_editor_doc($editor, $filename);

    $view->select_all();
    $editor->cmd_transform();
    is($editor->{state}, 'footer_input', 'Footer input opened');

    $editor->{footer_input}{on_submit}->('tr a-z A-Z');

    is($doc->get_line(0), "HELLO WORLD", 'Selection replaced with transformed output');
};

subtest 'cmd_transform: timeout leaves buffer unchanged and shows an error' => sub {
    local $ENV{ZEPTO_TRANSFORM_TIMEOUT} = 0.3;

    my $term = mock_terminal();
    my $original = "do not touch me\n";
    my $filename = create_temp_file($original);
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    my ($doc, $view) = setup_editor_doc($editor, $filename);

    $view->select_all();
    $editor->cmd_transform();

    my $start = time();
    $editor->{footer_input}{on_submit}->('sleep 30');
    my $elapsed = time() - $start;

    ok($elapsed < 5, "on_submit returned promptly ($elapsed sec), editor not hung");
    like($editor->{message}, qr/timed out/i, 'Status bar shows a timeout error');
    ok($editor->{message_is_error}, 'Message is flagged as an error');
    is($doc->get_line(0), 'do not touch me', 'Buffer content unchanged after timeout');
};

done_testing;
