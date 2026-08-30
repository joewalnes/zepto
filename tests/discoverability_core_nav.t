#!/usr/bin/env perl
# Discoverability Contract audit (see docs/UI_GUIDELINES.md
# "Discoverability Contract") — deterministic half.
#
# Core navigation (switch tree/editor focus, move across tabs, close a
# tab, quit) must have a persistent on-screen hint, not be palette-only —
# the same standard Save/Find/Word Wrap already meet. This test asserts
# the necessary precondition: each core-nav command is eligible for an
# always-visible on-screen hint — either as a status bar pill
# (`priority > 0`) or via a dedicated always-visible hint elsewhere that
# CommandRegistry knows about via `core_nav => 1` (e.g. next_tab/prev_tab/
# close_tab/quit render via the tab-bar corner hint in Renderer.pm's
# _render_tab_bar, not through the pill-priority system — see bugs.md).
#
# core_nav => 1 exists specifically so this check has one source of truth
# instead of two independently-maintained mechanisms that used to only
# agree by accident (see bugs.md "Discoverability Contract gaps" — the
# registry had no knowledge of the hardcoded tab-bar hint at all).
#
# This is NECESSARY but not SUFFICIENT: CommandRegistry::commands_for_
# status_bar() currently only serves the 'document' context ("Only show
# status bar pills in document context for now" — CommandRegistry.pm).
# FILE_TREE, FIND, and other contexts use their own hand-written
# renderers that don't consult priority (or core_nav) at all, so a
# command could pass this test and still be invisible while the tree is
# focused. The LLM visual sweep (qa/scripts/tier2/discoverability sweep)
# is the complementary check for those contexts — this test only catches
# "never eligible anywhere," not "eligible but not actually rendered
# in the context the user is currently in."

use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::CommandRegistry;

# The core navigation set named explicitly in docs/UI_GUIDELINES.md's
# Discoverability Contract. Add to this list if the contract's definition
# of "core navigation" grows — do not remove an entry to make a
# regression pass.
my @CORE_NAV_IDS = qw(
    toggle_tree
    next_tab
    prev_tab
    close_tab
    quit
);

for my $id (@CORE_NAV_IDS) {
    my $cmd = Zepto::CommandRegistry->find_command($id);
    ok($cmd, "core-nav command '$id' exists in the registry")
        or next;

    my $covered = ($cmd->{core_nav} // 0) || ($cmd->{priority} // 0) > 0;
    ok($covered,
       "core-nav command '$id' has core_nav => 1 or priority > 0 (eligible for an always-visible on-screen hint, not palette-only)");
}

done_testing();
