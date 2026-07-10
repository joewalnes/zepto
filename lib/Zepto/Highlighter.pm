package Zepto::Highlighter;
# =============================================================================
# Syntax Highlighter - Main Dispatcher and State Manager
# =============================================================================
#
# This module coordinates syntax highlighting for the editor. It:
#   1. Detects the appropriate grammar based on file extension or name
#   2. Manages line state caching for multi-line constructs
#   3. Provides the interface used by the Renderer
#
# =============================================================================
# ARCHITECTURE OVERVIEW
# =============================================================================
#
#                    ┌─────────────────────────────────────────────┐
#                    │              Editor / Renderer              │
#                    └────────────────────┬────────────────────────┘
#                                         │
#                                         │ tokenize_line($content, $line_num)
#                                         ▼
#                    ┌─────────────────────────────────────────────┐
#                    │              Highlighter.pm                 │
#                    │  - Detects language from filename          │
#                    │  - Caches line end states                  │
#                    │  - Routes to appropriate grammar           │
#                    └────────────────────┬────────────────────────┘
#                                         │
#                    ┌────────────────────┼────────────────────────┐
#                    │                    │                        │
#                    ▼                    ▼                        ▼
#            ┌───────────┐       ┌───────────┐            ┌───────────┐
#            │ Perl.pm   │       │ Python.pm │    ...     │ Shell.pm  │
#            └───────────┘       └───────────┘            └───────────┘
#                    │                    │                        │
#                    └────────────────────┼────────────────────────┘
#                                         │
#                                         ▼
#                    ┌─────────────────────────────────────────────┐
#                    │           Token Stream                      │
#                    │  [{start: 0, end: 5, type: 'keyword'}, ...] │
#                    └─────────────────────────────────────────────┘
#
# =============================================================================
# USAGE
# =============================================================================
#
#   my $highlighter = Zepto::Highlighter->new();
#   $highlighter->set_file('/path/to/file.py');
#
#   # For each visible line in the viewport:
#   my ($tokens, $state) = $highlighter->tokenize_line($content, $line_num);
#
#   # After editing line N:
#   $highlighter->invalidate_from($line_num);
#
# =============================================================================
# STATE MANAGEMENT
# =============================================================================
#
# Multi-line constructs (strings, comments, heredocs) require tracking state
# across lines. The highlighter maintains a cache of "end states" for each line.
#
#   Line 0: "normal code /* start comment"  → end state: COMMENT_BLOCK
#   Line 1: "   still in comment"           → end state: COMMENT_BLOCK
#   Line 2: "end comment */ normal"         → end state: NORMAL
#
# When a line is edited, we invalidate states from that line onwards,
# since changes might affect subsequent lines (e.g., adding/removing quotes).
#
# =============================================================================

use strict;
use warnings;

# Extension to grammar class mapping
# Keys are lowercase extensions (without dot)
my %EXTENSION_MAP = (
    # Perl
    pl   => 'Zepto::Syntax::Perl',
    pm   => 'Zepto::Syntax::Perl',
    t    => 'Zepto::Syntax::Perl',
    pod  => 'Zepto::Syntax::Perl',

    # Python
    py   => 'Zepto::Syntax::Python',
    pyw  => 'Zepto::Syntax::Python',
    pyi  => 'Zepto::Syntax::Python',

    # JavaScript
    js   => 'Zepto::Syntax::JavaScript',
    mjs  => 'Zepto::Syntax::JavaScript',
    cjs  => 'Zepto::Syntax::JavaScript',
    jsx  => 'Zepto::Syntax::JavaScript',

    # TypeScript
    ts   => 'Zepto::Syntax::TypeScript',
    tsx  => 'Zepto::Syntax::TypeScript',
    mts  => 'Zepto::Syntax::TypeScript',
    cts  => 'Zepto::Syntax::TypeScript',

    # Ruby
    rb   => 'Zepto::Syntax::Ruby',
    rake => 'Zepto::Syntax::Ruby',
    gemspec => 'Zepto::Syntax::Ruby',

    # Java
    java => 'Zepto::Syntax::Java',

    # PHP
    php  => 'Zepto::Syntax::PHP',
    php3 => 'Zepto::Syntax::PHP',
    php4 => 'Zepto::Syntax::PHP',
    php5 => 'Zepto::Syntax::PHP',
    phtml => 'Zepto::Syntax::PHP',

    # Shell
    sh   => 'Zepto::Syntax::Shell',
    bash => 'Zepto::Syntax::Shell',
    zsh  => 'Zepto::Syntax::Shell',
    ksh  => 'Zepto::Syntax::Shell',
    fish => 'Zepto::Syntax::Fish',

    # Markdown
    md       => 'Zepto::Syntax::Markdown',
    markdown => 'Zepto::Syntax::Markdown',
    mkd      => 'Zepto::Syntax::Markdown',

    # Go
    go       => 'Zepto::Syntax::Go',

    # Rust
    rs       => 'Zepto::Syntax::Rust',

    # Zig
    zig      => 'Zepto::Syntax::Zig',

    # Swift
    swift    => 'Zepto::Syntax::Swift',

    # C
    c        => 'Zepto::Syntax::C',
    h        => 'Zepto::Syntax::C',

    # C++
    cpp      => 'Zepto::Syntax::Cpp',
    cc       => 'Zepto::Syntax::Cpp',
    cxx      => 'Zepto::Syntax::Cpp',
    hpp      => 'Zepto::Syntax::Cpp',
    hh       => 'Zepto::Syntax::Cpp',
    hxx      => 'Zepto::Syntax::Cpp',

    # HTML
    html     => 'Zepto::Syntax::HTML',
    htm      => 'Zepto::Syntax::HTML',
    xhtml    => 'Zepto::Syntax::HTML',

    # XML
    xml      => 'Zepto::Syntax::XML',
    xsl      => 'Zepto::Syntax::XML',
    xslt     => 'Zepto::Syntax::XML',
    svg      => 'Zepto::Syntax::XML',
    plist    => 'Zepto::Syntax::XML',

    # CSS
    css      => 'Zepto::Syntax::CSS',

    # JSON
    json     => 'Zepto::Syntax::JSON',

    # KDL
    kdl      => 'Zepto::Syntax::KDL',

    # YAML
    yaml     => 'Zepto::Syntax::YAML',
    yml      => 'Zepto::Syntax::YAML',

    # Makefile extensions
    mk       => 'Zepto::Syntax::Makefile',
    mak      => 'Zepto::Syntax::Makefile',

    # SQL
    sql      => 'Zepto::Syntax::SQL',
    mysql    => 'Zepto::Syntax::SQL',
    pgsql    => 'Zepto::Syntax::SQL',
    plsql    => 'Zepto::Syntax::SQL',
    hql      => 'Zepto::Syntax::SQL',

    # Kotlin
    kt       => 'Zepto::Syntax::Kotlin',
    kts      => 'Zepto::Syntax::Kotlin',

    # C#
    cs       => 'Zepto::Syntax::CSharp',
    csx      => 'Zepto::Syntax::CSharp',

    # TOML
    toml     => 'Zepto::Syntax::TOML',

    # Dockerfile
    dockerfile => 'Zepto::Syntax::Dockerfile',

    # Terraform/HCL
    tf       => 'Zepto::Syntax::Terraform',
    tfvars   => 'Zepto::Syntax::Terraform',
    hcl      => 'Zepto::Syntax::Terraform',

    # Lua
    lua      => 'Zepto::Syntax::Lua',

    # Scala
    scala    => 'Zepto::Syntax::Scala',
    sc       => 'Zepto::Syntax::Scala',
    sbt      => 'Zepto::Syntax::Scala',

    # Protocol Buffers
    proto    => 'Zepto::Syntax::Protobuf',

    # Groovy
    groovy   => 'Zepto::Syntax::Groovy',
    gradle   => 'Zepto::Syntax::Groovy',
    gvy      => 'Zepto::Syntax::Groovy',
    gy       => 'Zepto::Syntax::Groovy',
    gsh      => 'Zepto::Syntax::Groovy',

    # Clojure and S-expression languages
    clj      => 'Zepto::Syntax::Clojure',
    cljs     => 'Zepto::Syntax::Clojure',
    cljc     => 'Zepto::Syntax::Clojure',
    edn      => 'Zepto::Syntax::Clojure',
    lisp     => 'Zepto::Syntax::Clojure',
    cl       => 'Zepto::Syntax::Clojure',
    lsp      => 'Zepto::Syntax::Clojure',
    scm      => 'Zepto::Syntax::Clojure',
    ss       => 'Zepto::Syntax::Clojure',
    rkt      => 'Zepto::Syntax::Clojure',
    el       => 'Zepto::Syntax::Clojure',

    # Objective-C
    m        => 'Zepto::Syntax::ObjectiveC',
    mm       => 'Zepto::Syntax::ObjectiveC',

    # Bazel (reuse Python syntax)
    bzl      => 'Zepto::Syntax::Python',
    bazel    => 'Zepto::Syntax::Python',

    # Thrift
    thrift   => 'Zepto::Syntax::Thrift',

    # INI
    ini      => 'Zepto::Syntax::INI',
    cfg      => 'Zepto::Syntax::INI',
    conf     => 'Zepto::Syntax::INI',

    # Properties
    properties => 'Zepto::Syntax::Properties',

    # Diff/Patch
    diff     => 'Zepto::Syntax::Diff',
    patch    => 'Zepto::Syntax::Diff',

    # Nginx (handled mainly via FILENAME_MAP)
    nginxconf => 'Zepto::Syntax::Nginx',

    # CMake
    cmake    => 'Zepto::Syntax::CMake',

    # SCSS/Sass/Less
    scss     => 'Zepto::Syntax::SCSS',
    sass     => 'Zepto::Syntax::SCSS',
    less     => 'Zepto::Syntax::SCSS',

    # GraphQL
    graphql  => 'Zepto::Syntax::GraphQL',
    gql      => 'Zepto::Syntax::GraphQL',

    # R
    r        => 'Zepto::Syntax::R',
    R        => 'Zepto::Syntax::R',
    rmd      => 'Zepto::Syntax::R',

    # systemd unit files
    service  => 'Zepto::Syntax::Systemd',
    timer    => 'Zepto::Syntax::Systemd',
    socket   => 'Zepto::Syntax::Systemd',
    mount    => 'Zepto::Syntax::Systemd',
    target   => 'Zepto::Syntax::Systemd',
    path     => 'Zepto::Syntax::Systemd',
    slice    => 'Zepto::Syntax::Systemd',
    scope    => 'Zepto::Syntax::Systemd',
    automount => 'Zepto::Syntax::Systemd',
    swap     => 'Zepto::Syntax::Systemd',
    device   => 'Zepto::Syntax::Systemd',
    network  => 'Zepto::Syntax::Systemd',
    netdev   => 'Zepto::Syntax::Systemd',
    link     => 'Zepto::Syntax::Systemd',

    # Log files
    log      => 'Zepto::Syntax::Logfile',

    # SSH config
    sshconfig => 'Zepto::Syntax::SSHConfig',

    # Crontab
    crontab  => 'Zepto::Syntax::Crontab',

    # Fish shell (also mapped above in Shell section)

    # Nix
    nix      => 'Zepto::Syntax::Nix',

    # LaTeX
    tex      => 'Zepto::Syntax::LaTeX',
    latex    => 'Zepto::Syntax::LaTeX',
    sty      => 'Zepto::Syntax::LaTeX',
    cls      => 'Zepto::Syntax::LaTeX',
    bib      => 'Zepto::Syntax::LaTeX',

    # reStructuredText
    rst      => 'Zepto::Syntax::ReStructuredText',
    rest     => 'Zepto::Syntax::ReStructuredText',

    # AsciiDoc
    adoc     => 'Zepto::Syntax::AsciiDoc',
    asciidoc => 'Zepto::Syntax::AsciiDoc',
    asc      => 'Zepto::Syntax::AsciiDoc',
);

# Filename to grammar mapping (for files without extensions or special names)
my %FILENAME_MAP = (
    'Makefile'       => 'Zepto::Syntax::Makefile',
    'makefile'       => 'Zepto::Syntax::Makefile',
    'GNUmakefile'    => 'Zepto::Syntax::Makefile',
    'Rakefile'       => 'Zepto::Syntax::Ruby',
    'Gemfile'        => 'Zepto::Syntax::Ruby',
    'Vagrantfile'    => 'Zepto::Syntax::Ruby',
    '.bashrc'        => 'Zepto::Syntax::Shell',
    '.bash_profile'  => 'Zepto::Syntax::Shell',
    '.zshrc'         => 'Zepto::Syntax::Shell',
    '.profile'       => 'Zepto::Syntax::Shell',

    # Dockerfile
    'Dockerfile'     => 'Zepto::Syntax::Dockerfile',
    'dockerfile'     => 'Zepto::Syntax::Dockerfile',
    'Containerfile'  => 'Zepto::Syntax::Dockerfile',

    # Gradle build files
    'build.gradle'     => 'Zepto::Syntax::Groovy',
    'settings.gradle'  => 'Zepto::Syntax::Groovy',
    'build.gradle.kts' => 'Zepto::Syntax::Kotlin',
    'settings.gradle.kts' => 'Zepto::Syntax::Kotlin',

    # Bazel build files (use Python syntax)
    'BUILD'          => 'Zepto::Syntax::Python',
    'BUILD.bazel'    => 'Zepto::Syntax::Python',
    'WORKSPACE'      => 'Zepto::Syntax::Python',
    'WORKSPACE.bazel'=> 'Zepto::Syntax::Python',

    # Config files
    'Cargo.toml'     => 'Zepto::Syntax::TOML',
    'pyproject.toml' => 'Zepto::Syntax::TOML',

    # INI config files
    '.gitconfig'     => 'Zepto::Syntax::INI',
    '.gitmodules'    => 'Zepto::Syntax::INI',
    '.editorconfig'  => 'Zepto::Syntax::INI',
    'setup.cfg'      => 'Zepto::Syntax::INI',
    'tox.ini'        => 'Zepto::Syntax::INI',
    'php.ini'        => 'Zepto::Syntax::INI',
    'my.cnf'         => 'Zepto::Syntax::INI',
    '.npmrc'         => 'Zepto::Syntax::INI',
    '.pylintrc'      => 'Zepto::Syntax::INI',

    # Nginx config files
    'nginx.conf'     => 'Zepto::Syntax::Nginx',

    # CMake
    'CMakeLists.txt' => 'Zepto::Syntax::CMake',

    # SSH config
    'ssh_config'     => 'Zepto::Syntax::SSHConfig',
    'sshd_config'    => 'Zepto::Syntax::SSHConfig',
    'config'         => 'Zepto::Syntax::SSHConfig',  # ~/.ssh/config

    # Crontab
    'crontab'        => 'Zepto::Syntax::Crontab',

    # Fish config
    'config.fish'    => 'Zepto::Syntax::Fish',

    # Nix
    'default.nix'    => 'Zepto::Syntax::Nix',
    'shell.nix'      => 'Zepto::Syntax::Nix',
    'flake.nix'      => 'Zepto::Syntax::Nix',
    'configuration.nix' => 'Zepto::Syntax::Nix',
);

# Shebang to grammar mapping
# Supports versioned interpreters (python3, ruby2.7) and common variants
my %SHEBANG_MAP = (
    perl     => 'Zepto::Syntax::Perl',
    python   => 'Zepto::Syntax::Python',
    python2  => 'Zepto::Syntax::Python',
    python3  => 'Zepto::Syntax::Python',
    ruby     => 'Zepto::Syntax::Ruby',
    node     => 'Zepto::Syntax::JavaScript',
    nodejs   => 'Zepto::Syntax::JavaScript',
    deno     => 'Zepto::Syntax::JavaScript',
    bun      => 'Zepto::Syntax::JavaScript',
    bash     => 'Zepto::Syntax::Shell',
    sh       => 'Zepto::Syntax::Shell',
    zsh      => 'Zepto::Syntax::Shell',
    ksh      => 'Zepto::Syntax::Shell',
    dash     => 'Zepto::Syntax::Shell',
    uv       => 'Zepto::Syntax::Python',
    fish     => 'Zepto::Syntax::Fish',
    php      => 'Zepto::Syntax::PHP',
    lua      => 'Zepto::Syntax::Lua',
    luajit   => 'Zepto::Syntax::Lua',
    groovy   => 'Zepto::Syntax::Groovy',
    scala    => 'Zepto::Syntax::Scala',
    kotlin   => 'Zepto::Syntax::Kotlin',
    racket   => 'Zepto::Syntax::Clojure',
    guile    => 'Zepto::Syntax::Clojure',
    sbcl     => 'Zepto::Syntax::Clojure',
    clisp    => 'Zepto::Syntax::Clojure',
    Rscript  => 'Zepto::Syntax::R',
);

sub new {
    my ($class, %args) = @_;
    return bless {
        grammar      => undef,   # Current grammar instance
        grammar_class=> undef,   # Grammar class name (for reloading)
        line_states  => [],      # End state for each line
        filename     => undef,   # Current filename
    }, $class;
}

# Set the file to highlight. Detects and loads the appropriate grammar.
# Call this when opening a file or when the file is renamed.
sub set_file {
    my ($self, $filename) = @_;

    $self->{filename} = $filename;
    $self->{line_states} = [];

    my $grammar_class = $self->_detect_grammar($filename);

    if ($grammar_class && $grammar_class ne ($self->{grammar_class} // '')) {
        $self->{grammar_class} = $grammar_class;
        $self->{grammar} = $self->_load_grammar($grammar_class);
    } elsif (!$grammar_class) {
        $self->{grammar} = undef;
        $self->{grammar_class} = undef;
    }
}

# Load a grammar class, handling both module-based and bundled environments
sub _load_grammar {
    my ($self, $grammar_class) = @_;

    # Check if the class is already defined (bundled build or already loaded)
    if ($grammar_class->can('new')) {
        return $grammar_class->new();
    }

    # Try to require the module (development environment)
    eval "require $grammar_class";
    if ($@) {
        warn "Failed to load grammar $grammar_class: $@";
        return undef;
    }

    return $grammar_class->new();
}

# Detect grammar from shebang line (first line of file)
# Handles various formats:
#   #!/bin/bash
#   #!/usr/bin/env python
#   #!/usr/bin/env -S python3 -u
#   #!/usr/bin/python3
#   #! /bin/sh
sub detect_from_shebang {
    my ($self, $first_line) = @_;

    return unless defined $first_line && $first_line =~ /^#!\s*(.+)/;

    my $shebang = $1;

    # Extract the interpreter name, handling various formats:
    # - /bin/bash -> bash
    # - /usr/bin/env python -> python
    # - /usr/bin/env -S python3 -u -> python3
    # - /usr/bin/python3 -> python3
    # - /usr/bin/python3.11 -> python3.11 -> python3
    my $interpreter;

    if ($shebang =~ m{(?:^|/)env\s+(?:-\S+\s+)*(\S+)}) {
        # Handle: env python, env -S python3 -u, etc.
        $interpreter = $1;
    } elsif ($shebang =~ m{^(\S+)}) {
        # Direct path: /bin/bash, /usr/bin/python3
        $interpreter = $1;
        $interpreter =~ s{.*/}{};  # Remove path component
    }

    return unless $interpreter;

    # Strip version suffixes for matching (python3.11 -> python3 -> python)
    # But try most specific first
    my @variants = ($interpreter);

    # Add variant without minor version: python3.11 -> python3
    if ($interpreter =~ /^(\w+\d+)\.\d+$/) {
        push @variants, $1;
    }

    # Add variant without any version: python3 -> python
    if ($interpreter =~ /^(\w+)\d/) {
        push @variants, $1;
    }

    for my $variant (@variants) {
        if (exists $SHEBANG_MAP{lc $variant}) {
            my $grammar_class = $SHEBANG_MAP{lc $variant};
            if ($grammar_class ne ($self->{grammar_class} // '')) {
                $self->{grammar_class} = $grammar_class;
                $self->{grammar} = $self->_load_grammar($grammar_class);
                $self->{line_states} = [] if $self->{grammar};
            }
            return;
        }
    }
}

# Tokenize a single line, using cached state if available
# Returns: (\@tokens, $end_state)
sub tokenize_line {
    my ($self, $line_content, $line_num) = @_;

    return ([], undef) unless $self->{grammar};

    # Get start state for this line
    my $start_state;
    if ($line_num == 0) {
        $start_state = $self->{grammar}->initial_state();
    } else {
        $start_state = $self->{line_states}[$line_num - 1];
        # If we don't have cached state, we need to process from last known
        if (!defined $start_state) {
            $self->_rebuild_states_to($line_num);
            $start_state = $line_num > 0
                ? ($self->{line_states}[$line_num - 1] // $self->{grammar}->initial_state())
                : $self->{grammar}->initial_state();
        }
    }

    my ($tokens, $end_state) = $self->{grammar}->tokenize($line_content // '', $start_state);

    # Cache end state
    $self->{line_states}[$line_num] = $end_state;

    return ($tokens, $end_state);
}

# Get the start state for a given line (end state of previous line)
# Used by toggle-comment for context-aware commenting in HTML
sub line_start_state {
    my ($self, $line_num) = @_;
    return $self->{grammar} ? $self->{grammar}->initial_state() : 0 if !$line_num || $line_num <= 0;
    my $prev_state = $self->{line_states}[$line_num - 1];
    return $prev_state if defined $prev_state;
    # State not cached — rebuild up to this line
    $self->_rebuild_states_to($line_num);
    return $self->{line_states}[$line_num - 1] // ($self->{grammar} ? $self->{grammar}->initial_state() : 0);
}

# Invalidate cached states from a line onwards
# Call this after editing a line
sub invalidate_from {
    my ($self, $line_num) = @_;
    splice @{$self->{line_states}}, $line_num if $line_num < @{$self->{line_states}};
}

# Check if highlighting is available for current file
sub has_grammar {
    my ($self) = @_;
    return defined $self->{grammar};
}

# Get current grammar name (for display)
sub grammar_name {
    my ($self) = @_;
    return undef unless $self->{grammar_class};
    my $name = $self->{grammar_class};
    $name =~ s/.*:://;
    return $name;
}

# =============================================================================
# Private methods
# =============================================================================

sub _detect_grammar {
    my ($self, $filename) = @_;

    return undef unless defined $filename;

    # Extract basename
    my $basename = $filename;
    $basename =~ s{.*/}{};

    # Check filename map first (for Makefile, .bashrc, etc.)
    return $FILENAME_MAP{$basename} if exists $FILENAME_MAP{$basename};

    # Extract extension
    if ($basename =~ /\.([^.]+)$/) {
        my $ext = lc($1);
        return $EXTENSION_MAP{$ext} if exists $EXTENSION_MAP{$ext};
    }

    return undef;
}

sub _rebuild_states_to {
    my ($self, $target_line) = @_;

    # This would require access to document content, which we don't have here.
    # In practice, lines are tokenized in order from the viewport, so this
    # is rarely needed. If needed, the renderer should ensure sequential
    # tokenization.
}

1;

__END__

=head1 NAME

Zepto::Highlighter - Syntax highlighting coordinator for Zepto editor

=head1 SYNOPSIS

    use Zepto::Highlighter;

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('script.py');

    # Tokenize visible lines
    for my $line_num (0 .. $viewport_height) {
        my $content = $doc->get_line_content($line_num);
        my ($tokens, $state) = $hl->tokenize_line($content, $line_num);

        for my $token (@$tokens) {
            # Apply $theme->color("syntax_$token->{type}") to
            # characters from $token->{start} to $token->{end}
        }
    }

    # After user edits line 5
    $hl->invalidate_from(5);

=head1 DESCRIPTION

Manages syntax highlighting grammars and line state caching.

=head1 SUPPORTED LANGUAGES

Perl, Python, JavaScript, TypeScript, Ruby, Java, PHP, Shell (Bash),
Markdown, Makefile

=head1 SEE ALSO

L<Zepto::Syntax::Base> - Base class for grammars

=cut
