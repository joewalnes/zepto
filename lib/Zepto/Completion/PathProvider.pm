package Zepto::Completion::PathProvider;
# =============================================================================
# PathProvider: File path completions for Markdown links/images and imports
# =============================================================================
#
# Provides file path completions in specific contexts:
#   - Markdown [text](path) and ![alt](path)
#   - Import/require statements (import, require, from, use, #include)
# =============================================================================

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {
        _file_cache => undef,  # Cached file list
        _cache_time => 0,      # When cache was built
    }, $class;
}

sub complete {
    my ($self, $context) = @_;

    my $line = $context->{line};
    my $col = $context->{col};
    return [] unless defined $line && $col > 0;

    my $before = substr($line, 0, $col);

    # Detect path context and extract partial path
    my $partial;
    if ($before =~ /!\[[^\]]*\]\(([^)]*?)$/) {
        # Markdown image: ![alt](path
        $partial = $1;
    } elsif ($before =~ /\[[^\]]*\]\(([^)]*?)$/) {
        # Markdown link: [text](path
        $partial = $1;
    } elsif ($before =~ /(?:import|require|from|use)\s+['"]([^'"]*?)$/) {
        # Import/require statement
        $partial = $1;
    } elsif ($before =~ /#include\s+["<]([^">]*?)$/) {
        # C/C++ #include
        $partial = $1;
    }

    return [] unless defined $partial;

    # Get file list
    my $files = $self->_get_files($context->{doc});
    return [] unless $files && @$files;

    my $lc_partial = lc($partial);
    my @matches;

    for my $file (@$files) {
        my $lc_file = lc($file);
        # Match if partial is a prefix of the file path
        if (length($lc_partial) == 0 || index($lc_file, $lc_partial) == 0) {
            push @matches, {
                text  => $file,
                score => 30,
                kind  => 'path',
            };
        }
        # Also match on filename part
        elsif ($file =~ m{([^/]+)$}) {
            my $basename = lc($1);
            if (index($basename, $lc_partial) == 0) {
                push @matches, {
                    text  => $file,
                    score => 25,
                    kind  => 'path',
                };
            }
        }
        last if @matches >= 50;  # Cap results
    }

    return \@matches;
}

sub _get_files {
    my ($self, $doc) = @_;

    # Refresh cache every 5 seconds
    if ($self->{_file_cache} && (time() - $self->{_cache_time}) < 5) {
        return $self->{_file_cache};
    }

    # Try to use FileTree's cached file list if available
    my @files;
    eval {
        if (Zepto::FileTree->can('_all_files')) {
            @files = Zepto::FileTree->_all_files('.');
        }
    };

    # Fallback: scan current directory (limited)
    if (!@files) {
        eval {
            opendir(my $dh, '.') or return;
            while (my $entry = readdir($dh)) {
                next if $entry =~ /^\./;
                if (-f $entry) {
                    push @files, $entry;
                } elsif (-d $entry) {
                    # One level deep
                    opendir(my $subdh, $entry) or next;
                    while (my $sub = readdir($subdh)) {
                        next if $sub =~ /^\./;
                        push @files, "$entry/$sub" if -f "$entry/$sub";
                    }
                    closedir($subdh);
                }
                last if @files > 500;
            }
            closedir($dh);
        };
    }

    $self->{_file_cache} = \@files;
    $self->{_cache_time} = time();
    return $self->{_file_cache};
}

1;
