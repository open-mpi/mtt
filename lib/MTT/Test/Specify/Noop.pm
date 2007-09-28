#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Specify::Noop;

use strict;

#--------------------------------------------------------------------------

sub Specify {
    my ($x, $x, $x, $x, $config) = @_;
    my $ret;
    my $one;
    %{$one} = %{$config};
    $one->{executable} = "";
    $one->{tests} = [""];
    push(@{$ret->{tests}}, $one);
    $ret->{test_result} = 1;
    $ret->{np_ok} = 1;
    return $ret;
} 

1;
