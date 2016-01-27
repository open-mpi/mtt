#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2016      Research Organization for Information Science
#                         and Technology (RIST). All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Install::Analyze::OMPI;

use strict;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;
use MTT::Values::Functions::MPI::OMPI;

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
    Debug("Have C bindings: 1\n");

    my $func = \&MTT::Values::Functions::MPI::OMPI::find_bindings;
    $ret->{cxx_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "cxx");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 

    # OMPI 1.7 (and higher) refer to "bindings:mpif.h".  Prior
    # versions refer to "bindings:f77".
    my $tmp;
    $tmp = &{$func}($ret->{bindir}, $ret->{libdir}, "f77");
    $tmp = &{$func}($ret->{bindir}, $ret->{libdir}, "mpif.h")
        if (!$tmp);
    $ret->{mpifh_bindings} = $ret->{f77_bindings} = $tmp;
    Debug("Have mpif.h bindings: $ret->{mpifh_bindings}\n"); 

    # OMPI 1.7 (and higher) refer to "bindings:use_mpi".  Prior
    # versions refer to "bindings:f90".
    $tmp = &{$func}($ret->{bindir}, $ret->{libdir}, "f90");
    $tmp = &{$func}($ret->{bindir}, $ret->{libdir}, "use_mpi")
        if (!$tmp);
    $ret->{usempi_bindings} = $ret->{f90_bindings} = $tmp;
    Debug("Have \"use mpi\" bindings: $ret->{usempi_bindings}\n"); 

    # OMPI 1.7 (and higher) have "bindings:use_mpi_f08".  Prior
    # versions do not have the mpi_f08 interface at all.
    $ret->{usempif08_bindings} = 
        &{$func}($ret->{bindir}, $ret->{libdir}, "use_mpi_f08");
    Debug("Have \"use mpi_f08\" bindings: $ret->{usempif08_bindings}\n"); 

    $func = \&MTT::Values::Functions::MPI::OMPI::find_bitness;
    $config->{bitness} = &{$func}($ret->{bindir}, $ret->{libdir})
        if (!defined($config->{bitness}));


    return $ret;
}

1;
