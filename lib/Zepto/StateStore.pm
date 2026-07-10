package Zepto::StateStore;
# =============================================================================
# StateStore: Persistent state with atomic writes and cross-instance sync
# =============================================================================
#
# Stores editor state (preferences, history, secrets) as JSON files in
# ~/.config/zepto/ (or $XDG_CONFIG_HOME/zepto/). Features:
#
#   - Atomic writes: temp file + rename, never corrupts
#   - Concurrent access: flock for read-modify-write coordination
#   - Cross-instance sync: mtime polling detects external changes
#   - Merge semantics: put() merges with on-disk state, caller keys win
#
# Categories:
#   - preferences: theme, word_wrap, etc. (user would sync across machines)
#   - history: recent files, find history, etc. (accumulated state)
#   - secrets: API keys, etc. (mode 0600)
# =============================================================================

use strict;
use warnings;
use Fcntl qw(:flock O_CREAT O_EXCL O_WRONLY);
use File::Spec;
use JSON::PP ();

my $JSON = JSON::PP->new->utf8->canonical->pretty;

sub new {
    my ($class, %opts) = @_;

    my $base_dir = $opts{base_dir};
    unless ($base_dir) {
        my $xdg = $ENV{XDG_CONFIG_HOME};
        my $home = $ENV{HOME} || (getpwuid($<))[7] || '.';
        $xdg ||= "$home/.config";
        $base_dir = "$xdg/zepto";
    }

    my $self = bless {
        base_dir   => $base_dir,
        _cache     => {},   # category => { data => hashref, mtime => number }
        _listeners => {},   # category => [ sub, ... ]
        _write_mtime => {}, # category => mtime we last wrote (to ignore our own writes)
    }, $class;

    return $self;
}

sub base_dir { $_[0]->{base_dir} }

# Get data for a category. Returns hashref (empty {} if file missing/corrupt).
# Cached; re-reads from disk only when mtime changes.
sub get {
    my ($self, $category) = @_;
    $self->_validate_category($category);

    my $path = $self->_file_path($category);
    my $cached = $self->{_cache}{$category};

    # If file doesn't exist, return cached data or empty hash
    my @stat = stat($path);
    unless (@stat) {
        $self->{_cache}{$category} //= { data => {}, mtime => 0 };
        return $self->{_cache}{$category}{data};
    }

    my $mtime = $stat[9];

    # Return cached if mtime unchanged
    if ($cached && $cached->{mtime} == $mtime) {
        return $cached->{data};
    }

    # Read from disk
    my $data = $self->_read_file($path);
    $self->{_cache}{$category} = { data => $data, mtime => $mtime };
    return $data;
}

# Write data for a category. Atomic, locked, merges with on-disk state.
# Caller's keys overwrite on-disk keys (shallow merge).
sub put {
    my ($self, $category, $data) = @_;
    $self->_validate_category($category);
    $self->_ensure_dir();

    my $path = $self->_file_path($category);
    my $lock_path = $self->_lock_path($category);

    # Open lock file
    open my $lock_fh, '>', $lock_path or return;
    flock($lock_fh, LOCK_EX) or do { close $lock_fh; return; };

    # Read current on-disk state (inside lock)
    my $on_disk = -f $path ? $self->_read_file($path) : {};

    # Shallow merge: caller's keys win
    my %merged = (%$on_disk, %$data);

    # Atomic write
    my $tmp_path = "$path.tmp.$$";
    my $ok = eval {
        my $fh;
        if ($category eq 'secrets') {
            # Secrets must never exist on disk with permissive
            # permissions, even for an instant. sysopen() with
            # O_CREAT|O_EXCL creates the file WITH mode 0600 atomically —
            # there is no window between "file exists" and "permissions
            # restricted" the way a plain open() + later chmod() has.
            # Defensively unlink any stale leftover (a previous crashed
            # process, or an attacker-planted symlink — unlink() removes
            # the symlink itself rather than following it) so O_EXCL
            # doesn't spuriously fail.
            unlink $tmp_path;
            sysopen($fh, $tmp_path, O_CREAT | O_EXCL | O_WRONLY, 0600)
                or die "sysopen: $!";
        } else {
            open($fh, '>', $tmp_path) or die "open: $!";
        }
        print $fh $JSON->encode(\%merged);
        close $fh or die "close: $!";

        rename($tmp_path, $path) or die "rename: $!";
        1;
    };
    unless ($ok) {
        unlink $tmp_path;  # Clean up on failure
        close $lock_fh;
        return;
    }

    # Update cache with merged data and new mtime
    my @stat = stat($path);
    my $mtime = @stat ? $stat[9] : 0;
    $self->{_cache}{$category} = { data => \%merged, mtime => $mtime };
    $self->{_write_mtime}{$category} = $mtime;

    # Release lock
    close $lock_fh;

    return 1;
}

# Register a callback for external changes to a category.
# Callback receives: ($new_data)
sub on_change {
    my ($self, $category, $callback) = @_;
    $self->_validate_category($category);
    $self->{_listeners}{$category} ||= [];
    push @{$self->{_listeners}{$category}}, $callback;
}

# Poll for external changes. Call from event loop (~1/sec).
# Fires on_change callbacks for categories modified by other processes.
# Returns the number of categories that changed, so callers can decide
# whether a re-render is needed (e.g. an idle instance picking up a theme
# toggle from another window — see Editor::run's idle-timeout branch).
sub check_for_changes {
    my ($self) = @_;

    my $changed_count = 0;

    for my $category (keys %{$self->{_cache}}) {
        my $path = $self->_file_path($category);
        my @stat = stat($path);
        next unless @stat;

        my $mtime = $stat[9];
        my $cached = $self->{_cache}{$category};

        # Skip if unchanged
        next if $cached && $cached->{mtime} == $mtime;

        # Skip if this was our own write
        if (defined $self->{_write_mtime}{$category}
            && $self->{_write_mtime}{$category} == $mtime) {
            next;
        }

        # External change detected — reload
        my $data = $self->_read_file($path);
        $self->{_cache}{$category} = { data => $data, mtime => $mtime };
        $changed_count++;

        # Fire listeners
        my $listeners = $self->{_listeners}{$category} || [];
        for my $cb (@$listeners) {
            eval { $cb->($data) };
        }
    }

    return $changed_count;
}

# --- Private helpers ---

sub _validate_category {
    my ($self, $category) = @_;
    die "Invalid category: $category"
        unless defined $category && $category =~ /^[a-z_]+$/;
}

sub _file_path {
    my ($self, $category) = @_;
    return "$self->{base_dir}/$category.json";
}

sub _lock_path {
    my ($self, $category) = @_;
    return "$self->{base_dir}/.$category.lock";
}

sub _ensure_dir {
    my ($self) = @_;
    my $dir = $self->{base_dir};
    return if -d $dir;

    # Create directory recursively
    my @parts = split m{/}, $dir;
    my $built = '';
    for my $part (@parts) {
        $built .= "/$part";
        next if -d $built;
        mkdir $built, 0700 or return;
    }
}

sub _read_file {
    my ($self, $path) = @_;
    open my $fh, '<', $path or return {};
    local $/;
    my $content = <$fh>;
    close $fh;

    my $data = eval { $JSON->decode($content) };
    return (ref $data eq 'HASH') ? $data : {};
}

1;
