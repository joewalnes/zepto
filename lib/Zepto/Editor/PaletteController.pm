package Zepto::Editor::PaletteController;
# =============================================================================
# Editor Palette Handling - Command palette overlay
# =============================================================================
#
# This module defines palette-related methods for the Zepto::Editor class.
# Handles opening/closing the command palette, type-to-filter, navigation,
# and executing commands.
#
# NOTE: This file is mid-extraction (see bugs.md "Editor god-object
# extraction"). At this stage the methods below are still added to
# Zepto::Editor's own namespace (package Zepto::Editor;) -- they have only
# been relocated to this file, not yet re-namespaced as a real
# Zepto::Editor::PaletteController object. This is intentionally a pure,
# behavior-preserving move so it can be verified as a no-op before the
# riskier step of flipping the package declaration and auditing every
# $self-> field access.
# =============================================================================

use strict;
use warnings;
use utf8;

# Define methods in Zepto::Editor's namespace (see NOTE above)
package Zepto::Editor;

use File::Spec;

# =============================================================================
# Internal Helpers (self-contained / read-only — safe to relocate first)
# =============================================================================

sub _filter_recent_files {
    my ($self, $query) = @_;
    my @recent = @{$self->{_recent_files} || []};
    my $cwd = Cwd::getcwd();

    my @items;
    for my $abs_path (@recent) {
        my $display_path = $abs_path;
        if (index($abs_path, "$cwd/") == 0) {
            $display_path = substr($abs_path, length($cwd) + 1);
        }
        push @items, _build_file_item($abs_path, $display_path);
    }

    if (defined $query && length($query) > 0) {
        @items = _fuzzy_rank_file_items(\@items, $query);
    }

    return @items;
}

# Build a palette item hash for a file entry.
sub _build_file_item {
    my ($abs_path, $display_path) = @_;
    my $filename = $display_path;
    $filename =~ s{.*/}{};
    my $dir = $display_path;
    if ($dir =~ m{/}) {
        $dir =~ s{/[^/]+$}{};
    } else {
        $dir = '';
    }
    return {
        label     => $filename,
        icon      => '_file_icon',
        shortcut  => $dir,
        type      => 'action',
        _is_file  => 1,
        _path     => $abs_path,
        _filename => $filename,
        _display  => $display_path,
    };
}

# Fuzzy-score and rank file items by query, returning only matches.
sub _fuzzy_rank_file_items {
    my ($items, $query) = @_;
    my $q = lc($query);
    my @scored;
    for my $item (@$items) {
        my $score = Zepto::CommandRegistry::_fuzzy_score($q, lc($item->{_display}));
        my $name_score = Zepto::CommandRegistry::_fuzzy_score($q, lc($item->{_filename}));
        $score = $name_score if $name_score > $score;
        push @scored, { item => $item, score => $score } if $score > 0;
    }
    @scored = sort { $b->{score} <=> $a->{score} } @scored;
    return map { $_->{item} } @scored;
}

sub _filter_all_files {
    my ($self, $query) = @_;

    # Ensure file tree exists and has built its file list
    if (!$self->{file_tree}) {
        $self->{file_tree} = Zepto::FileTree->new(root_path => '.');
    }
    my $tree = $self->{file_tree};
    $tree->_build_all_files_list();

    my $all_files = $tree->{_all_files};
    my $root_path = $tree->{root_path};

    # Build lowercased file list once (cached on the tree for reuse)
    if (!$tree->{_all_files_lc} || scalar @{$tree->{_all_files_lc}} != scalar @$all_files) {
        $tree->{_all_files_lc} = [ map { lc($_) } @$all_files ];
    }
    my $all_lc = $tree->{_all_files_lc};

    # With a query, use incremental substring filtering.
    # Each keystroke filters from the previous candidate set.
    if (defined $query && length($query) > 0) {
        my $q = lc($query);
        my $prev_query = $self->{_file_filter_prev_query} // '';
        my $prev_indices = $self->{_file_filter_prev_indices};

        # Incremental: if the new query extends the previous one, filter from
        # the previous candidate set instead of the full file list.
        my @candidate_indices;
        if (length($prev_query) > 0 && index($q, $prev_query) == 0 && $prev_indices) {
            # New query starts with previous query — filter from cached subset
            for my $i (@$prev_indices) {
                push @candidate_indices, $i if index($all_lc->[$i], $q) >= 0;
            }
        } else {
            # Full scan (first char typed, or query changed non-incrementally)
            for my $i (0 .. $#$all_lc) {
                push @candidate_indices, $i if index($all_lc->[$i], $q) >= 0;
            }
        }

        # Cache for next incremental keystroke
        $self->{_file_filter_prev_query} = $q;
        $self->{_file_filter_prev_indices} = \@candidate_indices;

        # Fuzzy-score candidates for ranking (capped to keep scoring fast)
        my $max_to_score = 5000;
        my @to_score = @candidate_indices;
        splice @to_score, $max_to_score if @to_score > $max_to_score;

        my @scored;
        for my $i (@to_score) {
            my $rel_path = $all_files->[$i];
            my $filename = $rel_path;
            $filename =~ s{.*/}{};
            my $score = Zepto::CommandRegistry::_fuzzy_score($q, $all_lc->[$i]);
            my $name_score = Zepto::CommandRegistry::_fuzzy_score($q, lc($filename));
            $score = $name_score if $name_score > $score;
            push @scored, { idx => $i, path => $rel_path, filename => $filename, score => $score };
        }
        @scored = sort { $b->{score} <=> $a->{score} } @scored;

        # Cap displayed results
        splice @scored, 1000 if @scored > 1000;

        # Build palette items only for results
        my @items;
        for my $s (@scored) {
            push @items, _build_file_item(
                File::Spec->rel2abs($s->{path}, $root_path), $s->{path}
            );
        }
        return @items;
    }

    # No query: clear incremental cache, show files (capped for display)
    $self->{_file_filter_prev_query} = '';
    $self->{_file_filter_prev_indices} = undef;

    my $max_display = 10000;
    my $count = scalar @$all_files;
    $count = $max_display if $count > $max_display;

    my @items;
    for my $i (0 .. $count - 1) {
        my $rel_path = $all_files->[$i];
        push @items, _build_file_item(
            File::Spec->rel2abs($rel_path, $root_path), $rel_path
        );
    }

    return @items;
}

sub _palette_page_size {
    my ($self) = @_;
    my ($rows) = $self->{terminal}->get_size();
    my $has_footer = (($self->{palette_mode} // '') eq 'find_in_files') ? 1 : 0;
    my $max_items = $rows - 6 - $has_footer;
    $max_items = 5 if $max_items < 5;
    $max_items = 30 if $max_items > 30;
    return $max_items - 2;  # leave a couple lines of context
}

sub _palette_skip_headers {
    my ($self, $direction) = @_;
    my $filtered = $self->{palette_filtered};
    my $count = scalar @$filtered;
    return unless $count > 0;

    $direction = 1 unless defined $direction;
    my $cursor = $self->{palette_cursor};

    # Move past headers in the given direction
    while ($cursor >= 0 && $cursor < $count && $filtered->[$cursor]{_is_header}) {
        $cursor += $direction;
    }

    # If we went off the end, try the other direction
    if ($cursor < 0 || $cursor >= $count) {
        $cursor = $self->{palette_cursor};
        $direction = -$direction;
        while ($cursor >= 0 && $cursor < $count && $filtered->[$cursor]{_is_header}) {
            $cursor += $direction;
        }
    }

    $cursor = 0 if $cursor < 0;
    $cursor = $count - 1 if $cursor >= $count;
    $self->{palette_cursor} = $cursor;
}

sub _palette_ensure_visible {
    my ($self) = @_;
    my $cursor = $self->{palette_cursor};
    my $scroll = $self->{palette_scroll};

    # Visible rows in the palette (will be computed from terminal size during render,
    # but use a reasonable default for scroll management)
    my $visible = $self->{palette_visible_rows} // 15;

    if ($cursor < $scroll) {
        $self->{palette_scroll} = $cursor;
    }
    elsif ($cursor >= $scroll + $visible) {
        $self->{palette_scroll} = $cursor - $visible + 1;
    }
}

# =============================================================================
# Find in Files Helpers
# =============================================================================

sub _build_file_search_items {
    my ($self) = @_;

    my $engine = $self->{_file_search_engine};
    return () unless $engine;

    my $query = $self->{palette_widget} ? $self->{palette_widget}->value() : '';

    # If query < 2 chars, don't search
    if (length($query) < 2) {
        $engine->abort() if $engine->is_searching();
        return ();
    }

    # Check if query or search options changed — start new search
    my $case_opt  = $self->{_file_search_case}  // 0;
    my $regex_opt = $self->{_file_search_regex} // 0;
    my $needs_search = ($query ne ($engine->{query} // ''))
                    || ($case_opt  != ($engine->{case_sensitive} // 0))
                    || ($regex_opt != ($engine->{use_regex} // 0));

    if ($needs_search) {
        my $scope = $self->{_file_search_scope} // Cwd::getcwd();
        $engine->search($query, $scope,
            case_sensitive => $case_opt,
            use_regex      => $regex_opt,
        );
    }

    # Build grouped palette items: one path header per file, matches underneath
    my @items;
    my $group_idx = 0;
    my $last_path = '';

    for my $r (@{$engine->{results}}) {
        # Extract filename for icon
        my $filename = $r->{display_path};
        $filename =~ s{.*/}{};

        # Emit path header only when file changes
        if ($r->{display_path} ne $last_path) {
            $last_path = $r->{display_path};
            $group_idx++;
            push @items, {
                _is_header     => 1,
                _is_fsr_path   => 1,
                label          => $r->{display_path},
                _filename      => $filename,
                _group_idx     => $group_idx,
            };
        }

        # Content excerpt line (selectable) with line number prefix
        my $content = $r->{content} // '';
        my $match_col = $r->{match_col} // -1;
        my $match_len = $r->{match_len} // 0;

        # Truncate content centered around match
        my $excerpt = $content // '';
        my $excerpt_match_start = $match_col;
        my $content_len = length($content);
        my $context_radius = 60;
        if ($match_col >= 0 && $match_col < $content_len && $content_len > 120) {
            my $start = $match_col - $context_radius;
            $start = 0 if $start < 0;
            my $end = $match_col + $match_len + $context_radius;
            $end = $content_len if $end > $content_len;
            my $len = $end - $start;
            $len = 0 if $len < 0;
            $excerpt = substr($content, $start, $len);
            $excerpt_match_start = $match_col - $start;
            if ($start > 0) {
                $excerpt = "\x{2026}" . $excerpt;
                $excerpt_match_start += 1;  # account for prepended ellipsis
            }
        }

        # Build label with line number prefix: "42: content..."
        # (tree branch chars are prepended by Renderer)
        my $line_prefix = "$r->{line_num}: ";
        my $prefix_len = length($line_prefix);

        push @items, {
            label                  => "$line_prefix$excerpt",
            type                   => 'action',
            _is_file_search_result => 1,
            _is_fsr_content        => 1,
            _path                  => $r->{file},
            _line                  => $r->{line_num},
            _match_start           => ($excerpt_match_start >= 0 ? $excerpt_match_start + $prefix_len : -1),
            _match_len             => $match_len,
            _group_idx             => $group_idx,
        };
    }

    # Mark last content item in each group for tree rendering (╰─ vs ├─)
    my %seen_group;
    for my $i (reverse 0 .. $#items) {
        if ($items[$i]{_is_fsr_content}) {
            my $gid = $items[$i]{_group_idx} // -1;
            if (!exists $seen_group{$gid}) {
                $items[$i]{_is_last_in_group} = 1;
                $seen_group{$gid} = 1;
            }
        }
    }

    return @items;
}

1;
