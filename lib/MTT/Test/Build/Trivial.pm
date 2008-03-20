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

package MTT::Test::Build::Trivial;

use strict;
use Cwd;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;
use Data::Dumper;

#--------------------------------------------------------------------------

sub _do_compile {
    my ($wrapper, $in_name, $out_name) = @_;

    # Do the compile
    my $x = MTT::DoCommand::Cmd(1, "$wrapper $in_name -o $out_name");
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        my $ret;
        $ret->{test_result} = MTT::Values::FAIL;
        $ret->{exit_status} = $x->{exit_status};
        $ret->{result_message} = "Failed to compile/link $out_name using '$wrapper'.\n";
        $ret->{result_stdout} = $x->{result_stdout};
        return $ret;
    }

    # All done
    return undef;
}

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $mpi_install, $config) = @_;
    my $ret;
    my $x;

    Debug("Building Trivial\n");
    $ret->{test_result} = MTT::Values::FAIL;

    my $cflags = Value($ini, $config->{full_section_name}, 
                       "trivial_tests_cflags");
    my $fflags = Value($ini, $config->{full_section_name}, 
                       "trivial_tests_fflags");
    my $languages = Value($ini, $config->{full_section_name}, 
                       "trivial_tests_languages");

    # Default to running *all* flavors of trivial tests
    if (!$languages) {
        $languages = "c,c++,f77,f90";
    }

    my $languages_hash;
    my @arr = split(/,|\s+/, $languages);
    foreach my $lang (@arr) {
        $lang = lc($lang);
        $languages_hash->{"$lang"} = 1;
    }

    # Try compiling and linking a simple C application

    if ($mpi_install->{c_bindings} and $languages_hash->{"c"}) {
        Debug("Test compile/link sample C MPI application\n");
        $x = _do_compile("mpicc $cflags", "hello.c", "c_hello");
        return $x
            if (defined($x));
        $x = _do_compile("mpicc $cflags", "ring.c", "c_ring");
        return $x
            if (defined($x));
    } else {
        Debug("MPI C bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the C++ MPI bindings, try and compile and link a
    # simple C++ application

    if ($mpi_install->{cxx_bindings} and $languages_hash->{"c++"}) {
        Debug("Test compile/link sample C++ MPI application\n");
        $x = _do_compile("mpicxx $cflags", "hello.cc", "cxx_hello");
        return $x
            if (defined($x));
        $x = _do_compile("mpicxx $cflags", "ring.cc", "cxx_ring");
        return $x
            if (defined($x));
    } else {
        Debug("MPI C++ bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the F77 MPI bindings, try compiling and linking a
    # simple F77 application

    if ($mpi_install->{f77_bindings} and $languages_hash->{"f77"}) {
        Debug("Test compile/link sample F77 MPI application\n");
        $x = _do_compile("mpif77 $fflags", "hello.f", "f77_hello");
        return $x
            if (defined($x));
        $x = _do_compile("mpif77 $fflags", "ring.f", "f77_ring");
        return $x
            if (defined($x));
    } else {
        Debug("MPI F77 bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the F90 MPI bindings, try compiling and linking a
    # simple F90 application

    if ($mpi_install->{f90_bindings} and $languages_hash->{"f90"}) {
        Debug("Test compile/link sample F90 MPI application\n");
        $x = _do_compile("mpif90 $fflags", "hello.f90", "f90_hello");
        return $x
            if (defined($x));
        $x = _do_compile("mpif90 $fflags", "ring.f90", "f90_ring");
        return $x
            if (defined($x));
    } else {
        Debug("MPI F90 bindings unavailable; skipping simple compile/link test\n");
    }

    # All done
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{exit_status} = 0;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
