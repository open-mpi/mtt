#!/usr/bin/env perl
#
# Copyright (c) 2008      Mellanox Technologies.  All rights reserved.
# Copyright (c) 2008      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Install::Analyze::MVAPICH;

use strict;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;
use MTT::Values::Functions::MPI::MVAPICH;

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

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    my $func = \&MTT::Values::Functions::MPI::MVAPICH::find_bindings;
    $ret->{cxx_bindings} = &{$func}($ret->{bindir}, "CXX");
    $ret->{f77_bindings} = &{$func}($ret->{bindir}, "F77");
    $ret->{f90_bindings} = &{$func}($ret->{bindir}, "F90");

    return $ret;
}

1;
