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

# Time::HiRes::alarm overrides CORE::alarm in this package only, adding
# fractional-second resolution -- see TOKENIZE_ALARM_SECS below for why
# that's needed. Same core-only import pattern already used for `time` in
# FindEngine.pm/StateStore.pm/etc. (Rule 1: stdlib only, no CPAN).
use Time::HiRes qw(alarm);

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

# Bound on the token memo cache (see tokenize_line() below). Cleared
# wholesale once exceeded, mirroring Renderer.pm's `_table_cache` "evict by
# clearing" pattern rather than a full LRU -- simplicity over marginal
# hit-rate for the pathological case of a huge file with mostly-unique
# line content. 8000 keeps memory bounded (each entry is a small tokens
# arrayref) while comfortably covering many screenfuls of scrolling/typing
# through a large real-world file without thrashing.
use constant MAX_TOKEN_CACHE_ENTRIES => 8000;

# Wall-clock ceiling (seconds) for a single grammar tokenize() call on one
# line. Follows the exact same guard idiom as FindEngine.pm's
# _match_with_alarm (local $SIG{ALRM}, alarm(N), eval{}, unconditional
# alarm(0) cleanup, a distinct sentinel exception for "timed out" vs. a
# real Perl error) -- but with a MUCH smaller budget than FindEngine's
# MATCH_ALARM_SECS (1s).
#
# Why smaller: FindEngine's alarm guards one explicit, user-initiated
# search() call. tokenize_line() runs on every visible line, on every
# render() -- including every single keystroke, not just an explicit user
# action. A viewport is commonly 30-100 lines; at a 1s-per-line budget, a
# handful of slow lines could visibly freeze the editor for many seconds.
# FindEngine.pm's own comment on MATCH_ALARM_SECS notes that legitimate
# (non-catastrophic) matches complete in low single-digit milliseconds
# even against multi-megabyte single-line input. 100ms keeps roughly
# 20-50x headroom above that worst-case legitimate cost while still
# failing fast enough that even a fully-pathological viewport degrades
# to "briefly slow" rather than "hung".
#
# Perl's core alarm() only accepts whole seconds -- far too coarse for a
# 100ms budget. Time::HiRes::alarm() (imported above, overriding
# CORE::alarm in this package only) supports fractional seconds with the
# same SIGALRM delivery/cancellation semantics; it's a drop-in swap, not
# a different mechanism.
use constant TOKENIZE_ALARM_SECS => 0.1;

sub new {
    my ($class, %args) = @_;
    return bless {
        grammar      => undef,   # Current grammar instance
        grammar_class=> undef,   # Grammar class name (for reloading)
        line_states  => [],      # End state for each line
        filename     => undef,   # Current filename

        # Token memo cache: { start_state => { line_content => [tokens, end_state] } }.
        # See tokenize_line() for why keying on both start_state and content
        # makes this cache self-invalidating -- no explicit invalidation
        # logic is needed beyond clearing it wholesale on set_file().
        _token_cache       => {},
        _token_cache_count => 0,   # entries currently cached (for the size cap)

        # Set when a grammar's tokenize() call has ever hit
        # TOKENIZE_ALARM_SECS on the current file. Mirrors FindEngine.pm's
        # _search_timed_out flag/accessor pattern. Reset in set_file()
        # (start of a fresh unit of work), not per tokenize_line() call --
        # a single render pass may mix pathological and normal lines and
        # we don't want a later normal line to erase the signal that an
        # earlier one in the same pass timed out.
        _highlight_timed_out => 0,
    }, $class;
}

# Set the file to highlight. Detects and loads the appropriate grammar.
# Call this when opening a file or when the file is renamed.
sub set_file {
    my ($self, $filename) = @_;

    $self->{filename} = $filename;
    $self->{line_states} = [];
    # Grammar may be changing (e.g. Save As with a new extension) -- cached
    # tokens are only valid for the grammar that produced them, so clear
    # unconditionally rather than trying to detect whether the grammar
    # actually changed.
    $self->{_token_cache} = {};
    $self->{_token_cache_count} = 0;
    $self->{_highlight_timed_out} = 0;

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
                if ($self->{grammar}) {
                    $self->{line_states} = [];
                    # Cached tokens were produced by the old grammar; drop them.
                    $self->{_token_cache} = {};
                    $self->{_token_cache_count} = 0;
                }
            }
            return;
        }
    }
}

# Tokenize a single line, using cached state and a content+state token memo
# if available.
# Returns: (\@tokens, $end_state)
sub tokenize_line {
    my ($self, $line_content, $line_num) = @_;

    return ([], undef) unless $self->{grammar};

    $line_content //= '';

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

    # Token memo cache, keyed on (start_state, line_content). grammar
    # tokenize() implementations are pure functions of exactly these two
    # inputs (verified across all grammars in Syntax/*.pm: no instance or
    # module-level mutable state read during tokenize()), so this key
    # fully captures everything that can affect the result -- which makes
    # the cache self-invalidating with no separate bookkeeping needed:
    #   - Editing this line's own content changes $line_content -> new key.
    #   - Editing an EARLIER line in a way that changes what state a later,
    #     otherwise-untouched line starts in (e.g. opening/closing a
    #     multi-line comment upstream) changes $start_state -> new key.
    # Either way it's a natural cache miss, not stale data served from a
    # miss-classified "unchanged" line. A hit only ever happens when both
    # inputs are byte-identical to a previous call, in which case the pure
    # function is guaranteed to return the same tokens and end_state.
    #
    # Returned token arrayrefs are shared with the cache (not cloned) --
    # safe because every caller (Renderer.pm) only reads token fields to
    # build its own visual-position copies; nothing mutates them in place.
    my $state_bucket = $self->{_token_cache}{$start_state} //= {};
    if (my $cached = $state_bucket->{$line_content}) {
        my ($tokens, $end_state) = @$cached;
        $self->{line_states}[$line_num] = $end_state;
        return ($tokens, $end_state);
    }

    my ($timed_out, $tokens, $end_state) = $self->_tokenize_with_alarm(sub {
        return $self->{grammar}->tokenize($line_content, $start_state);
    });

    if ($timed_out) {
        $self->{_highlight_timed_out} = 1;
        # Give up on this line's highlighting for this (and every future,
        # via the cache write below) render: no tokens means the renderer
        # draws it as plain/unhighlighted text -- never block, never crash.
        #
        # end_state: assume unchanged from start_state rather than
        # guessing what the grammar would have produced. We don't know
        # whether the real tokenize() would have entered a multi-line
        # construct (e.g. opened a block comment) -- guessing wrong would
        # desync every subsequent line's start state from what a working
        # grammar would produce. Assuming STATE_NORMAL-equivalent
        # continuity (start_state carried through unchanged) is the more
        # conservative failure: at worst a multi-line construct that
        # *should* have opened here doesn't get highlighted either, which
        # is the same "give up gracefully" behavior we already chose for
        # this line, rather than corrupting unrelated lines below it.
        $tokens = [];
        $end_state = $start_state;
    }

    # Cache end state
    $self->{line_states}[$line_num] = $end_state;

    # Bound the memo cache: clear wholesale once it grows past the cap,
    # mirroring Renderer.pm's _table_cache "evict by clearing" pattern.
    if ($self->{_token_cache_count} >= MAX_TOKEN_CACHE_ENTRIES) {
        $self->{_token_cache} = {};
        $self->{_token_cache_count} = 0;
        $state_bucket = $self->{_token_cache}{$start_state} = {};
    }

    # A timed-out result is cached here exactly like a normal one -- this
    # is deliberate, not an oversight. Without it, a genuinely pathological
    # line would re-run the full TOKENIZE_ALARM_SECS budget on every single
    # render of that line (every scroll, every keystroke on another line
    # that redraws the viewport), i.e. a tight retry loop paying the
    # timeout cost forever. Caching the fallback means the cost is paid
    # once per (start_state, line_content) key, then every future request
    # for that exact key hits the memo and returns instantly -- same
    # amortization the cache already gives normal lines, just with "gave up,
    # render as plain text" as the memoized answer instead of real tokens.
    # This is still a pure function of the two key inputs: the same
    # pathological pattern against the same content deterministically
    # re-triggers the same catastrophic backtracking, so re-deriving it
    # would (barring wall-clock jitter right at the timeout boundary,
    # already an accepted tradeoff in FindEngine.pm's identical alarm
    # design) reach the same "timed out" outcome every time anyway.
    $state_bucket->{$line_content} = [$tokens, $end_state];
    $self->{_token_cache_count}++;

    return ($tokens, $end_state);
}

# Query whether any grammar tokenize() call has hit TOKENIZE_ALARM_SECS
# since the current file was loaded (set_file() resets this). Mirrors
# FindEngine.pm's search_timed_out() accessor/flag pattern.
sub highlight_timed_out {
    my ($self) = @_;
    return $self->{_highlight_timed_out} ? 1 : 0;
}

# Run a grammar's tokenize() call (passed as a coderef so the caller
# controls exactly what's guarded) under a wall-clock alarm. Returns
# ($timed_out, @result) where @result is exactly whatever $coderef->()
# returned (empty if timed out).
#
# Follows the identical cleanup discipline as FindEngine.pm's
# _match_with_alarm: $SIG{ALRM} is localized to the eval, a distinct
# sentinel exception ("tokenize_timeout") distinguishes an alarm firing
# from a real error in the grammar (which is re-thrown, not swallowed --
# a bug in a grammar's tokenize() should surface, not be silently treated
# as "just slow"), and alarm(0) is called both on the success path inside
# the eval and unconditionally after it, so no armed alarm can ever leak
# out of this call regardless of how it exits.
sub _tokenize_with_alarm {
    my ($self, $coderef) = @_;

    my @result = eval {
        local $SIG{ALRM} = sub { die "tokenize_timeout\n" };
        alarm(TOKENIZE_ALARM_SECS);
        my @r = $coderef->();
        alarm(0);
        @r;
    };
    alarm(0);  # Ensure alarm is cancelled even on exception

    if ($@) {
        die $@ unless $@ eq "tokenize_timeout\n";
        return (1);  # timed_out, no result
    }
    return (0, @result);
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

# Get list of supported extensions
sub supported_extensions {
    return sort keys %EXTENSION_MAP;
}

# Get list of supported filenames
sub supported_filenames {
    return sort keys %FILENAME_MAP;
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
