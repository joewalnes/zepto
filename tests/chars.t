#!/usr/bin/env perl
# Tests for Zepto::Chars
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::Chars;

# =============================================================================
# Basic functionality
# =============================================================================

subtest 'Module loads' => sub {
    use_ok('Zepto::Chars');
};

subtest 'Default state is enabled' => sub {
    # Reset to default
    Zepto::Chars->enable();
    ok(Zepto::Chars->enabled(), 'Powerline is enabled by default');
};

subtest 'Enable/disable/toggle' => sub {
    Zepto::Chars->disable();
    ok(!Zepto::Chars->enabled(), 'Can disable powerline');

    Zepto::Chars->enable();
    ok(Zepto::Chars->enabled(), 'Can enable powerline');

    my $new_state = Zepto::Chars->toggle();
    ok(!$new_state, 'Toggle returns new state (off)');
    ok(!Zepto::Chars->enabled(), 'Toggle actually changes state');

    $new_state = Zepto::Chars->toggle();
    ok($new_state, 'Toggle returns new state (on)');
    ok(Zepto::Chars->enabled(), 'Toggle changes state back');
};

subtest 'set_enabled' => sub {
    Zepto::Chars->set_enabled(0);
    ok(!Zepto::Chars->enabled(), 'set_enabled(0) disables');

    Zepto::Chars->set_enabled(1);
    ok(Zepto::Chars->enabled(), 'set_enabled(1) enables');
};

# =============================================================================
# Character retrieval
# =============================================================================

subtest 'Get characters when enabled' => sub {
    Zepto::Chars->enable();

    # Powerline chars should be Unicode
    my $arrow = Zepto::Chars->get('arrow_right');
    is($arrow, "\x{e0b0}", 'arrow_right returns powerline char');

    my $round = Zepto::Chars->get('round_left');
    is($round, "\x{e0b6}", 'round_left returns powerline char');

    my $toggle = Zepto::Chars->get('toggle_on');
    is($toggle, "\x{25cf}", 'toggle_on returns filled circle');
};

subtest 'Get characters when disabled' => sub {
    Zepto::Chars->disable();

    # Should return ASCII fallbacks
    my $arrow = Zepto::Chars->get('arrow_right');
    is($arrow, '>', 'arrow_right returns ASCII when disabled');

    my $round = Zepto::Chars->get('round_left');
    is($round, ' ', 'round_left returns space when disabled');

    my $toggle = Zepto::Chars->get('toggle_on');
    is($toggle, '*', 'toggle_on returns * when disabled');

    # Re-enable for other tests
    Zepto::Chars->enable();
};

subtest 'Box drawing characters' => sub {
    Zepto::Chars->enable();

    # Rounded corners when enabled
    is(Zepto::Chars->get('box_tl'), "\x{256d}", 'box_tl is rounded when enabled');
    is(Zepto::Chars->get('box_tr'), "\x{256e}", 'box_tr is rounded when enabled');
    is(Zepto::Chars->get('box_bl'), "\x{2570}", 'box_bl is rounded when enabled');
    is(Zepto::Chars->get('box_br'), "\x{256f}", 'box_br is rounded when enabled');

    Zepto::Chars->disable();

    # Square corners when disabled
    is(Zepto::Chars->get('box_tl'), "\x{250c}", 'box_tl is square when disabled');
    is(Zepto::Chars->get('box_tr'), "\x{2510}", 'box_tr is square when disabled');
    is(Zepto::Chars->get('box_bl'), "\x{2514}", 'box_bl is square when disabled');
    is(Zepto::Chars->get('box_br'), "\x{2518}", 'box_br is square when disabled');

    Zepto::Chars->enable();
};

subtest 'Unknown character returns empty' => sub {
    my $unknown = Zepto::Chars->get('nonexistent_char');
    is($unknown, '', 'Unknown char returns empty string');
};

# =============================================================================
# Convenience accessors
# =============================================================================

subtest 'Convenience accessors' => sub {
    Zepto::Chars->enable();

    is(Zepto::Chars->round_left(), "\x{e0b6}", 'round_left accessor works');
    is(Zepto::Chars->round_right(), "\x{e0b4}", 'round_right accessor works');
    is(Zepto::Chars->arrow_left(), "\x{e0b2}", 'arrow_left accessor works');
    is(Zepto::Chars->arrow_right(), "\x{e0b0}", 'arrow_right accessor works');
    is(Zepto::Chars->menu(), "\x{f0c9}", 'menu accessor works');
};

# =============================================================================
# Helper methods
# =============================================================================

subtest 'pill helper' => sub {
    Zepto::Chars->enable();

    my $pill = Zepto::Chars->pill('Test');
    like($pill, qr/\x{e0b6}Test\x{e0b4}/, 'pill wraps content in rounded chars');

    Zepto::Chars->disable();
    $pill = Zepto::Chars->pill('Test');
    is($pill, ' Test ', 'pill uses spaces when disabled (rectangular)');

    Zepto::Chars->enable();
};

subtest 'hline helper' => sub {
    my $line = Zepto::Chars->hline(5);
    is($line, "\x{2500}" x 5, 'hline creates horizontal line');
};

subtest 'box_top helper' => sub {
    Zepto::Chars->enable();
    my $top = Zepto::Chars->box_top(10);
    like($top, qr/\x{256d}/, 'box_top starts with rounded corner');
    like($top, qr/\x{256e}/, 'box_top ends with rounded corner');
};

subtest 'box_bottom helper' => sub {
    Zepto::Chars->enable();
    my $bottom = Zepto::Chars->box_bottom(10);
    like($bottom, qr/\x{2570}/, 'box_bottom starts with rounded corner (BL)');
    like($bottom, qr/\x{256f}/, 'box_bottom ends with rounded corner (BR)');
};

done_testing();
