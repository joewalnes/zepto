package Zepto::HelpDocs;
# =============================================================================
# HelpDocs: Built-in documentation accessible from the command palette
# =============================================================================
#
# In development mode, docs are read from docs/help/*.md.
# In the built single-file distribution, build.pl embeds them inline.
# =============================================================================

use strict;
use warnings;
use utf8;

# Document registry: id => { label, file }
my @DOC_ORDER = qw(about tutorial changelog license);

my %DOCS = (
    about     => { label => 'About Zepto',      file => 'about.md' },
    tutorial  => { label => 'Tutorial',          file => 'tutorial.md' },
    changelog => { label => 'Changelog',         file => 'changelog.md' },
    license   => { label => 'License & Credits', file => 'license.md' },
);

# Embedded content — populated by build.pl during build, empty in dev mode
my %EMBEDDED;
# __EMBED_DOCS__

sub doc_label {
    my ($class, $id) = @_;
    return $DOCS{$id}{label};
}

sub doc_content {
    my ($class, $id) = @_;
    return undef unless exists $DOCS{$id};
    return $EMBEDDED{$id} if exists $EMBEDDED{$id};

    # Dev mode: read from docs/help/ relative to project root
    my $base = __FILE__;
    $base =~ s{lib/Zepto/HelpDocs\.pm$}{};
    $base = '.' if $base eq '';
    my $path = "$base/docs/help/$DOCS{$id}{file}";
    open my $fh, '<:utf8', $path or return "# Document not found\n\nCould not load: $path\n";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

1;
