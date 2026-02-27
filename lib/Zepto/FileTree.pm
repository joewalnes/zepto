package Zepto::FileTree;
# =============================================================================
# FileTree: File explorer tree data model for Zepto Editor
# =============================================================================
#
# Pure data model (no rendering, no I/O except filesystem scanning).
# Manages the tree structure, expand/collapse state, navigation,
# filtering, and VCS status propagation.
#
# =============================================================================

use strict;
use warnings;
use File::Spec;
use Zepto::Config;

# --- Constants ---

use constant {
    DEFAULT_TREE_WIDTH => 28,
    MIN_TREE_WIDTH     => 15,
    MAX_TREE_WIDTH     => 60,
    INDENT_PER_LEVEL   => 2,
    MAX_INDENT         => 16,   # clamp at 8 levels deep
    RESIZE_STEP        => 2,
    VCS_DEBOUNCE_SEC   => 1.0,
};

# =============================================================================
# Constructor
# =============================================================================

sub new {
    my ($class, %opts) = @_;

    my $root = $opts{root_path} // '.';
    $root = File::Spec->rel2abs($root);

    my $self = bless {
        root_path       => $root,
        nodes           => [],       # top-level children (dirs first, alpha)
        flat_list       => [],       # visible nodes after expand/collapse/filter
        cursor          => 0,        # index into flat_list
        scroll          => 0,
        viewport_height => $opts{viewport_height} // 20,
        panel_width     => $opts{panel_width} // DEFAULT_TREE_WIDTH,
        focused         => 0,
        filter_query    => '',
        filter_active   => 0,
        current_file    => undef,    # relative path of active tab's file
        _all_files      => [],       # flat list of all file paths for filter scoring
        _vcs_statuses   => {},       # path => status
        _vcs_last_update => 0,       # debounce timestamp

        # Preview state (managed by Editor, stored here for convenience)
        preview_active         => 0,
        preview_path           => undef,
        pre_preview_tab_index  => undef,
        _preview_is_existing_tab => 0,
    }, $class;

    $self->_build_tree();
    $self->_flatten();

    return $self;
}

# =============================================================================
# Tree Construction
# =============================================================================

sub _build_tree {
    my ($self) = @_;

    my $root = $self->{root_path};
    my %skip = Zepto::Config::skip_directories_hash();
    my $max_depth = Zepto::Config::max_depth();

    my @all_files;
    $self->{nodes} = $self->_scan_dir($root, 0, \%skip, $max_depth, \@all_files);
    $self->{_all_files} = \@all_files;
}

sub _scan_dir {
    my ($self, $dir_path, $depth, $skip, $max_depth, $all_files) = @_;

    return [] if $depth > $max_depth;

    opendir(my $dh, $dir_path) or return [];
    my @entries = sort { lc($a) cmp lc($b) } grep { $_ ne '.' && $_ ne '..' } readdir($dh);
    closedir($dh);

    my @dirs;
    my @files;

    for my $entry (@entries) {
        my $full_path = "$dir_path/$entry";
        my $rel_path = File::Spec->abs2rel($full_path, $self->{root_path});

        if (-d $full_path) {
            next if $skip->{$entry};

            my $children = $self->_scan_dir($full_path, $depth + 1, $skip, $max_depth, $all_files);
            # Skip empty directories
            next unless @$children;

            push @dirs, {
                name       => $entry,
                path       => $rel_path,
                is_dir     => 1,
                depth      => $depth,
                expanded   => 0,
                children   => $children,
                vcs_status => undef,
                collapsed_prefix => undef,
            };
        }
        elsif (-f $full_path && -r $full_path) {
            push @$all_files, $rel_path;
            push @files, {
                name       => $entry,
                path       => $rel_path,
                is_dir     => 0,
                depth      => $depth,
                vcs_status => undef,
            };
        }
    }

    # Dirs first, then files (both already alpha-sorted)
    my @result = (@dirs, @files);

    # Collapse single-child directory chains
    $self->_collapse_single_children(\@result, $depth);

    return \@result;
}

sub _collapse_single_children {
    my ($self, $nodes, $parent_depth) = @_;

    for my $node (@$nodes) {
        next unless $node->{is_dir};

        # Keep collapsing while dir has exactly one child that is also a dir
        while (@{$node->{children}} == 1 && $node->{children}[0]{is_dir}) {
            my $child = $node->{children}[0];

            # Merge: "a" with single child "b" becomes "a/b"
            my $prefix = $node->{collapsed_prefix} // $node->{name};
            $node->{name} = $prefix . '/' . $child->{name};
            $node->{collapsed_prefix} = $node->{name};
            $node->{path} = $child->{path};
            $node->{children} = $child->{children};
        }
    }
}

# =============================================================================
# Flattening (visible nodes list)
# =============================================================================

sub _flatten {
    my ($self) = @_;

    my @flat;
    $self->_flatten_nodes($self->{nodes}, 0, \@flat);
    $self->{flat_list} = \@flat;

    # Clamp cursor
    if (@flat == 0) {
        $self->{cursor} = 0;
    }
    elsif ($self->{cursor} >= @flat) {
        $self->{cursor} = $#flat;
    }
}

sub _flatten_nodes {
    my ($self, $nodes, $depth, $flat) = @_;

    for my $node (@$nodes) {
        # Store current display depth
        $node->{depth} = $depth;

        push @$flat, $node;

        if ($node->{is_dir} && $node->{expanded} && $node->{children}) {
            $self->_flatten_nodes($node->{children}, $depth + 1, $flat);
        }
    }
}

# =============================================================================
# Navigation
# =============================================================================

sub move_up {
    my ($self) = @_;
    if ($self->{cursor} > 0) {
        $self->{cursor}--;
        $self->_ensure_visible();
    }
}

sub move_down {
    my ($self) = @_;
    my $max = $#{$self->{flat_list}};
    if ($self->{cursor} < $max) {
        $self->{cursor}++;
        $self->_ensure_visible();
    }
}

sub page_up {
    my ($self, $n) = @_;
    $n //= $self->{viewport_height};
    $self->{cursor} -= $n;
    $self->{cursor} = 0 if $self->{cursor} < 0;
    $self->_ensure_visible();
}

sub page_down {
    my ($self, $n) = @_;
    $n //= $self->{viewport_height};
    my $max = $#{$self->{flat_list}};
    $self->{cursor} += $n;
    $self->{cursor} = $max if $max >= 0 && $self->{cursor} > $max;
    $self->{cursor} = 0 if $max < 0;
    $self->_ensure_visible();
}

sub home {
    my ($self) = @_;
    $self->{cursor} = 0;
    $self->_ensure_visible();
}

sub end {
    my ($self) = @_;
    my $max = $#{$self->{flat_list}};
    $self->{cursor} = $max >= 0 ? $max : 0;
    $self->_ensure_visible();
}

sub _ensure_visible {
    my ($self) = @_;
    my $vh = $self->{viewport_height};
    my $sticky_count = scalar @{$self->sticky_headers()};
    my $effective_vh = $vh - $sticky_count;
    $effective_vh = 1 if $effective_vh < 1;

    if ($self->{cursor} < $self->{scroll}) {
        $self->{scroll} = $self->{cursor};
    }
    elsif ($self->{cursor} >= $self->{scroll} + $effective_vh) {
        $self->{scroll} = $self->{cursor} - $effective_vh + 1;
    }
}

sub cursor_node {
    my ($self) = @_;
    my $flat = $self->{flat_list};
    return undef unless $self->{cursor} >= 0 && $self->{cursor} <= $#$flat;
    return $flat->[$self->{cursor}];
}

# =============================================================================
# Expand / Collapse
# =============================================================================

sub toggle_current {
    my ($self) = @_;
    my $node = $self->cursor_node();
    return unless $node && $node->{is_dir};

    $node->{expanded} = !$node->{expanded};
    $self->_flatten();
}

sub expand_current {
    my ($self) = @_;
    my $node = $self->cursor_node();
    return unless $node;

    if ($node->{is_dir}) {
        unless ($node->{expanded}) {
            $node->{expanded} = 1;
            $self->_flatten();
        }
    }
    # If file or already-expanded dir, no-op
}

sub collapse_current {
    my ($self) = @_;
    my $node = $self->cursor_node();
    return unless $node;

    if ($node->{is_dir} && $node->{expanded}) {
        $node->{expanded} = 0;
        $self->_flatten();
    }
    else {
        # Collapse parent: find parent dir in flat_list
        $self->_collapse_to_parent();
    }
}

sub _collapse_to_parent {
    my ($self) = @_;
    my $flat = $self->{flat_list};
    my $cur_depth = $flat->[$self->{cursor}]{depth};

    # Walk backwards to find first node with depth < current
    for my $i (reverse 0 .. $self->{cursor} - 1) {
        if ($flat->[$i]{is_dir} && $flat->[$i]{depth} < $cur_depth) {
            $flat->[$i]{expanded} = 0;
            $self->{cursor} = $i;
            $self->_flatten();
            $self->_ensure_visible();
            return;
        }
    }
}

sub expand_to_path {
    my ($self, $path) = @_;
    return unless defined $path;

    # Normalize: make relative to root
    if (File::Spec->file_name_is_absolute($path)) {
        $path = File::Spec->abs2rel($path, $self->{root_path});
    }

    # Split path into components to find ancestor dirs
    my @parts = split m{/}, $path;

    # Expand each ancestor directory
    my $current_nodes = $self->{nodes};
    for my $i (0 .. $#parts - 1) {
        # Build the prefix we're looking for
        my $prefix = join('/', @parts[0 .. $i]);

        for my $node (@$current_nodes) {
            next unless $node->{is_dir};

            # Check if this node matches the prefix
            # Handle collapsed dirs: node path might span multiple levels
            if ($node->{path} eq $prefix || _path_starts_with($prefix, $node->{path})) {
                $node->{expanded} = 1;
                $current_nodes = $node->{children};
                last;
            }
            # Also check if the collapsed prefix covers our path
            if (_path_starts_with($node->{path}, $prefix)) {
                $node->{expanded} = 1;
                $current_nodes = $node->{children};
                last;
            }
        }
    }

    # Reflatten with new expand state
    $self->_flatten();

    # Find the target node in flat_list and set cursor
    for my $i (0 .. $#{$self->{flat_list}}) {
        if ($self->{flat_list}[$i]{path} eq $path) {
            $self->{cursor} = $i;
            $self->_ensure_visible();
            return 1;
        }
    }

    return 0;
}

# Check if $path starts with $prefix (as path components, not string prefix)
sub _path_starts_with {
    my ($path, $prefix) = @_;
    return 0 unless defined $path && defined $prefix;
    return $path eq $prefix || index($path, "$prefix/") == 0;
}

# =============================================================================
# Refresh (re-scan filesystem, preserve expand state)
# =============================================================================

sub refresh {
    my ($self) = @_;

    # Save current expand states
    my %expanded;
    $self->_collect_expanded($self->{nodes}, \%expanded);

    # Rebuild tree
    $self->_build_tree();

    # Restore expand states
    $self->_restore_expanded($self->{nodes}, \%expanded);

    $self->_flatten();
}

sub _collect_expanded {
    my ($self, $nodes, $expanded) = @_;
    for my $node (@$nodes) {
        next unless $node->{is_dir};
        $expanded->{$node->{path}} = 1 if $node->{expanded};
        $self->_collect_expanded($node->{children}, $expanded);
    }
}

sub _restore_expanded {
    my ($self, $nodes, $expanded) = @_;
    for my $node (@$nodes) {
        next unless $node->{is_dir};
        $node->{expanded} = 1 if $expanded->{$node->{path}};
        $self->_restore_expanded($node->{children}, $expanded);
    }
}

# =============================================================================
# Fuzzy Filter
# =============================================================================

sub start_filter {
    my ($self) = @_;
    $self->{filter_active} = 1;
    $self->{filter_query} = '';
    # Don't reflatten yet — empty query shows everything
}

sub filter_append_char {
    my ($self, $char) = @_;
    return unless $self->{filter_active};
    $self->{filter_query} .= $char;
    $self->_apply_filter();
}

sub filter_backspace {
    my ($self) = @_;
    return unless $self->{filter_active};
    if (length($self->{filter_query}) > 0) {
        $self->{filter_query} = substr($self->{filter_query}, 0, -1);
        $self->_apply_filter();
    }
}

sub clear_filter {
    my ($self) = @_;
    $self->{filter_active} = 0;
    $self->{filter_query} = '';
    # Clear any filter match data from nodes
    for my $node (@{$self->{flat_list}}) {
        delete $node->{_filter_match_positions};
    }
    $self->_flatten();
    $self->{cursor} = 0;
    $self->{scroll} = 0;
}

sub _apply_filter {
    my ($self) = @_;
    my $query = $self->{filter_query};

    if (!length($query)) {
        $self->_flatten();
        return;
    }

    # Score all files
    my @matches;
    for my $file (@{$self->{_all_files}}) {
        my ($score, $positions) = $self->_fuzzy_score_with_positions($query, $file);
        if ($score >= 0) {
            push @matches, { path => $file, score => $score, positions => $positions };
        }
    }

    # Sort by score descending
    @matches = sort { $b->{score} <=> $a->{score} } @matches;

    # Build a flat list of matching files with their ancestor dirs
    my %needed_dirs;  # dir path => 1
    my %match_positions;  # file path => positions arrayref

    for my $m (@matches) {
        $match_positions{$m->{path}} = $m->{positions};

        # Collect ancestor dirs
        my @parts = split m{/}, $m->{path};
        for my $i (0 .. $#parts - 1) {
            my $dir = join('/', @parts[0 .. $i]);
            $needed_dirs{$dir} = 1;
        }
    }

    # Rebuild flat list: walk tree, include matching files + needed ancestor dirs
    my @flat;
    $self->_flatten_filtered($self->{nodes}, 0, \@flat, \%needed_dirs, \%match_positions);
    $self->{flat_list} = \@flat;

    # Store match positions on nodes for rendering
    for my $node (@flat) {
        if (!$node->{is_dir} && $match_positions{$node->{path}}) {
            $node->{_filter_match_positions} = $match_positions{$node->{path}};
        }
    }

    $self->{cursor} = 0;
    $self->{scroll} = 0;
}

sub _flatten_filtered {
    my ($self, $nodes, $depth, $flat, $needed_dirs, $match_positions) = @_;

    for my $node (@$nodes) {
        $node->{depth} = $depth;

        if ($node->{is_dir}) {
            # Include dir if it's an ancestor of a matching file
            # Check if any needed_dirs match this node's path (including collapsed paths)
            my $include = 0;
            if ($needed_dirs->{$node->{path}}) {
                $include = 1;
            }
            # Also check if this collapsed dir is a prefix of any needed dir
            for my $dir (keys %$needed_dirs) {
                if (_path_starts_with($dir, $node->{path})) {
                    $include = 1;
                    last;
                }
            }

            if ($include) {
                push @$flat, $node;
                # Always show children of needed dirs (they're expanded in filter mode)
                $self->_flatten_filtered($node->{children}, $depth + 1, $flat, $needed_dirs, $match_positions);
            }
        }
        else {
            # Include file if it matches
            push @$flat, $node if $match_positions->{$node->{path}};
        }
    }
}

# Fuzzy score with match position tracking (reuses FilePicker algorithm)
sub _fuzzy_score_with_positions {
    my ($self, $query, $path) = @_;

    return (-1, []) unless length($query);

    my $lq = lc $query;
    my $lp = lc $path;

    my $qi = 0;
    my $score = 0;
    my $consecutive = 0;
    my $last_match = -2;
    my @positions;

    for my $pi (0 .. length($lp) - 1) {
        next unless $qi < length($lq);

        my $qchar = substr($lq, $qi, 1);
        my $pchar = substr($lp, $pi, 1);

        next unless $pchar eq $qchar;

        $score += 1;

        # Consecutive character bonus
        if ($pi == $last_match + 1) {
            $consecutive++;
            $score += $consecutive * 3;
        } else {
            $consecutive = 0;
        }

        # Word boundary bonus (after / . _ -)
        if ($pi == 0 || substr($lp, $pi - 1, 1) =~ m{[/._-]}) {
            $score += 10;
        }

        push @positions, $pi;
        $last_match = $pi;
        $qi++;
    }

    # Not all query chars matched
    return (-1, []) if $qi < length($lq);

    # Filename-start bonus
    my ($fname) = $path =~ m{([^/]+)$};
    if (defined $fname && index(lc $fname, $lq) == 0) {
        $score += 15;
    }

    # Prefer shorter paths
    $score -= length($path) * 0.1;

    return ($score, \@positions);
}

# =============================================================================
# VCS Integration
# =============================================================================

sub update_vcs_statuses {
    my ($self, $vcs_provider) = @_;
    return unless $vcs_provider;

    # Debounce
    my $now = time();
    return if ($now - $self->{_vcs_last_update}) < VCS_DEBOUNCE_SEC;
    $self->{_vcs_last_update} = $now;

    my $statuses = eval { $vcs_provider->get_worktree_status() } // {};
    $self->{_vcs_statuses} = $statuses;

    # Apply statuses to tree nodes
    $self->_apply_vcs_statuses($self->{nodes});
    $self->_propagate_dir_status($self->{nodes});
}

sub _apply_vcs_statuses {
    my ($self, $nodes) = @_;
    my $statuses = $self->{_vcs_statuses};

    for my $node (@$nodes) {
        if ($node->{is_dir}) {
            $node->{vcs_status} = undef;  # will be set by propagation
            $self->_apply_vcs_statuses($node->{children});
        }
        else {
            $node->{vcs_status} = $statuses->{$node->{path}};
        }
    }
}

# Priority order for dir status: modified > added > untracked > staged > undef
my %VCS_PRIORITY = (
    modified  => 4,
    added     => 3,
    untracked => 2,
    staged    => 1,
);

sub _propagate_dir_status {
    my ($self, $nodes) = @_;

    for my $node (@$nodes) {
        next unless $node->{is_dir};

        $self->_propagate_dir_status($node->{children});

        # Find worst status among children
        my $worst_priority = 0;
        my $worst_status = undef;

        for my $child (@{$node->{children}}) {
            my $status = $child->{vcs_status};
            next unless defined $status;
            my $p = $VCS_PRIORITY{$status} // 0;
            if ($p > $worst_priority) {
                $worst_priority = $p;
                $worst_status = $status;
            }
        }

        $node->{vcs_status} = $worst_status;
    }
}

# =============================================================================
# Resize
# =============================================================================

sub set_width {
    my ($self, $w) = @_;
    $w = MIN_TREE_WIDTH if $w < MIN_TREE_WIDTH;
    $w = MAX_TREE_WIDTH if $w > MAX_TREE_WIDTH;
    $self->{panel_width} = $w;
}

sub grow {
    my ($self, $n) = @_;
    $n //= RESIZE_STEP;
    $self->set_width($self->{panel_width} + $n);
}

sub shrink {
    my ($self, $n) = @_;
    $n //= RESIZE_STEP;
    $self->set_width($self->{panel_width} - $n);
}

# =============================================================================
# Sticky Headers
# =============================================================================

sub sticky_headers {
    my ($self) = @_;

    # Use cursor node's path for computing ancestor context — this reflects
    # where the user is looking, whether the tree is focused or not
    my $node = $self->cursor_node();
    return [] unless $node;

    my $path = $node->{path};
    return [] unless defined $path;

    # Find ancestor dir nodes that are scrolled above viewport
    my @ancestors;
    my @parts = split m{/}, $path;

    # Build list of ancestor dir paths
    my @ancestor_paths;
    for my $i (0 .. $#parts - 1) {
        push @ancestor_paths, join('/', @parts[0 .. $i]);
    }

    return [] unless @ancestor_paths;

    # Find these ancestors in flat_list that are above scroll position
    my $scroll = $self->{scroll};
    for my $i (0 .. $scroll - 1) {
        last if $i > $#{$self->{flat_list}};
        my $node = $self->{flat_list}[$i];
        next unless $node->{is_dir};

        # Check if this dir is an ancestor of current_file
        for my $ap (@ancestor_paths) {
            if ($node->{path} eq $ap || _path_starts_with($ap, $node->{path})) {
                push @ancestors, $node;
                last;
            }
        }
    }

    return \@ancestors;
}

# =============================================================================
# Scrollbar
# =============================================================================

sub scrollbar_data {
    my ($self) = @_;
    my $total = scalar @{$self->{flat_list}};
    my $vh = $self->{viewport_height};
    my $sticky_count = scalar @{$self->sticky_headers()};
    my $visible = $vh - $sticky_count;
    $visible = 1 if $visible < 1;

    return { total => $total, visible => $visible, thumb_start => 0, thumb_end => 0 }
        if $total <= $visible;

    # Calculate thumb position and size
    my $thumb_size = int(($visible * $visible) / $total);
    $thumb_size = 1 if $thumb_size < 1;

    my $scroll_range = $total - $visible;
    my $track_range = $visible - $thumb_size;

    my $thumb_start = 0;
    if ($scroll_range > 0) {
        $thumb_start = int(($self->{scroll} * $track_range) / $scroll_range);
    }
    my $thumb_end = $thumb_start + $thumb_size - 1;

    return {
        total       => $total,
        visible     => $visible,
        thumb_start => $thumb_start,
        thumb_end   => $thumb_end,
    };
}

# =============================================================================
# Accessors
# =============================================================================

sub cursor          { $_[0]->{cursor} }
sub scroll          { $_[0]->{scroll} }
sub focused         { $_[0]->{focused} }
sub panel_width     { $_[0]->{panel_width} }
sub filter_query    { $_[0]->{filter_query} }
sub filter_active   { $_[0]->{filter_active} }
sub current_file    { $_[0]->{current_file} }
sub visible_count   { scalar @{$_[0]->{flat_list}} }
sub flat_list       { $_[0]->{flat_list} }
sub viewport_height { $_[0]->{viewport_height} }
sub nodes           { $_[0]->{nodes} }
sub root_path       { $_[0]->{root_path} }

sub set_focused {
    my ($self, $val) = @_;
    $self->{focused} = $val ? 1 : 0;
}

sub set_current_file {
    my ($self, $path) = @_;
    if (defined $path && File::Spec->file_name_is_absolute($path)) {
        $path = File::Spec->abs2rel($path, $self->{root_path});
    }
    $self->{current_file} = $path;
}

sub set_viewport_height {
    my ($self, $h) = @_;
    $self->{viewport_height} = $h if defined $h && $h > 0;
}

sub set_cursor {
    my ($self, $idx) = @_;
    my $max = $#{$self->{flat_list}};
    $idx = 0 if $idx < 0;
    $idx = $max if $max >= 0 && $idx > $max;
    $self->{cursor} = $idx;
    $self->_ensure_visible();
}

sub set_scroll {
    my ($self, $scroll) = @_;
    my $total = scalar @{$self->{flat_list}};
    my $sticky_count = scalar @{$self->sticky_headers()};
    my $visible = $self->{viewport_height} - $sticky_count;
    $visible = 1 if $visible < 1;

    my $max_scroll = $total - $visible;
    $max_scroll = 0 if $max_scroll < 0;

    $scroll = 0 if $scroll < 0;
    $scroll = $max_scroll if $scroll > $max_scroll;
    $self->{scroll} = $scroll;

    # Keep cursor within visible range
    if ($self->{cursor} < $scroll) {
        $self->{cursor} = $scroll;
    } elsif ($self->{cursor} >= $scroll + $visible) {
        $self->{cursor} = $scroll + $visible - 1;
    }
}

1;
