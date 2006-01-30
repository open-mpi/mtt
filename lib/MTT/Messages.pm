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
@EXPORT = qw(Messages Error Warning Abort Debug Verbose);

# Is debugging enabled?
my $debug;

# Is verbose enabled?
my $verbose;

#--------------------------------------------------------------------------

sub Messages {
    $debug = shift;
    $verbose = shift;

    $Text::Wrap::columns = 76;
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

1;
