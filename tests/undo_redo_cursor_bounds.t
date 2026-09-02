#!/usr/bin/env perl
# Fuzz-style sweep: the cursor must ALWAYS be within the document's bounds
# after every undo/redo/movement step.
#
# Background (ASKS.md item 0, P0): a user reported "I pasted a block of text,
# then hit undo, then some sequence of moving / redo, and my cursor ended up
# outside of the valid line numbers." The exact trigger was never pinned down,
# so this file sweeps a wide permutation space instead of asserting one
# hand-picked sequence, and checks the invariant after EVERY step rather than
# only at the end.
#
# Instrument note: this sweep drives Zepto::Document + Zepto::View directly,
# replicating the exact operation sequence that Zepto::Editor::Commands
# performs, so that a few thousand permutations run in well under a second:
#   - paste  == cmd_paste (Commands.pm:516-526): line_col_to_offset ->
#               $doc->insert -> $view->set_cursor(offset_to_line_col(end))
#   - undo   == cmd_undo (Commands.pm):  $doc->undo()  then $view->clamp_to_document()
#   - redo   == cmd_redo (Commands.pm):  $doc->redo()  then $view->clamp_to_document()
# The same sequences are exercised through the real Zepto::Editor command
# methods in tests/editor.t ('Cursor stays in bounds across undo/redo'), so
# the real command path is covered too and this file is not the only evidence.

use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::Document;
use Zepto::View;

# ============================================================================
# The invariant
# ============================================================================

# Returns a human-readable violation string, or undef when everything is in
# range. Checks the primary cursor, the selection anchor, and every extra
# multi-cursor -- all of them index into the document and all of them can go
# stale when the document shrinks underneath the view.
sub bounds_violation {
    my ($doc, $view) = @_;

    my $line_count = $doc->line_count();
    return "line_count is $line_count (documents always have >= 1 line)"
        if $line_count < 1;

    my $check = sub {
        my ($what, $line, $col) = @_;
        return undef unless defined $line;
        return "$what line $line out of range [0, $line_count)"
            if $line < 0 || $line >= $line_count;
        return undef unless defined $col;
        my $len = $doc->line_length($line);
        return "$what col $col out of range [0, $len] on line $line"
            if $col < 0 || $col > $len;
        return undef;
    };

    my $v = $check->('cursor', $view->cursor_line(), $view->cursor_col());
    return $v if $v;

    $v = $check->('selection anchor',
                  $view->{selection_anchor_line}, $view->{selection_anchor_col});
    return $v if $v;

    my $i = 0;
    for my $mc (@{ $view->multi_cursors() }) {
        $v = $check->("multi-cursor $i", $mc->{line}, $mc->{col});
        return $v if $v;
        $v = $check->("multi-cursor $i anchor", $mc->{anchor_line}, $mc->{anchor_col});
        return $v if $v;
        $i++;
    }

    return undef;
}

# ============================================================================
# Operations
# ============================================================================

# Each op is a closure taking ($doc, $view). Movement ops are included because
# the user's report specifically involved "some sequence of moving / redo".
my %OPS = (
    undo      => sub { $_[0]->undo() and $_[1]->clamp_to_document() },
    redo      => sub { $_[0]->redo() and $_[1]->clamp_to_document() },
    up        => sub { $_[1]->move_up() },
    down      => sub { $_[1]->move_down() },
    left      => sub { $_[1]->move_left() },
    right     => sub { $_[1]->move_right() },
    home      => sub { $_[1]->move_to_line_start() },
    end       => sub { $_[1]->move_to_line_end() },
    pgup      => sub { $_[1]->move_page_up() },
    pgdn      => sub { $_[1]->move_page_down() },
    doc_start => sub { $_[1]->move_to_document_start() },
    doc_end   => sub { $_[1]->move_to_document_end() },
    word_left => sub { $_[1]->move_word_left() },
    word_right=> sub { $_[1]->move_word_right() },
);

# Replicates cmd_paste's non-columnar path (Commands.pm:516-526).
sub do_paste {
    my ($doc, $view, $text) = @_;
    my $offset = $doc->line_col_to_offset($view->cursor_line(), $view->cursor_col());
    $doc->insert($offset, $text);
    my ($line, $col) = $doc->offset_to_line_col($offset + length($text));
    $view->set_cursor($line, $col);
}

# ============================================================================
# Document shapes and paste payloads
# ============================================================================

my @DOCS = (
    { name => 'single line, no trailing NL', text => "only line" },
    { name => 'single line, trailing NL',    text => "only line\n" },
    { name => 'multi-line, trailing NL',     text => "alpha\nbeta\ngamma\n" },
    { name => 'multi-line, no trailing NL',  text => "alpha\nbeta\ngamma" },
    { name => 'with blank lines',            text => "alpha\n\nbeta\n\n\ngamma\n" },
    { name => 'empty document',              text => "" },
);

my @PASTES = (
    { name => 'multi-line block',          text => "one\ntwo\nthree\nfour\nfive\n" },
    { name => 'multi-line, no trailing NL',text => "one\ntwo\nthree" },
    { name => 'single line',               text => "inserted" },
    { name => 'blank-line block',          text => "\n\n\n" },
);

# Cursor placements to paste at: start of doc, an interior line, end of a
# line, end of doc. Resolved against the actual doc so they stay valid for
# every shape above.
my @POSITIONS = (
    { name => 'start of document', where => sub { (0, 0) } },
    { name => 'end of first line', where => sub { (0, $_[0]->line_length(0)) } },
    { name => 'middle line',       where => sub {
          my $l = int($_[0]->line_count() / 2); ($l, 0) } },
    { name => 'last line, col 0',  where => sub { ($_[0]->line_count() - 1, 0) } },
    { name => 'end of document',   where => sub {
          my $l = $_[0]->line_count() - 1; ($l, $_[0]->line_length($l)) } },
);

# ============================================================================
# Sequence generation
# ============================================================================

# All sequences of length 1..3 drawn from a pool weighted toward the ops the
# user described (undo / redo / movement), plus a handful of longer
# hand-written sequences covering "multiple back-to-back paste+undo+redo
# cycles" and "undo across a line that was deleted then the deletion undone".
my @POOL = qw(undo redo up down left right home end pgup pgdn doc_start doc_end);

# Length-3 uses a reduced pool so the whole sweep stays under a second
# (Rule 3: slow tests are a bug). It keeps both undo/redo plus one movement
# of each kind -- vertical, horizontal, line-wise, page-wise, document-wise.
my @POOL3 = qw(undo redo down right end pgdn doc_end);

my @SEQUENCES;
for my $a (@POOL) {
    push @SEQUENCES, [$a];
    for my $b (@POOL) {
        push @SEQUENCES, [$a, $b];
    }
}
# Length-3 sequences: require at least one undo and one redo (the reported
# bug's shape) rather than enumerating the full cube.
for my $a (@POOL3) {
    for my $b (@POOL3) {
        for my $c (@POOL3) {
            my $s = "$a $b $c";
            next unless $s =~ /undo/ && $s =~ /redo/;
            push @SEQUENCES, [$a, $b, $c];
        }
    }
}
# Explicit longer sequences from the ASKS.md description.
push @SEQUENCES,
    [qw(undo undo redo redo)],
    [qw(undo redo undo redo)],
    [qw(undo down redo up)],
    [qw(undo doc_end redo doc_start)],
    [qw(undo undo undo redo redo redo)],
    [qw(down undo pgdn redo pgup undo)],
    [qw(undo word_right redo word_left undo redo)];

# ============================================================================
# The sweep
# ============================================================================

my $total      = 0;
my $violations = 0;
my @examples;   # first few distinct failures, for the diagnostic output

for my $d (@DOCS) {
    for my $p (@PASTES) {
        for my $pos (@POSITIONS) {
            for my $seq (@SEQUENCES) {
                $total++;

                my $doc = Zepto::Document->new(text => $d->{text});
                my $view = Zepto::View->new(
                    document      => $doc,
                    viewport_rows => 5,     # small, so page up/down move far
                    viewport_cols => 40,
                );

                my ($sl, $sc) = $pos->{where}->($doc);
                $view->set_cursor($sl, $sc);

                do_paste($doc, $view, $p->{text});

                my $step = "paste";
                my $bad  = bounds_violation($doc, $view);

                unless ($bad) {
                    for my $op (@$seq) {
                        $OPS{$op}->($doc, $view);
                        $step = $op;
                        $bad = bounds_violation($doc, $view);
                        last if $bad;
                    }
                }

                if ($bad) {
                    $violations++;
                    push @examples, sprintf(
                        "doc[%s] paste[%s] at[%s] seq[%s] -- broke after '%s': %s",
                        $d->{name}, $p->{name}, $pos->{name},
                        join(',', @$seq), $step, $bad
                    ) if @examples < 8;
                }
            }
        }
    }
}

# note() rather than diag() so a passing run stays silent (Rule 3: no
# unexpected output); the failure details below still use diag().
note("swept $total permutations");
if ($violations) {
    diag("first failing permutations:");
    diag("  $_") for @examples;
}

is($violations, 0,
   "cursor stayed in bounds after every step of all $total paste/undo/redo/move permutations");

# ============================================================================
# Sanity check on the sweep itself: it must be able to SEE a violation.
#
# Without this, a bug in bounds_violation() (or a sweep that silently never
# reaches its subject) would report a vacuous pass. Force a known-bad state
# by hand and confirm the checker flags it.
# ============================================================================
subtest 'the bounds checker actually detects an out-of-range cursor' => sub {
    my $doc  = Zepto::Document->new(text => "a\nb\nc\n");
    my $view = Zepto::View->new(document => $doc, viewport_rows => 5, viewport_cols => 40);

    ok(!defined bounds_violation($doc, $view), 'clean state reports no violation');

    # Poke the field directly -- set_cursor() would clamp it.
    $view->{cursor_line} = 99;
    like(bounds_violation($doc, $view), qr/cursor line 99 out of range/,
         'out-of-range cursor line is detected');

    $view->{cursor_line} = 0;
    $view->{cursor_col}  = 99;
    like(bounds_violation($doc, $view), qr/cursor col 99 out of range/,
         'out-of-range cursor col is detected');

    $view->{cursor_col} = 0;
    $view->{selection_anchor_line} = 42;
    $view->{selection_anchor_col}  = 0;
    like(bounds_violation($doc, $view), qr/selection anchor line 42 out of range/,
         'out-of-range selection anchor is detected');
};

done_testing();
