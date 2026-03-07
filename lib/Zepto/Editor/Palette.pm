package Zepto::Editor::Palette;
# =============================================================================
# Editor Palette Handling - Command palette overlay
# =============================================================================
#
# This module defines palette-related methods for the Zepto::Editor class.
# Handles opening/closing the command palette, type-to-filter, navigation,
# and executing commands.
# =============================================================================

use strict;
use warnings;
use utf8;

# Define methods in Zepto::Editor's namespace
package Zepto::Editor;

use Cwd qw(getcwd);
use File::Basename ();
use File::Spec;
use Zepto::CommandRegistry;
use Zepto::InputWidget;

# =============================================================================
# Palette State
# =============================================================================

sub cmd_open_palette {
    my ($self) = @_;

    # Don't open palette during input-focused states
    return if $self->{state} eq 'footer_input';
    return if $self->{state} eq 'prompt';
    return if $self->{state} eq 'find';
    return if $self->{state} eq 'dialog';

    $self->{state} = 'palette';
    $self->{palette_mode} = 'commands';
    $self->{palette_widget} = Zepto::InputWidget->new();
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->_palette_update_filtered();
}

sub close_palette {
    my ($self) = @_;

    # Persist find_in_files state for re-opening
    if (($self->{palette_mode} // '') eq 'find_in_files' && $self->{palette_widget}) {
        $self->{_file_search_saved_widget} = $self->{palette_widget};
        $self->{_file_search_saved_cursor} = $self->{palette_cursor};
        $self->{_file_search_saved_scroll} = $self->{palette_scroll};
    }

    # Abort file search engine if running
    if ($self->{_file_search_engine} && $self->{_file_search_engine}->is_searching()) {
        $self->{_file_search_engine}->abort();
    }

    $self->{state} = 'editing';
    $self->{palette_mode} = 'commands';
    $self->{palette_widget} = undef;
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->{palette_filtered} = [];
}

# =============================================================================
# Palette Event Handling
# =============================================================================

sub handle_palette_event {
    my ($self, $event) = @_;

    my $type   = $event->{type};
    my $widget = $self->{palette_widget};

    if ($type eq 'key') {
        my $key = $event->{key};

        if ($key eq 'escape') {
            $self->close_palette();
        }
        elsif ($key eq 'enter') {
            $self->_palette_execute_selected();
        }
        elsif ($key eq 'up') {
            $self->_palette_move_cursor(-1);
        }
        elsif ($key eq 'down') {
            $self->_palette_move_cursor(1);
        }
        elsif ($key eq 'pageup') {
            my $page = $self->_palette_page_size();
            $self->_palette_move_cursor(-$page);
        }
        elsif ($key eq 'pagedown') {
            my $page = $self->_palette_page_size();
            $self->_palette_move_cursor($page);
        }
        elsif ($key eq 'home') {
            $self->{palette_cursor} = 0;
            $self->{palette_scroll} = 0;
            $self->_palette_skip_headers(1);
        }
        elsif ($key eq 'end') {
            my $count = scalar @{$self->{palette_filtered}};
            $self->{palette_cursor} = $count > 0 ? $count - 1 : 0;
            $self->_palette_skip_headers(-1);
            $self->_palette_ensure_visible();
        }
        elsif ($key eq 'tab' && ($self->{palette_mode} // '') eq 'find_in_files') {
            $self->_file_search_cycle_scope();
        }
        elsif ($key eq 'shift_tab' && ($self->{palette_mode} // '') eq 'find_in_files') {
            $self->_file_search_cycle_scope();
        }
        else {
            # Delegate cursor/editing keys to widget
            my $old_query = $widget->value();
            $widget->handle_event($event, \$self->{clipboard});
            if ($widget->value() ne $old_query) {
                $self->{palette_cursor} = 0;
                $self->{palette_scroll} = 0;
                $self->_palette_update_filtered();
            }
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');
        my $alt  = Zepto::InputParser::has_modifier($event, 'alt');

        if ($ctrl) {
            # Find in Files toggles: Ctrl+R (regex) and Ctrl+C (case)
            if (($self->{palette_mode} // '') eq 'find_in_files') {
                if (lc($char) eq 'r') {
                    $self->_file_search_toggle_regex();
                    return;
                }
                elsif (lc($char) eq 'c') {
                    $self->_file_search_toggle_case();
                    return;
                }
            }

            # Check if ctrl+char matches a command shortcut — execute directly
            my $matched = $self->_palette_try_shortcut('ctrl', $char);
            return if $matched;

            # Ctrl+Space while palette is open closes it
            if ($char eq ' ') {
                $self->close_palette();
                return;
            }

            # Delegate Ctrl+A / other editing to widget
            my $old_query = $widget->value();
            $widget->handle_event($event);
            if ($widget->value() ne $old_query) {
                $self->{palette_cursor} = 0;
                $self->{palette_scroll} = 0;
                $self->_palette_update_filtered();
            }
        }
        elsif ($alt) {
            # Check if alt+char matches a command shortcut
            my $matched = $self->_palette_try_shortcut('alt', $char);
            return if $matched;
        }
        else {
            # Printable character — append to query via widget
            my $old_query = $widget->value();
            $widget->handle_event($event);
            if ($widget->value() ne $old_query) {
                $self->{palette_cursor} = 0;
                $self->{palette_scroll} = 0;
                $self->_palette_update_filtered();
            }
        }
    }
    elsif ($type eq 'mouse') {
        $self->_handle_palette_mouse($event);
    }
}

# =============================================================================
# Internal Helpers
# =============================================================================

sub _palette_update_filtered {
    my ($self) = @_;
    my $query = $self->{palette_widget} ? $self->{palette_widget}->value() : '';

    my @filtered;

    if (($self->{palette_mode} // 'commands') eq 'recent_files') {
        @filtered = $self->_filter_recent_files($query);
    } elsif (($self->{palette_mode} // 'commands') eq 'files') {
        @filtered = $self->_filter_all_files($query);
    } elsif (($self->{palette_mode} // 'commands') eq 'find_in_files') {
        @filtered = $self->_build_file_search_items();
    } else {
        @filtered = Zepto::CommandRegistry->filter_commands($query);

        # When no query, insert section headers before each group
        if (length($query) == 0) {
            my @with_headers;
            my $current_section = '';
            for my $cmd (@filtered) {
                if (($cmd->{section} // '') ne $current_section) {
                    $current_section = $cmd->{section};
                    push @with_headers, { _is_header => 1, label => $current_section };
                }
                push @with_headers, $cmd;
            }
            @filtered = @with_headers;
        }
    }

    $self->{palette_filtered} = \@filtered;

    # Clamp cursor to valid range
    my $max = scalar(@filtered) - 1;
    $max = 0 if $max < 0;
    $self->{palette_cursor} = $max if $self->{palette_cursor} > $max;

    # Ensure cursor is not on a section header
    $self->_palette_skip_headers(1);
}

sub _filter_recent_files {
    my ($self, $query) = @_;
    my @recent = @{$self->{_recent_files} || []};
    my $cwd = Cwd::getcwd();

    my @items;
    for my $abs_path (@recent) {
        # Compute display path (relative to cwd if possible)
        my $display_path = $abs_path;
        if (index($abs_path, "$cwd/") == 0) {
            $display_path = substr($abs_path, length($cwd) + 1);
        }

        # Extract filename for label
        my $filename = $display_path;
        $filename =~ s{.*/}{};

        # Compute directory for shortcut display
        my $dir = $display_path;
        if ($dir =~ m{/}) {
            $dir =~ s{/[^/]+$}{};
        } else {
            $dir = '';
        }

        push @items, {
            label     => $filename,
            icon      => '_file_icon',  # special: use file_icon() method
            shortcut  => $dir,
            type      => 'action',
            _is_file  => 1,
            _path     => $abs_path,
            _filename => $filename,
            _display  => $display_path,
        };
    }

    # Filter by query if provided
    if (defined $query && length($query) > 0) {
        my $q = lc($query);
        my @scored;
        for my $item (@items) {
            # Match against full display path
            my $score = Zepto::CommandRegistry::_fuzzy_score($q, lc($item->{_display}));
            # Also try matching against just the filename
            my $name_score = Zepto::CommandRegistry::_fuzzy_score($q, lc($item->{_filename}));
            $score = $name_score if $name_score > $score;
            push @scored, { item => $item, score => $score } if $score > 0;
        }
        @scored = sort { $b->{score} <=> $a->{score} } @scored;
        @items = map { $_->{item} } @scored;
    }

    return @items;
}

sub _filter_all_files {
    my ($self, $query) = @_;

    # Ensure file tree exists and has built its file list
    if (!$self->{file_tree}) {
        $self->{file_tree} = Zepto::FileTree->new(root_path => '.');
    }
    my $tree = $self->{file_tree};
    $tree->_build_all_files_list();

    my @items;
    for my $rel_path (@{$tree->{_all_files}}) {
        # Extract filename
        my $filename = $rel_path;
        $filename =~ s{.*/}{};

        # Compute directory portion for shortcut display
        my $dir = $rel_path;
        if ($dir =~ m{/}) {
            $dir =~ s{/[^/]+$}{};
        } else {
            $dir = '';
        }

        # Absolute path for opening
        my $abs_path = File::Spec->rel2abs($rel_path, $tree->{root_path});

        push @items, {
            label     => $filename,
            icon      => '_file_icon',
            shortcut  => $dir,
            type      => 'action',
            _is_file  => 1,
            _path     => $abs_path,
            _filename => $filename,
            _display  => $rel_path,
        };
    }

    # Filter by query if provided
    if (defined $query && length($query) > 0) {
        my $q = lc($query);
        my @scored;
        for my $item (@items) {
            my $score = Zepto::CommandRegistry::_fuzzy_score($q, lc($item->{_display}));
            my $name_score = Zepto::CommandRegistry::_fuzzy_score($q, lc($item->{_filename}));
            $score = $name_score if $name_score > $score;
            push @scored, { item => $item, score => $score } if $score > 0;
        }
        @scored = sort { $b->{score} <=> $a->{score} } @scored;
        @items = map { $_->{item} } @scored;
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

sub _palette_move_cursor {
    my ($self, $delta) = @_;
    my $count = scalar @{$self->{palette_filtered}};
    return unless $count > 0;

    my $new_pos = $self->{palette_cursor} + $delta;
    $new_pos = 0 if $new_pos < 0;
    $new_pos = $count - 1 if $new_pos >= $count;
    $self->{palette_cursor} = $new_pos;

    # Skip section headers in the direction of movement
    $self->_palette_skip_headers($delta > 0 ? 1 : -1);

    # Ensure cursor is visible within scroll window
    $self->_palette_ensure_visible();
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

sub _palette_execute_selected {
    my ($self) = @_;

    my $filtered = $self->{palette_filtered};
    return unless @$filtered;

    my $cmd = $filtered->[$self->{palette_cursor}];
    return unless $cmd;
    return if $cmd->{_is_header};  # Section headers are not executable

    # File search result: open file at specific line
    if ($cmd->{_is_file_search_result}) {
        my $path = $cmd->{_path};
        my $line = $cmd->{_line};
        # Normalize to absolute path for reliable tab matching
        $path = File::Spec->rel2abs($path) if defined $path && $path ne '';
        $self->close_palette();
        $self->_record_location();
        $self->_jump_to_location({
            file => $path,
            line => ($line > 0 ? $line - 1 : 0),  # Convert 1-indexed to 0-indexed
            col  => 0,
        });
        return;
    }

    # Recent file entry: open the file
    if ($cmd->{_is_file}) {
        my $path = $cmd->{_path};
        $self->close_palette();
        $self->_load_file($path);
        return;
    }

    if ($cmd->{type} eq 'toggle') {
        # Toggle commands: execute and stay open (update state live)
        Zepto::CommandRegistry->execute($self, $cmd->{id});
        # Re-filter to update toggle state display
        $self->_palette_update_filtered();
    }
    else {
        # Action commands: execute and close
        $self->close_palette();
        Zepto::CommandRegistry->execute($self, $cmd->{id});
    }
}

sub _palette_try_shortcut {
    my ($self, $modifier, $char) = @_;
    $char = lc($char);

    my @all = Zepto::CommandRegistry->all_commands();
    for my $cmd (@all) {
        my $shortcut = $cmd->{shortcut} // '';
        my $expected;
        if ($modifier eq 'ctrl') {
            $expected = Zepto::CommandRegistry::SYM_CTRL . uc($char);
        } elsif ($modifier eq 'alt') {
            $expected = Zepto::CommandRegistry::SYM_ALT . uc($char);
        } else {
            next;
        }

        # Check if expected matches any shortcut alternative (split on /)
        my $matched = 0;
        for my $alt (split m{/}, $shortcut) {
            if ($alt eq $expected) {
                $matched = 1;
                last;
            }
        }
        next unless $matched;

        # If this command would open the same palette mode, toggle-close
        my %cmd_to_mode = (
            open_palette  => 'commands',
            recent_files  => 'recent_files',
            open_file     => 'files',
            find_in_files => 'find_in_files',
        );
        my $target_mode = $cmd_to_mode{$cmd->{id}};
        if ($target_mode && ($self->{palette_mode} // 'commands') eq $target_mode) {
            $self->close_palette();
            return 1;
        }

        if ($cmd->{type} eq 'toggle') {
            Zepto::CommandRegistry->execute($self, $cmd->{id});
            $self->_palette_update_filtered();
        } else {
            $self->close_palette();
            Zepto::CommandRegistry->execute($self, $cmd->{id});
        }
        return 1;
    }
    return 0;
}

sub _handle_palette_mouse {
    my ($self, $event) = @_;

    my $action = $event->{action};

    if ($action eq 'press') {
        my $x = $event->{x};
        my $y = $event->{y};

        # Check if click is on the filter input row
        my $geo = Zepto::Renderer::get_palette_geometry();
        if ($geo && defined($geo->{filter_row}) && $y == $geo->{filter_row}
            && $x >= $geo->{filter_x_start}
            && $x < $geo->{filter_x_start} + $geo->{filter_input_width}) {
            my $char_offset = $x - $geo->{filter_x_start};
            $self->{palette_widget}->handle_mouse_click($char_offset);
            return;
        }

        # Check if click is on a command item row or footer pill
        my @buttons = Zepto::Renderer::get_palette_buttons();
        for my $btn (@buttons) {
            if ($y == $btn->{y} && $x >= $btn->{x_start} && $x <= $btn->{x_end}) {
                # Footer pill actions (find_in_files)
                if ($btn->{_action}) {
                    if ($btn->{_action} eq 'toggle_regex') {
                        $self->_file_search_toggle_regex();
                    } elsif ($btn->{_action} eq 'toggle_case') {
                        $self->_file_search_toggle_case();
                    } elsif ($btn->{_action} eq 'cycle_scope') {
                        $self->_file_search_cycle_scope();
                    }
                    return;
                }
                # Regular item click
                my $idx = $btn->{index};
                $self->{palette_cursor} = $idx;
                $self->_palette_execute_selected();
                return;
            }
        }

        # Click outside palette → close
        $self->close_palette();
    }
    elsif ($action eq 'scroll_up') {
        $self->_palette_move_cursor(-3);
    }
    elsif ($action eq 'scroll_down') {
        $self->_palette_move_cursor(3);
    }
}

# =============================================================================
# Status Bar Click Handling
# =============================================================================

sub handle_status_bar_click {
    my ($self, $x) = @_;

    my @buttons = Zepto::Renderer::get_status_buttons();
    for my $btn (@buttons) {
        if ($x >= $btn->{x_start} && $x <= $btn->{x_end}) {
            my $cmd_id = $btn->{command_id};
            if ($cmd_id eq 'open_palette') {
                $self->cmd_open_palette();
            } else {
                Zepto::CommandRegistry->execute($self, $cmd_id);
            }
            return;
        }
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

sub _file_search_cycle_scope {
    my ($self) = @_;

    my $cwd = Cwd::getcwd();
    my $current_label = $self->{_file_search_scope_label} // 'project';

    if ($current_label eq 'project') {
        # Switch to current file's directory
        my $file_path = $self->active_file_path();
        if ($file_path) {
            my $dir = File::Basename::dirname($file_path);
            if (-d $dir) {
                $self->{_file_search_scope} = $dir;
                # Compute display label relative to cwd
                my $display = $dir;
                if (index($dir, "$cwd/") == 0) {
                    $display = substr($dir, length($cwd) + 1);
                }
                $self->{_file_search_scope_label} = $display;
            } else {
                # Fall back to project
                $self->{_file_search_scope} = $cwd;
                $self->{_file_search_scope_label} = 'project';
            }
        } else {
            # No active file, stay on project
            return;
        }
    } else {
        # Switch back to project
        $self->{_file_search_scope} = $cwd;
        $self->{_file_search_scope_label} = 'project';
    }

    # Re-trigger search with new scope
    $self->_file_search_re_search();
}

sub _file_search_toggle_regex {
    my ($self) = @_;
    $self->{_file_search_regex} = !($self->{_file_search_regex} // 0);
    $self->_file_search_re_search();
}

sub _file_search_toggle_case {
    my ($self) = @_;
    $self->{_file_search_case} = !($self->{_file_search_case} // 0);
    $self->_file_search_re_search();
}

sub _file_search_re_search {
    my ($self) = @_;

    my $engine = $self->{_file_search_engine};
    if ($engine) {
        my $query = $self->{palette_widget} ? $self->{palette_widget}->value() : '';
        if (length($query) >= 2) {
            $engine->search($query, $self->{_file_search_scope} // Cwd::getcwd(),
                case_sensitive => $self->{_file_search_case} // 0,
                use_regex      => $self->{_file_search_regex} // 0,
            );
        }
    }

    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->_palette_update_filtered();
}

1;
