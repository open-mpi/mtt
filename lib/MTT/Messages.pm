#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Messages;

use strict;
use Data::Dumper;
use Text::Wrap;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(Messages Error Warning Abort Debug Verbose Trace);

# Is debugging enabled?
my $debug;

# Is verbose enabled?
my $verbose;

# Path where mtt was invoked
my $cwd;

#--------------------------------------------------------------------------


sub Messages {
    $debug = shift;
    $verbose = shift;
    $cwd = shift;

    my $textwrap = $MTT::Globals::Values->{textwrap};
    $Text::Wrap::columns = ($textwrap ? $textwrap : 76);
}

sub Error {
    Abort(@_);
}

sub Warning {
    print wrap("", "    ", "*** WARNING: @_");
}

sub Abort {
    my ($msg) = @_;

    die wrap("", "    ", "*** ERROR: $msg");
}

sub Debug {
    print wrap("", "   ", @_) if $debug;
}

sub Verbose {
    print wrap("", "   ", @_) if $verbose;
}

sub Trace {
    my ($str, $lev) = @_;

    $lev = 0 if (! defined($lev));
    my @called = caller($lev);

    print wrap("", "   ", (join(":", map { &relative_path($_) } @called[1..2]), @_)) if $verbose;
}

# Trace helper for showing paths relative to the path mtt was invoked from
sub relative_path {
    my ($path) = shift;
    $path =~ s/$cwd/./;
    return $path;
}

1;
