#!/usr/bin/env perl
# Tests for Zepto::Theme
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::Theme;

# ============================================================================
# Color Helpers
# ============================================================================
subtest 'RGB foreground colors' => sub {
    my $color = Zepto::Theme::fg_rgb(255, 128, 0);
    is($color, "\x1b[38;2;255;128;0m", 'RGB foreground escape sequence');
};

subtest 'RGB background colors' => sub {
    my $color = Zepto::Theme::bg_rgb(100, 50, 200);
    is($color, "\x1b[48;2;100;50;200m", 'RGB background escape sequence');
};

# ============================================================================
# Theme Construction
# ============================================================================
subtest 'Theme construction' => sub {
    my $theme = Zepto::Theme->new('test', {
        fg => "\x1b[37m",
        bg => "\x1b[40m",
    });
    ok($theme, 'Theme created');
    is($theme->name(), 'test', 'Theme name');
};

subtest 'Get color' => sub {
    my $theme = Zepto::Theme->new('test', {
        fg => "\x1b[37m",
        bg => "\x1b[40m",
    });
    is($theme->color('fg'), "\x1b[37m", 'Get fg color');
    is($theme->color('bg'), "\x1b[40m", 'Get bg color');
    is($theme->color('nonexistent'), '', 'Missing color returns empty');
};

subtest 'Style combination' => sub {
    my $theme = Zepto::Theme->new('test', {
        fg => "\x1b[37m",
        bg => "\x1b[40m",
    });
    is($theme->style('fg', 'bg'), "\x1b[37m\x1b[40m", 'Combined style');
};

subtest 'Reset' => sub {
    is(Zepto::Theme->reset(), "\x1b[0m", 'Reset sequence');
};

# ============================================================================
# Built-in Themes
# ============================================================================
subtest 'Dark theme' => sub {
    my $theme = Zepto::Theme->dark_theme();
    ok($theme, 'Dark theme created');
    is($theme->name(), 'dark', 'Theme name is dark');

    # Check essential colors exist
    ok($theme->color('fg'), 'Has fg');
    ok($theme->color('bg'), 'Has bg');
    ok($theme->color('gutter_fg'), 'Has gutter_fg');
    ok($theme->color('gutter_bg'), 'Has gutter_bg');
    ok($theme->color('selection_fg'), 'Has selection_fg');
    ok($theme->color('selection_bg'), 'Has selection_bg');
    ok($theme->color('menu_fg'), 'Has menu_fg');
    ok($theme->color('menu_bg'), 'Has menu_bg');
    ok($theme->color('status_fg'), 'Has status_fg');
    ok($theme->color('status_bg'), 'Has status_bg');
    ok($theme->color('dialog_fg'), 'Has dialog_fg');
    ok($theme->color('dialog_bg'), 'Has dialog_bg');
    ok($theme->color('match_fg'), 'Has match_fg');
    ok($theme->color('match_bg'), 'Has match_bg');
    ok($theme->color('error_fg'), 'Has error_fg');
};

subtest 'Light theme' => sub {
    my $theme = Zepto::Theme->light_theme();
    ok($theme, 'Light theme created');
    is($theme->name(), 'light', 'Theme name is light');

    # Check essential colors exist
    ok($theme->color('fg'), 'Has fg');
    ok($theme->color('bg'), 'Has bg');
    ok($theme->color('gutter_fg'), 'Has gutter_fg');
    ok($theme->color('selection_bg'), 'Has selection_bg');

    # Regression: status_accent must be a foreground color (fg_rgb -> ESC[38;2;...)
    # Bug: was set to bg_rgb() which produces ESC[48;2;...] — wrong for a text accent
    like($theme->color('status_accent'), qr/^\x1b\[38;/, 'status_accent is a foreground color');
};

subtest 'Get theme by name' => sub {
    my $dark = Zepto::Theme->get_theme('dark');
    is($dark->name(), 'dark', 'Got dark theme');

    my $light = Zepto::Theme->get_theme('light');
    is($light->name(), 'light', 'Got light theme');

    my $default = Zepto::Theme->get_theme();
    is($default->name(), 'dark', 'Default is dark');

    my $unknown = Zepto::Theme->get_theme('unknown');
    is($unknown->name(), 'dark', 'Unknown falls back to dark');
};

subtest 'Available themes' => sub {
    my @themes = Zepto::Theme->available_themes();
    is(scalar @themes, 2, 'Two themes available');
    ok(grep({ $_ eq 'dark' } @themes), 'Dark in list');
    ok(grep({ $_ eq 'light' } @themes), 'Light in list');
};

# ============================================================================
# Constants
# ============================================================================
subtest 'Constants' => sub {
    is(Zepto::Theme::RESET, "\x1b[0m", 'RESET constant');
    is(Zepto::Theme::BOLD, "\x1b[1m", 'BOLD constant');
    is(Zepto::Theme::DIM, "\x1b[2m", 'DIM constant');
    is(Zepto::Theme::ITALIC, "\x1b[3m", 'ITALIC constant');
    is(Zepto::Theme::UNDERLINE, "\x1b[4m", 'UNDERLINE constant');
    is(Zepto::Theme::REVERSE, "\x1b[7m", 'REVERSE constant');
};

done_testing();
