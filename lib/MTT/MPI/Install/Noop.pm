#!/usr/bin/env perl
#
# Copyright (c) 2012 Sun Microsystems, Inc.  All rights reserved.
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

    # Make assumptions about the bindings
    $ret->{c_bindings}   = 1;
    $ret->{cxx_bindings} = 1;
    $ret->{mpifh_bindings} = $ret->{f77_bindings} = 1;
    $ret->{usempi_bindings} = $ret->{f90_bindings} = 1;
    $ret->{usempif08_bindings} = 1;

    # If it's OMPI, see if we can refine those assumptions better
    my $prog = FindProgram("ompi_info");
    if (defined($prog)) {
        Debug("This is OMPI, so use ompi_info to figure out which bindings we have\n");

        my $func = \&MTT::Values::Functions::MPI::OMPI::find_bindings;
        $ret->{cxx_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "cxx");
        Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 

        # OMPI 1.7 (and higher) refer to "bindings:mpif.h".  Prior
        # versions refer to "bindings:f77".
        $tmp = &{$func}($ret->{bindir}, $ret->{libdir}, "f77");
        $tmp = &{$func}($ret->{bindir}, $ret->{libdir}, "mpif.h")
            if (!$tmp);
        $ret->{mpifh_bindings} = $ret->{f77_bindings} = $tmp
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
    }

    return $ret;
}

1;
