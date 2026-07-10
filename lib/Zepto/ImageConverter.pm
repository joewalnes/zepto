package Zepto::ImageConverter;
# =============================================================================
# ImageConverter: Convert non-PNG images to PNG for Kitty graphics protocol
# =============================================================================
#
# The Kitty graphics protocol only defines f=100 (PNG), f=24 (RGB), and
# f=32 (RGBA). Non-PNG images must be converted before transmission.
#
# Detects available system converters:
#   - sips (macOS built-in)
#   - convert (ImageMagick)
#
# Converted files are cached in the system temp directory and cleaned up
# when cleanup() is called.
# =============================================================================

use strict;
use warnings;

{
    my $_image_converter;   # undef = not checked, '' = none found, or cmd path
    my %_png_cache;         # "path\0mtime" => converted PNG path

    # Detect available image converter: sips (macOS) or convert (ImageMagick).
    # Returns the full path to the converter, or '' if none found.
    sub detect_converter {
        return $_image_converter if defined $_image_converter;
        for my $cmd ('sips', 'convert') {
            my $found = `which $cmd 2>/dev/null`;
            chomp $found;
            if ($found && -x $found) {
                $_image_converter = $found;
                return $_image_converter;
            }
        }
        $_image_converter = '';
        return $_image_converter;
    }

    # Ensure the given image path is a PNG. If it already is, returns it as-is.
    # Otherwise, converts via sips or convert. Returns '' on failure.
    # Results are cached per source path + mtime.
    sub ensure_png {
        my ($class, $path) = @_;

        # Already PNG by extension — return as-is
        return $path if $path =~ /\.png$/i;

        # Check magic bytes: PNG starts with \x89PNG
        open my $fh, '<:raw', $path or return '';
        read($fh, my $magic, 4);
        close $fh;
        return $path if defined $magic && $magic eq "\x89PNG";

        # Check cache (invalidate if file was modified)
        my $mtime = (stat($path))[9] // 0;
        my $cache_key = "$path\0$mtime";
        if (my $cached = $_png_cache{$cache_key}) {
            return $cached if -f $cached;
        }

        # Need conversion — check for a converter
        my $converter = $class->detect_converter();
        return '' unless $converter;

        # Build output path in system temp directory
        require File::Basename;
        my $basename = File::Basename::basename($path);
        $basename =~ s/\.[^.]+$/.png/;
        my $tmpdir = $ENV{TMPDIR} // '/tmp';
        my $out = "$tmpdir/zepto-img-$$-$basename";

        my $ok;
        # Redirect stdout/stderr to suppress tool output
        open my $old_out, '>&', \*STDOUT;
        open my $old_err, '>&', \*STDERR;
        open STDOUT, '>', '/dev/null';
        open STDERR, '>', '/dev/null';
        if ($converter =~ /sips$/) {
            $ok = system($converter, '-s', 'format', 'png', $path,
                         '--out', $out) == 0;
        } else {
            # ImageMagick convert
            $ok = system($converter, $path, 'PNG:' . $out) == 0;
        }
        open STDOUT, '>&', $old_out;
        open STDERR, '>&', $old_err;
        return '' unless $ok && -f $out;

        $_png_cache{$cache_key} = $out;
        return $out;
    }

    # Clean up any converted temp files.
    sub cleanup {
        for my $png_path (values %_png_cache) {
            unlink $png_path if $png_path && -f $png_path;
        }
        %_png_cache = ();
    }
}

1;
