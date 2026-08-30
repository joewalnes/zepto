#!/usr/bin/env perl
# WCAG contrast audit for Zepto::Theme
#
# Every themed color is a hand-picked RGB triple (see Theme.pm) — nothing
# computes or checks contrast when a theme is written or edited, so a color
# tuned for one theme (or one background) can silently become unreadable
# against another. This test catches that whole bug class automatically
# instead of relying on a human to notice, e.g., a barely-visible tab icon.
#
# Pairing strategy (best-effort, not exhaustive):
#   1. Same-prefix pairs: any role "X_fg" with a sibling "X_bg" is checked
#      directly — this covers pills, segments, and other self-contained
#      two-color components precisely, with zero maintenance as new pairs
#      are added (inferred from naming convention, not a hand-kept list).
#   2. "_bg_fg" and "_edge" roles are excluded: these intentionally reuse a
#      NEIGHBORING background's color as a foreground/border color to draw
#      seamless pill caps — they are not readability colors and comparing
#      them to their own reference bg would always show ~0 contrast.
#   3. Remaining "orphan" fg roles (no same-prefix bg) render on whichever
#      surface currently contains them. A handful of known multi-surface
#      roles (e.g. a tab icon, which can sit on the active/inactive/hover
#      tab background) are checked against every surface they can actually
#      appear on, via %SURFACE_OVERRIDE below. Anything not in that table
#      falls back to the base editor fg/bg pair as the most common surface.
#      This is a heuristic, not formal verification — if a future orphan fg
#      role renders somewhere unexpected, add it to %SURFACE_OVERRIDE.
#
# Threshold: WCAG 3.0:1 (the "UI components and graphical objects" minimum,
# not the stricter 4.5:1 body-text minimum) — appropriate for a TUI where
# most text renders bold/large relative to typical body copy, and avoids
# false positives on legitimately-subtle design choices while still
# catching genuinely broken pairs.

use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::Theme;

use constant MIN_CONTRAST => 3.0;

# Pre-existing contrast debt, found by this test's first run (2026-08-30)
# and not yet fixed — tracked in bugs.md ("P2: Pre-existing theme contrast
# debt found by tests/theme_contrast.t"). This list must only ever SHRINK:
# do not add a role here to silence a NEW regression — fix the color
# instead. New roles are held to the full threshold from day one.
my %KNOWN_DEBT = map { $_ => 1 } (
    'dark:completion_border_fg/dropdown_bg', 'dark:completion_border_fg/menu_bg',
    'dark:gutter_fg/gutter_bg', 'dark:menu_pill_fg/menu_pill_bg',
    'dark:minimap_text_fg/bg', 'dark:ruler_fg/ruler_bg',
    'dark:tab_close_fg/tab_active_bg', 'dark:tab_close_fg/tab_hover_bg',
    'dark:tab_close_fg/tab_inactive_bg', 'dark:tab_shortcut_fg/tab_active_bg',
    'dark:table_border_fg/bg', 'dark:tree_border_fg/tree_bg',
    'dark:tree_indent_fg/tree_bg', 'dark:tree_scrollbar_fg/tree_scrollbar_bg',
    'dark:wrap_indicator_fg/bg',
    'light:completion_border_fg/dropdown_bg', 'light:completion_border_fg/menu_bg',
    'light:completion_ghost_fg/bg', 'light:dropdown_selected_fg/dropdown_selected_bg',
    'light:gutter_fg/gutter_bg', 'light:menu_active_fg/menu_active_bg',
    'light:menu_pill_fg/menu_pill_bg', 'light:minimap_text_fg/bg',
    'light:ruler_fg/ruler_bg', 'light:status_modified_fg/status_bg',
    'light:status_pos_fg/status_pos_bg', 'light:tab_close_fg/tab_active_bg',
    'light:tab_close_fg/tab_hover_bg', 'light:tab_close_fg/tab_inactive_bg',
    'light:tab_shortcut_fg/tab_active_bg', 'light:tab_shortcut_fg/tab_hover_bg',
    'light:tab_shortcut_fg/tab_inactive_bg', 'light:tab_vcs_fg/tab_active_bg',
    'light:table_border_fg/bg', 'light:tree_border_active_fg/tree_bg',
    'light:tree_border_drag_fg/tree_bg', 'light:tree_border_fg/tree_bg',
    'light:tree_indent_fg/tree_bg', 'light:tree_scrollbar_fg/tree_scrollbar_bg',
    'light:warning_fg/bg', 'light:warning_fg/status_bg', 'light:wrap_indicator_fg/bg',
);

# ---------------------------------------------------------------------------
# WCAG relative luminance / contrast ratio
# ---------------------------------------------------------------------------

sub _linearize {
    my ($c) = @_;
    $c /= 255;
    return $c <= 0.03928 ? $c / 12.92 : (($c + 0.055) / 1.055) ** 2.4;
}

sub _relative_luminance {
    my ($r, $g, $b) = @_;
    return 0.2126 * _linearize($r) + 0.7152 * _linearize($g) + 0.0722 * _linearize($b);
}

sub _contrast_ratio {
    my ($rgb1, $rgb2) = @_;
    my $l1 = _relative_luminance(@$rgb1);
    my $l2 = _relative_luminance(@$rgb2);
    ($l1, $l2) = ($l2, $l1) if $l2 > $l1;
    return ($l1 + 0.05) / ($l2 + 0.05);
}

# Extract the (r,g,b) triple from a Theme-generated ANSI escape sequence.
# Returns undef if the role isn't a truecolor fg/bg sequence (e.g. a bare
# reset or a role that doesn't exist in this theme).
sub _rgb_of {
    my ($ansi) = @_;
    return undef unless defined $ansi;
    return [$1, $2, $3] if $ansi =~ /\x1b\[[34]8;2;(\d+);(\d+);(\d+)m/;
    return undef;
}

# ---------------------------------------------------------------------------
# Multi-surface overrides for orphan fg roles (see header comment)
# ---------------------------------------------------------------------------

my %SURFACE_OVERRIDE = (
    tab_modified => ['tab_active_bg', 'tab_inactive_bg', 'tab_hover_bg'],
    tab_close    => ['tab_active_bg', 'tab_inactive_bg', 'tab_hover_bg'],
    tab_shortcut => ['tab_active_bg', 'tab_inactive_bg', 'tab_hover_bg'],
    tab_vcs      => ['tab_active_bg', 'tab_inactive_bg', 'tab_hover_bg'],
    status_modified => ['status_bg'],
    tree_dir         => ['tree_bg'],
    tree_indent      => ['tree_bg'],
    tree_match       => ['tree_bg'],
    tree_preview     => ['tree_bg'],
    tree_result_dir  => ['tree_bg'],
    tree_border      => ['tree_bg'],
    tree_border_active => ['tree_bg'],
    tree_border_drag   => ['tree_bg'],
    completion_border => ['dropdown_bg', 'menu_bg'],
    completion_ghost   => ['bg'],  # ghost text renders inline in the editor
    completion_kind    => ['dropdown_bg', 'menu_bg'],
    fsr_path           => ['dropdown_bg'],
    fsr_path_active     => ['dropdown_bg'],
    minimap_cursor      => ['bg'],
    minimap_text        => ['bg'],
    table_border        => ['bg'],
    wrap_indicator       => ['bg'],
    error   => ['bg', 'status_bg'],
    warning => ['bg', 'status_bg'],
    info    => ['bg', 'status_bg'],
);

# ---------------------------------------------------------------------------
# Build the list of (theme_name, fg_role, bg_role) checks
# ---------------------------------------------------------------------------

sub _checks_for_theme {
    my ($theme) = @_;
    my $colors = $theme->{colors};
    my @fg_roles = grep { /_fg$/ && !/_bg_fg$/ } keys %$colors;

    my @checks;
    for my $fg_role (@fg_roles) {
        (my $prefix = $fg_role) =~ s/_fg$//;
        my $sibling_bg = "${prefix}_bg";

        if (exists $colors->{$sibling_bg}) {
            push @checks, [$fg_role, $sibling_bg];
            next;
        }

        if (my $surfaces = $SURFACE_OVERRIDE{$prefix}) {
            push @checks, [$fg_role, $_] for @$surfaces;
            next;
        }

        # Default fallback: base editor surface
        push @checks, [$fg_role, 'bg'];
    }
    return @checks;
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

for my $theme_ctor (qw(dark_theme light_theme)) {
    my $theme = Zepto::Theme->$theme_ctor();
    my $name  = $theme->name();

    subtest "Contrast — $name theme" => sub {
        my @checks = _checks_for_theme($theme);
        ok(@checks > 50, "found a substantial number of checks ($name: " . scalar(@checks) . ")");

        for my $check (sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @checks) {
            my ($fg_role, $bg_role) = @$check;
            my $fg_rgb = _rgb_of($theme->color($fg_role));
            my $bg_rgb = _rgb_of($theme->color($bg_role));

            # Skip roles that aren't truecolor RGB (e.g. RESET, or a role
            # missing in this theme) — not a contrast failure, just N/A.
            next unless $fg_rgb && $bg_rgb;

            my $ratio = _contrast_ratio($fg_rgb, $bg_rgb);
            my $debt_key = "$name:$fg_role/$bg_role";
            if ($KNOWN_DEBT{$debt_key}) {
                # Not silently ignored: still visible in TAP output as a
                # TODO so `prove -v` shows exactly what's outstanding.
              TODO: {
                    local $TODO = 'pre-existing contrast debt, see bugs.md';
                    ok($ratio >= MIN_CONTRAST,
                       sprintf("%s on %s: %.2f:1 (need >= %.1f:1)",
                               $fg_role, $bg_role, $ratio, MIN_CONTRAST));
                }
                next;
            }
            ok($ratio >= MIN_CONTRAST,
               sprintf("%s on %s: %.2f:1 (need >= %.1f:1)",
                       $fg_role, $bg_role, $ratio, MIN_CONTRAST));
        }
    };
}

done_testing();
