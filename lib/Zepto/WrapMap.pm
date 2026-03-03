package Zepto::WrapMap;
# =============================================================================
# WrapMap: Word wrap computation for the editor viewport
# =============================================================================
#
# Maps document lines to visual (screen) rows when word wrap is enabled.
# One long document line may occupy multiple visual rows.
#
# This is conceptually similar to LineMap (for inline diff expansion)
# but operates on a per-character basis within each line.
#
# Key concepts:
#   - "segment": a slice of a document line that fits on one screen row
#   - "visual row": a screen row in the wrapped view (0-indexed from document start)
#   - A document line with N segments occupies N consecutive visual rows
#
# All data is lazily computed and cached. Call invalidate() when the
# document content or viewport width changes.
# =============================================================================

use strict;
use warnings;
use utf8;

use Zepto::Renderer;

# Minimum content columns before we disable hanging indent
use constant MIN_CONTENT_COLS => 4;

sub new {
    my ($class, %opts) = @_;

    return bless {
        document  => $opts{document},
        width     => $opts{width} // 80,
        tab_width => $opts{tab_width} // 4,

        # Cached data (rebuilt lazily)
        _segments    => {},    # doc_line => [segment, ...]
        _visual_rows => [],    # [segment, ...] indexed by visual row
        _doc_to_vrow => {},    # doc_line => first visual row index
        _total       => 0,     # total visual row count
        _dirty       => 1,
        _last_content_version => -1,  # Track document changes

        # Content-keyed wrap cache: content_string => [segment_templates]
        # Survives full rebuilds so unchanged lines skip wrap_line()
        _wrap_cache    => {},
        _cached_width  => 0,
    }, $class;
}

# Mark cache as stale (call on any document change or resize)
sub invalidate {
    my ($self) = @_;
    $self->{_dirty} = 1;
}

# Incrementally re-wrap a single changed line without full rebuild.
# Use for single-char insert/delete that doesn't change line count.
# Falls back to lazy full rebuild if map is stale or unbuilt.
sub invalidate_line {
    my ($self, $line_idx) = @_;

    my $doc = $self->{document};
    return unless $doc;

    # If never built or already dirty, skip — full rebuild will happen lazily
    return if $self->{_dirty};

    # If version drift > 1, multiple edits happened without us seeing them;
    # incremental update would be incorrect, so fall back to full rebuild
    my $current_version = $doc->content_version();
    if ($current_version - $self->{_last_content_version} > 1) {
        $self->{_dirty} = 1;
        return;
    }

    my $content = $doc->get_line_content($line_idx);
    my $new_segs = $self->wrap_line($content, $self->{width});

    # Stamp doc_line onto each new segment
    for my $seg (@$new_segs) {
        $seg->{doc_line} = $line_idx;
    }

    # Get old segments and compute delta
    my $old_segs = $self->{_segments}{$line_idx} // [];
    my $old_count = scalar @$old_segs;
    my $new_count = scalar @$new_segs;
    my $delta = $new_count - $old_count;

    # Replace in _segments hash
    $self->{_segments}{$line_idx} = $new_segs;

    # Splice _visual_rows: remove old segments, insert new ones
    my $vrow_start = $self->{_doc_to_vrow}{$line_idx} // 0;
    splice(@{$self->{_visual_rows}}, $vrow_start, $old_count, @$new_segs);

    # Update total visual row count
    $self->{_total} += $delta;

    # Adjust _doc_to_vrow for all subsequent lines
    if ($delta != 0) {
        my $line_count = $doc->line_count();
        for my $l ($line_idx + 1 .. $line_count - 1) {
            $self->{_doc_to_vrow}{$l} += $delta
                if exists $self->{_doc_to_vrow}{$l};
        }
    }

    # Sync version so _ensure_built() won't trigger a full rebuild
    $self->{_last_content_version} = $current_version;
}

# Rebuild the full map if dirty or document content has changed.
# Uses a content-keyed cache to skip wrap_line() for unchanged lines,
# making undo/redo rebuilds nearly as fast as incremental updates.
sub _ensure_built {
    my ($self) = @_;

    # Auto-detect content changes via Document's version counter
    my $doc = $self->{document};
    if ($doc && $doc->content_version() != $self->{_last_content_version}) {
        $self->{_dirty} = 1;
        $self->{_last_content_version} = $doc->content_version();
    }

    return unless $self->{_dirty};

    my $width = $self->{width};

    # Wrap cache: reuse previous wrap_line() results for lines whose content
    # hasn't changed.  Keyed by content string.  Invalidate on width change.
    my $prev_cache = ($self->{_cached_width} == $width)
                   ? $self->{_wrap_cache}
                   : {};

    $self->{_segments} = {};
    $self->{_visual_rows} = [];
    $self->{_doc_to_vrow} = {};

    my $line_count = $doc ? $doc->line_count() : 0;
    my $vrow = 0;
    my %new_cache;

    for my $line_idx (0 .. $line_count - 1) {
        my $content = $doc->get_line_content($line_idx);
        my $segs;

        if (exists $prev_cache->{$content}) {
            # Cache hit — clone segments with correct doc_line
            $segs = [map { {%$_, doc_line => $line_idx} } @{$prev_cache->{$content}}];
        } else {
            # Cache miss — compute wrapping
            $segs = $self->wrap_line($content, $width);
            for my $seg (@$segs) {
                $seg->{doc_line} = $line_idx;
            }
        }

        # Store in new cache (first occurrence of each content wins)
        $new_cache{$content} //= $segs;

        $self->{_segments}{$line_idx} = $segs;
        $self->{_doc_to_vrow}{$line_idx} = $vrow;

        for my $seg (@$segs) {
            push @{$self->{_visual_rows}}, $seg;
            $vrow++;
        }
    }

    $self->{_wrap_cache} = \%new_cache;
    $self->{_cached_width} = $width;
    $self->{_total} = $vrow;
    $self->{_dirty} = 0;
}

# =============================================================================
# Core wrapping algorithm
# =============================================================================

# Wrap a single line's content into segments that each fit within $width columns.
# Returns arrayref of segment hashrefs.
sub wrap_line {
    my ($self, $line_content, $width) = @_;
    $line_content //= '';
    $width //= $self->{width};

    # Expand tabs to get visual column mapping
    my ($expanded, $char_to_visual) = Zepto::Renderer::_expand_tabs($line_content);
    my $expanded_len = length($expanded);
    my $char_len = length($line_content);

    # Single segment if line fits
    if ($expanded_len <= $width) {
        return [{
            doc_line     => undef,
            wrap_index   => 0,
            col_start    => 0,
            col_end      => $char_len,
            vis_start    => 0,
            vis_end      => $expanded_len,
            indent_width => 0,
        }];
    }

    # Compute hanging indent from leading whitespace
    my $indent_width = 0;
    if ($line_content =~ /^(\s+)/) {
        $indent_width = Zepto::Renderer::_char_to_visual_col($line_content, length($1));
    }
    # Clamp: if indent is too large, disable it
    if ($indent_width > $width - MIN_CONTENT_COLS) {
        $indent_width = 0;
    }

    my @segments;
    my $char_pos = 0;
    my $wrap_idx = 0;

    while ($char_pos < $char_len) {
        my $effective_width = ($wrap_idx == 0) ? $width : ($width - $indent_width);
        $effective_width = MIN_CONTENT_COLS if $effective_width < MIN_CONTENT_COLS;
        my $segment_indent = ($wrap_idx == 0) ? 0 : $indent_width;

        my $seg_char_start = $char_pos;
        my $seg_vis_start = ($char_pos < scalar @$char_to_visual)
            ? $char_to_visual->[$char_pos]
            : $expanded_len;

        # Find how many characters fit in effective_width visual columns
        my $seg_char_end = $char_pos;
        my $seg_vis_end = $seg_vis_start;
        my $last_break_char = undef;

        while ($seg_char_end < $char_len) {
            my $next_vis = ($seg_char_end + 1 < scalar @$char_to_visual)
                ? $char_to_visual->[$seg_char_end + 1]
                : $expanded_len;

            # Would adding this character exceed the width?
            if ($next_vis - $seg_vis_start > $effective_width) {
                last;
            }

            my $ch = substr($line_content, $seg_char_end, 1);

            # Track word-break points: break AFTER spaces and certain punctuation
            if ($ch =~ /[\s\-\/\.\,\;\:\!\?\)\]\}]/) {
                $last_break_char = $seg_char_end + 1;
            }

            $seg_char_end++;
            $seg_vis_end = $next_vis;
        }

        # If we haven't reached the end and found a word break point, use it
        if ($seg_char_end < $char_len && defined $last_break_char && $last_break_char > $seg_char_start) {
            # Only use word break if it's at least 25% into the segment
            my $seg_len = $seg_char_end - $seg_char_start;
            if ($seg_len == 0 || ($last_break_char - $seg_char_start) >= $seg_len * 0.25) {
                $seg_char_end = $last_break_char;
                $seg_vis_end = ($seg_char_end < scalar @$char_to_visual)
                    ? $char_to_visual->[$seg_char_end]
                    : $expanded_len;
            }
        }

        # Ensure progress: at minimum advance by 1 character
        if ($seg_char_end == $seg_char_start && $seg_char_end < $char_len) {
            $seg_char_end++;
            $seg_vis_end = ($seg_char_end < scalar @$char_to_visual)
                ? $char_to_visual->[$seg_char_end]
                : $expanded_len;
        }

        push @segments, {
            doc_line     => undef,  # Set by caller
            wrap_index   => $wrap_idx,
            col_start    => $seg_char_start,
            col_end      => $seg_char_end,
            vis_start    => $seg_vis_start,
            vis_end      => $seg_vis_end,
            indent_width => $segment_indent,
        };

        $char_pos = $seg_char_end;
        $wrap_idx++;
    }

    return \@segments;
}

# =============================================================================
# Query methods (all trigger lazy rebuild)
# =============================================================================

sub segments_for_line {
    my ($self, $doc_line) = @_;
    $self->_ensure_built();
    return $self->{_segments}{$doc_line} // [];
}

sub visual_rows_for_line {
    my ($self, $doc_line) = @_;
    $self->_ensure_built();
    my $segs = $self->{_segments}{$doc_line};
    return $segs ? scalar @$segs : 1;
}

sub doc_line_to_visual_row {
    my ($self, $doc_line) = @_;
    $self->_ensure_built();
    return $self->{_doc_to_vrow}{$doc_line} // 0;
}

sub segment_at_visual_row {
    my ($self, $vrow) = @_;
    $self->_ensure_built();
    return undef if $vrow < 0 || $vrow >= $self->{_total};
    return $self->{_visual_rows}[$vrow];
}

sub total_visual_rows {
    my ($self) = @_;
    $self->_ensure_built();
    return $self->{_total};
}

# =============================================================================
# Coordinate conversion
# =============================================================================

# Convert document (line, col) to (visual_row, visual_col_within_row)
# Optional $affinity: 'left' keeps cursor at end of current segment when at boundary,
# 'right' (default) maps boundary positions to start of next segment.
sub doc_to_visual {
    my ($self, $doc_line, $doc_col, $affinity) = @_;
    $affinity //= 'right';
    $self->_ensure_built();

    my $segs = $self->{_segments}{$doc_line};
    unless ($segs && @$segs) {
        # Line not in map (shouldn't happen if built correctly)
        my $vrow = $self->{_doc_to_vrow}{$doc_line} // 0;
        return ($vrow, 0);
    }

    my $base_vrow = $self->{_doc_to_vrow}{$doc_line} // 0;

    # Find which segment contains doc_col
    for my $i (0 .. $#$segs) {
        my $seg = $segs->[$i];
        # With 'left' affinity, col_end belongs to this segment (cursor stays on current row)
        # With 'right' affinity (default), col_end falls through to next segment
        my $matches = ($doc_col < $seg->{col_end})
                   || ($affinity eq 'left' && $doc_col == $seg->{col_end} && $i < $#$segs)
                   || ($i == $#$segs);
        if ($matches) {
            # Clamp doc_col to this segment's range
            my $clamped_col = $doc_col;
            $clamped_col = $seg->{col_start} if $clamped_col < $seg->{col_start};
            $clamped_col = $seg->{col_end} if $clamped_col > $seg->{col_end};

            # Get the line content for visual col computation
            my $content = $self->{document}->get_line_content($doc_line);
            my $vis_col_abs = Zepto::Renderer::_char_to_visual_col($content, $clamped_col);
            my $vis_col_in_row = ($vis_col_abs - $seg->{vis_start}) + $seg->{indent_width};

            return ($base_vrow + $i, $vis_col_in_row);
        }
    }

    # Fallback (shouldn't reach here)
    return ($base_vrow, 0);
}

# Convert (visual_row, visual_col_within_row) to document (line, col)
sub visual_to_doc {
    my ($self, $vrow, $vcol) = @_;
    $self->_ensure_built();

    my $seg = $self->segment_at_visual_row($vrow);
    unless ($seg) {
        # Beyond document — return last valid position
        my $doc = $self->{document};
        if ($doc && $doc->line_count() > 0) {
            my $last = $doc->line_count() - 1;
            return ($last, $doc->line_length($last));
        }
        return (0, 0);
    }

    my $doc_line = $seg->{doc_line};
    my $content = $self->{document}->get_line_content($doc_line);

    # Subtract hanging indent to get visual offset into the actual content
    my $content_vcol = $vcol - $seg->{indent_width};
    $content_vcol = 0 if $content_vcol < 0;

    # Convert to absolute visual column in the full line
    my $abs_vis_col = $seg->{vis_start} + $content_vcol;

    # Convert visual column to character position
    my $doc_col = Zepto::Renderer::visual_to_char_col($content, $abs_vis_col);

    # Clamp to segment range
    $doc_col = $seg->{col_start} if $doc_col < $seg->{col_start};
    $doc_col = $seg->{col_end} if $doc_col > $seg->{col_end};

    # Also clamp to line length
    my $line_len = $self->{document}->line_length($doc_line);
    $doc_col = $line_len if $doc_col > $line_len;

    return ($doc_line, $doc_col);
}

1;
