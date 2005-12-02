#!/usr/bin/env perl

use Data::Dumper;

my $foo = "foo";

my @l;
my @x;

push(@x, $foo);
push(@x, $foo);

push(@l, $foo);
push(@l, $foo);
push(@l, @x);

my $r = \@x;
push(@l, @$r);

print $#$r;

print Dumper(@l);
