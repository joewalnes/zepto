#!/usr/bin/env perl
# A complete Perl program demonstrating various syntax elements

use strict;
use warnings;
use Data::Dumper;

# Constants
use constant MAX_VALUE => 100;
use constant PI => 3.14159;

# Package variable
our $VERSION = '1.0.0';

# Scalar, array, hash variables
my $name = "World";
my $count = 42;
my @items = (1, 2, 3, 'four', "five");
my %config = (
    host => 'localhost',
    port => 8080,
);

# Subroutine definition
sub greet {
    my ($who) = @_;
    return "Hello, $who!";
}

# Control structures
if ($count > 0) {
    print "Positive\n";
} elsif ($count == 0) {
    print "Zero\n";
} else {
    print "Negative\n";
}

# Loops
for my $i (0 .. 10) {
    next if $i % 2;
    last if $i > 5;
    print "$i\n";
}

while ($count > 0) {
    $count--;
}

foreach my $item (@items) {
    print "$item\n";
}

# Regular expressions
if ($name =~ /^[A-Z]/) {
    $name =~ s/World/Universe/g;
}

# Here-doc
my $html = <<'HTML';
<html>
    <body>Hello</body>
</html>
HTML

# Anonymous sub
my $add = sub {
    my ($a, $b) = @_;
    return $a + $b;
};

# Method call and chaining
my $result = Dumper->new()->dump($config);

# Numbers: int, float, hex, octal, binary
my $int = 42;
my $float = 3.14;
my $hex = 0xFF;
my $octal = 0755;
my $binary = 0b1010;
my $sci = 1.5e10;

# Operators
my $sum = $int + $float;
my $concat = $name . "!";
my $bool = ($count && $int) || 0;
my $ternary = $count > 0 ? 'yes' : 'no';

=head1 NAME

perl_complete.pl - Sample Perl file

=head1 DESCRIPTION

This is POD documentation.

=cut

1;
