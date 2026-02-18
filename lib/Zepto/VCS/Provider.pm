package Zepto::VCS::Provider;
# =============================================================================
# VCS::Provider: Abstract base class for version control integration
# =============================================================================
#
# Provides a common interface for version control systems (Git, Mercurial, etc.)
# Subclasses implement the actual VCS-specific logic.
#
# Usage:
#   my $vcs = Zepto::VCS::Provider->detect('/path/to/file');
#   if ($vcs) {
#       my $base_content = $vcs->get_head_content('/path/to/file');
#   }
# =============================================================================

use strict;
use warnings;
use utf8;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

# Registry of available VCS providers (populated by subclasses)
my @PROVIDERS = ();

# =============================================================================
# Class Methods
# =============================================================================

# Register a provider class (called by subclasses)
sub register {
    my ($class, $provider_class) = @_;
    push @PROVIDERS, $provider_class;
}

# Detect VCS for a given file path
# Returns a provider instance if the file is in a VCS repo, undef otherwise
sub detect {
    my ($class, $file_path) = @_;
    return undef unless defined $file_path && -e $file_path;

    # Try each registered provider
    for my $provider_class (@PROVIDERS) {
        my $provider = $provider_class->detect($file_path);
        return $provider if $provider;
    }

    return undef;
}

# =============================================================================
# Instance Methods (to be overridden by subclasses)
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    return bless {
        repo_root => $opts{repo_root},
    }, $class;
}

# Get the repository root directory
sub repo_root { $_[0]->{repo_root} }

# Get the name of this VCS (e.g., "git", "hg", "svn")
sub name { die "Subclass must implement name()" }

# Check if a file is tracked by this VCS
sub is_tracked {
    my ($self, $file_path) = @_;
    die "Subclass must implement is_tracked()";
}

# Get the content of a file at HEAD (last committed version)
# Returns undef if file is not tracked or doesn't exist in HEAD
sub get_head_content {
    my ($self, $file_path) = @_;
    die "Subclass must implement get_head_content()";
}

# Get the content of a file in the staging area (index)
# Returns undef if file is not staged or VCS doesn't support staging
sub get_staged_content {
    my ($self, $file_path) = @_;
    # Default: staging not supported, return undef
    return undef;
}

# Check if HEAD has changed since last check (for cache invalidation)
# Returns true if changed, false otherwise
# Default: always returns false (subclasses override with actual check)
sub head_changed {
    return 0;
}

# Invalidate cached content (call after save or external changes)
sub invalidate_cache {
    my ($self, $file_path) = @_;
    # Default: no-op, subclasses override if they cache
}

# Convert absolute file path to repo-relative path
sub _relative_path {
    my ($self, $file_path) = @_;
    my $abs_path = abs_path($file_path);
    my $repo_root = $self->{repo_root};

    if ($abs_path =~ /^\Q$repo_root\E\/?(.*)/) {
        return $1;
    }
    return $abs_path;
}

# =============================================================================
# Utility: Walk up directory tree looking for a marker directory
# =============================================================================

sub _find_repo_root {
    my ($class, $file_path, $marker_dir) = @_;

    my $dir = -d $file_path ? $file_path : dirname(abs_path($file_path));

    # Walk up the directory tree
    my $prev_dir = '';
    while ($dir ne $prev_dir && $dir ne '/') {
        if (-d "$dir/$marker_dir") {
            return $dir;
        }
        $prev_dir = $dir;
        $dir = dirname($dir);
    }

    # Check root as well
    if (-d "/$marker_dir") {
        return '/';
    }

    return undef;
}

1;
