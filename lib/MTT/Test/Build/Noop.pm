#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc. All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::Noop;

use strict;

#--------------------------------------------------------------------------

sub Build {
    my $ret;
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{exit_status} = 0;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
