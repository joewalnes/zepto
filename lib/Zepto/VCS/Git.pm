package Zepto::VCS::Git;
# =============================================================================
# VCS::Git: Git version control integration
# =============================================================================
#
# Provides git-specific VCS operations:
#   - Detection: Find .git directory
#   - Content retrieval: Get file content at HEAD
#   - Tracking status: Check if file is tracked
#
# Uses the git command-line tool for operations. Gracefully handles missing git.
# =============================================================================

use strict;
use warnings;
use utf8;
use parent 'Zepto::VCS::Provider';
use File::Basename qw(dirname);
use Cwd qw(abs_path getcwd);

# Check if git is available (cached)
my $_git_available;

sub _git_available {
    return $_git_available if defined $_git_available;

    my $result = `git --version 2>/dev/null`;
    $_git_available = ($? == 0) ? 1 : 0;

    return $_git_available;
}

# Register with the provider system
Zepto::VCS::Provider->register(__PACKAGE__);

# =============================================================================
# Class Methods
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = $class->SUPER::new(%opts);
    $self->{_content_cache} = {};  # Cache for HEAD content
    $self->{_head_mtime} = $self->_get_head_mtime();  # Track HEAD changes
    return $self;
}

# Detect if a file is in a git repository
# Returns a Git provider instance if found, undef otherwise
sub detect {
    my ($class, $file_path) = @_;
    return undef unless _git_available();
    return undef unless defined $file_path;

    # Handle non-existent files (new unsaved files)
    my $search_path = -e $file_path ? $file_path : dirname($file_path);
    return undef unless -e $search_path;

    my $repo_root = $class->SUPER::_find_repo_root($search_path, '.git');
    return undef unless defined $repo_root;

    return $class->new(repo_root => $repo_root);
}

# =============================================================================
# Instance Methods
# =============================================================================

sub name { 'git' }

# Check if a file is tracked by git
sub is_tracked {
    my ($self, $file_path) = @_;
    return 0 unless defined $file_path && -e $file_path;

    my $rel_path = $self->_relative_path($file_path);
    my $repo_root = $self->{repo_root};

    # Use git ls-files to check if file is tracked
    my $cmd = "cd " . _shell_quote($repo_root) . " && git ls-files --error-unmatch " . _shell_quote($rel_path) . " 2>/dev/null";
    `$cmd`;

    return $? == 0;
}

# Get the content of a file at HEAD
sub get_head_content {
    my ($self, $file_path) = @_;
    return undef unless defined $file_path;

    my $rel_path = $self->_relative_path($file_path);

    # Check cache first
    if (exists $self->{_content_cache}{$rel_path}) {
        return $self->{_content_cache}{$rel_path};
    }

    my $repo_root = $self->{repo_root};

    # Use git show to get content at HEAD
    my $cmd = "cd " . _shell_quote($repo_root) . " && git show HEAD:" . _shell_quote($rel_path) . " 2>/dev/null";
    my $content = `$cmd`;

    if ($? != 0) {
        # File doesn't exist at HEAD (new file or not tracked)
        $self->{_content_cache}{$rel_path} = undef;
        return undef;
    }

    # Normalize line endings (git may return with original line endings)
    $content =~ s/\r\n/\n/g;

    # Strip trailing newline for consistency with Document.pm
    $content =~ s/\n$//;

    # Decode UTF-8
    utf8::decode($content);

    $self->{_content_cache}{$rel_path} = $content;
    return $content;
}

# Get the content of a file in the staging area
sub get_staged_content {
    my ($self, $file_path) = @_;
    return undef unless defined $file_path;

    my $rel_path = $self->_relative_path($file_path);
    my $repo_root = $self->{repo_root};

    # Use git show :path to get staged content
    my $cmd = "cd " . _shell_quote($repo_root) . " && git show :" . _shell_quote($rel_path) . " 2>/dev/null";
    my $content = `$cmd`;

    if ($? != 0) {
        return undef;
    }

    $content =~ s/\r\n/\n/g;
    $content =~ s/\n$//;
    utf8::decode($content);

    return $content;
}

# Invalidate cache (call after save or external changes)
sub invalidate_cache {
    my ($self, $file_path) = @_;

    if (defined $file_path) {
        my $rel_path = $self->_relative_path($file_path);
        delete $self->{_content_cache}{$rel_path};
    } else {
        $self->{_content_cache} = {};
    }
}

# =============================================================================
# Utility
# =============================================================================

# Simple shell quoting (single quotes, escape existing single quotes)
sub _shell_quote {
    my ($str) = @_;
    $str =~ s/'/'\\''/g;
    return "'$str'";
}

# Get mtime of .git/HEAD file
sub _get_head_mtime {
    my ($self) = @_;
    my $head_file = $self->{repo_root} . "/.git/HEAD";
    return (stat($head_file))[9] // 0;
}

# Check if HEAD has changed since last check
# Returns true if changed, and updates stored mtime
sub head_changed {
    my ($self) = @_;
    my $current_mtime = $self->_get_head_mtime();
    if ($current_mtime != $self->{_head_mtime}) {
        $self->{_head_mtime} = $current_mtime;
        return 1;
    }
    return 0;
}

1;
