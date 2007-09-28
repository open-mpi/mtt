#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Install::Noop;

use strict;

#--------------------------------------------------------------------------

sub Install {
    my $ret;
    $ret->{have_new}     = 1;
    $ret->{test_result}  = MTT::Values::PASS;
    $ret->{exit_status}  = 0;
    $ret->{installdir}   = "/dev/null";
    $ret->{bindir}       = "/dev/null";
    $ret->{libdir}       = "/dev/null";
    $ret->{c_bindings}   = 1;
    $ret->{cxx_bindings} = 1;
    $ret->{f77_bindings} = 1;
    $ret->{f90_bindings} = 1;
    return $ret;
}

1;
