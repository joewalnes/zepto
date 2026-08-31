#!/usr/bin/env perl
# Regression test for bugs.md P1 "cmd_transform (⌥T, 'Transform via
# Shell') can deadlock the whole editor" / QA-REG-187.
#
# Root cause: cmd_transform (Editor/Commands.pm) used IPC::Open3 and read
# the child's stdout to EOF *before* touching stderr at all. If the shell
# command writes enough to stderr (~64KB, the typical OS pipe buffer
# size) while also writing to stdout, the child blocks writing to a full
# stderr pipe nobody is reading yet, while the parent blocks reading
# stdout waiting for the child to close it -- deadlock. Since raw mode
# disables ISIG, the user can't even Ctrl-C out.
#
# We can't literally let a broken implementation hang forever in a test
# run, so this test bounds the call in an alarm()-guarded eval: if the
# fix works, cmd_transform returns well within the alarm; if the
# regression reappears, the alarm fires and we fail loudly instead of
# hanging the test suite.
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempfile);

use Zepto::Editor;
use Zepto::Terminal;
use Zepto::Document;
use Zepto::View;
use Zepto::FindEngine;
use Zepto::Highlighter;

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

# Sanity: skip if perl isn't reachable via sh -c (should always be true
# in this test environment, but don't hang the whole suite if not).
my $has_sh_perl = system('sh', '-c', 'perl -e 1') == 0;
plan skip_all => 'sh -c perl not available' unless $has_sh_perl;

subtest 'cmd_transform does not deadlock when child writes >64KB to stderr and stdout' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("some input text\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_transform();
    ok($editor->{footer_input} && $editor->{footer_input}->{on_submit},
        'cmd_transform opened footer input with on_submit');

    # Writes ~100KB to stderr (well past the typical 64KB pipe buffer)
    # interleaved with small stdout writes on either side, reproducing
    # exactly the deadlock shape described in bugs.md.
    my $shell_cmd = q{perl -e 'print STDOUT "x" x 100; print STDERR "e" x 100000; print STDOUT "y" x 100'};

    # NOTE: cmd_transform wraps its child I/O in its own eval{}, so even
    # a genuine deadlock that gets interrupted by this outer alarm gets
    # swallowed by cmd_transform's own `if ($@) { show_error_message;
    # return }` handling rather than re-thrown here -- it returns
    # "successfully" either way. The alarm below is therefore only a
    # last-resort safety net so a regression can't hang the whole test
    # suite; the real assertion is on ELAPSED WALL TIME: the deadlocked
    # implementation blocks for the full alarm duration, while a correct
    # concurrent-read implementation returns in well under a second.
    my $start = time();
    eval {
        local $SIG{ALRM} = sub { die "transform_deadlock_timeout\n" };
        alarm(8);
        $editor->{footer_input}->{on_submit}->($shell_cmd);
        alarm(0);
    };
    alarm(0);  # Ensure alarm is cancelled even on exception
    my $elapsed = time() - $start;
    diag("on_submit raised: $@") if $@ && $@ ne "transform_deadlock_timeout\n";

    ok($elapsed < 5, "cmd_transform returned quickly (${elapsed}s), not blocked on the stdout/stderr deadlock")
        or diag('cmd_transform is hanging -- the stdout/stderr sequential-read deadlock has regressed');

    my $doc = $editor->active_doc();
    is($doc->text(), ('x' x 100) . ('y' x 100),
        'stdout was captured correctly despite the large stderr write');
};

done_testing;
