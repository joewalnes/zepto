#!/usr/bin/env perl
# QA-REG-193 / bugs.md P2 "ImageConverter.pm uses a predictable temp
# filename with no exclusive creation - symlink-follow risk".
#
# Before the fix, ensure_png() built its conversion output path as
# "$tmpdir/zepto-img-$$-$basename" via plain string concatenation - a
# name any local user could predict just by knowing our PID (via `ps`)
# and the image's basename, with no O_EXCL/exclusive creation. A local
# attacker who pre-planted a symlink at that exact path (pointing at,
# say, the victim's ~/.bashrc) would have that target overwritten when
# sips/convert wrote through the symlink. The fix uses File::Temp's
# tempfile() (unpredictable name, exclusive creation), matching
# Document.pm's existing atomic-save precedent.
#
# This test both confirms normal conversion still works, and directly
# reproduces the attack scenario: pre-plants a symlink at the OLD
# predictable path and confirms nothing is ever written through it.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use MIME::Base64 qw(decode_base64);
use lib 'lib';
use Zepto::ImageConverter;

Zepto::ImageConverter::_reset_converter_cache();
my $converter = Zepto::ImageConverter->detect_converter();

SKIP: {
    skip "no sips/convert image converter found on this system", 3 unless $converter;

    my $dir = tempdir(CLEANUP => 1);

    # A real, valid, minimal 16x16 baseline JPEG, base64-encoded so this
    # test doesn't depend on any external tool to produce its own fixture
    # (sips/convert themselves are what we're testing here).
    my $jpeg_b64 = <<'B64';
/9j/4AAQSkZJRgABAQAASABIAAD/4QCARXhpZgAATU0AKgAAAAgABAEaAAUAAAABAAAAPgEbAAUA
AAABAAAARgEoAAMAAAABAAIAAIdpAAQAAAABAAAATgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQAD
AAAAAQABAACgAgAEAAAAAQAAABCgAwAEAAAAAQAAABAAAAAA/+0AOFBob3Rvc2hvcCAzLjAAOEJJ
TQQEAAAAAAAAOEJJTQQlAAAAAAAQ1B2M2Y8AsgTpgAmY7PhCfv/AABEIABAAEAMBIgACEQEDEQH/
xAAfAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgv/xAC1EAACAQMDAgQDBQUEBAAAAX0BAgMA
BBEFEiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVG
R0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0
tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+fr/xAAfAQADAQEBAQEB
AQEBAAAAAAAAAQIDBAUGBwgJCgv/xAC1EQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2Fx
EyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZ
WmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TF
xsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2wBDAAICAgICAgMCAgMFAwMDBQYFBQUF
BggGBgYGBggKCAgICAgICgoKCgoKCgoMDAwMDAwODg4ODg8PDw8PDw8PDw//2wBDAQICAgQEBAcE
BAcQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/
3QAEAAH/2gAMAwEAAhEDEQA/AM+iiiv5XP7YP//Z
B64
    $jpeg_b64 =~ s/\s+//g;
    my $jpeg_bytes = decode_base64($jpeg_b64);

    my $src = "$dir/photo.jpg";
    open my $fh, '>:raw', $src or die "Cannot create $src: $!";
    print $fh $jpeg_bytes;
    close $fh;

    subtest 'ensure_png converts and returns a valid PNG' => sub {
        my $out = Zepto::ImageConverter->ensure_png($src);
        ok($out, 'conversion succeeded');
        ok($out && -f $out, 'output file exists') or return;

        open my $ofh, '<:raw', $out or die "Cannot open $out: $!";
        read($ofh, my $magic, 4);
        close $ofh;
        is($magic, "\x89PNG", 'output is a real PNG (magic bytes)');

        unlink $out;
    };

    subtest 'output path is not the old predictable "$$" pattern' => sub {
        my $pid = $$;
        my $out = Zepto::ImageConverter->ensure_png($src);
        ok($out, 'conversion succeeded') or return;

        unlike($out, qr/zepto-img-\Q$pid\E-photo\.png$/,
            'output path does not match the old predictable "$tmpdir/zepto-img-$$-basename" naming');
        like($out, qr/zepto-img-[A-Za-z0-9_]{8}\.png$/,
            'output path matches the new File::Temp-generated random-suffix naming');

        unlink $out;
    };

    subtest 'symlink pre-planted at the old predictable path is never followed' => sub {
        # Deliberately a *fresh* source file with a basename not used by
        # any earlier subtest in this file. ensure_png() caches converted
        # results per "source path + mtime" — reusing $src here would let
        # a leftover cache entry from an earlier subtest short-circuit the
        # real conversion call this subtest needs to trigger, producing a
        # false pass that never actually exercises sips/convert again.
        my $src2 = "$dir/trap_target.jpg";
        open my $sfh, '>:raw', $src2 or die "Cannot create $src2: $!";
        print $sfh $jpeg_bytes;
        close $sfh;

        my $victim = "$dir/victim_rc";
        open my $vfh, '>', $victim or die "Cannot create $victim: $!";
        print $vfh "original content\n";
        close $vfh;

        my $pid = $$;
        my $trap_path = ($ENV{TMPDIR} // '/tmp') . "/zepto-img-$pid-trap_target.png";
        unlink $trap_path;   # clear any leftover from a previous failed run

      SKIP: {
            skip "could not create symlink at $trap_path (permissions?)", 1
                unless symlink($victim, $trap_path);

            my $out = Zepto::ImageConverter->ensure_png($src2);
            unlink $out if $out && $out ne $victim && -f $out && !-l $out;

            open my $rfh, '<', $victim or die "Cannot open $victim: $!";
            local $/;
            my $content = <$rfh>;
            close $rfh;

            is($content, "original content\n",
                'victim file reachable via the old predictable symlink path was never written through');

            unlink $trap_path;
        }
    };
}

done_testing;
