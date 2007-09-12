#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Install::Analyze::IntelMPI;

use strict;
use Data::Dumper;
use MTT::Messages;
use MTT::Values;

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;
    my $result_stdout;
    my $result_stderr;

    # Prepare $ret
    my $ret;
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{exit_status} = 0;

    # Grab installdir parameter
    $ret->{installdir} = $config->{module_data}->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    # Set the compiler
    $config->{compiler_name} = "intel";
    $config->{compiler_version} = "9.1";

    # Intel MPI has all the bindings
    $ret->{c_bindings} = 1;
    $ret->{cxx_bindings} = 1;
    $ret->{f77_bindings} = 1;
    $ret->{f90_bindings} = 1;

    return $ret;
}

1;
