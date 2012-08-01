#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2012 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::Trivial;

use strict;
use File::Temp qw(tempfile);
use File::Basename;
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;
use MTT::FindProgram;
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
    my $mpicc  = Value($ini, $config->{full_section_name}, 
                    "trivial_tests_mpicc");
    my $mpicxx = Value($ini, $config->{full_section_name}, 
                    "trivial_tests_mpicxx");
    my $mpifort = Value($ini, $config->{full_section_name}, 
                    "trivial_tests_mpifort");
    my $mpif77 = Value($ini, $config->{full_section_name}, 
                    "trivial_tests_mpif77");
    my $mpif90 = Value($ini, $config->{full_section_name}, 
                       "trivial_tests_mpif90");
    my $mpif08 = Value($ini, $config->{full_section_name}, 
                       "trivial_tests_mpif08");

    # Set some default compilers
    $mpicc   = "mpicc"   if (!defined($mpicc));
    $mpicxx  = "mpicxx"  if (!defined($mpicxx));
    if (!defined($mpif77)) {
        $mpif77 = FindProgram(qw/mpifort mpif77/);
        $mpif77 = basename($mpif77)
            if (defined($mpif77));
    }
    if (!defined($mpif90)) {
        $mpif90 = FindProgram(qw/mpifort mpif90/);
        $mpif90 = basename($mpif90)
            if (defined($mpif90));
    }
    $mpif08  = "mpifort" if (!defined($mpif08));

    # Default to running *all* flavors of trivial tests
    if (!$languages) {
        $languages = "c,c++,mpifh,usempi,usempif08";
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
        $x = _do_compile("$mpicc $cflags", "hello.c", "c_hello");
        return $x
            if (defined($x));
        $x = _do_compile("$mpicc $cflags", "ring.c", "c_ring");
        return $x
            if (defined($x));
    } else {
        Debug("MPI C bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the C++ MPI bindings, try and compile and link simple
    # C++ applications

    if ($mpi_install->{cxx_bindings} and $languages_hash->{"c++"}) {
        Debug("Test compile/link sample C++ MPI application\n");
        $x = _do_compile("$mpicxx $cflags", "hello.cc", "cxx_hello");
        return $x
            if (defined($x));
        $x = _do_compile("$mpicxx $cflags", "ring.cc", "cxx_ring");
        return $x
            if (defined($x));
    } else {
        Debug("MPI C++ bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the mpif.h MPI bindings, try compiling and linking
    # simple mpif.h applications

    if ($mpi_install->{mpifh_bindings} and $languages_hash->{"mpifh"}) {
        Debug("Test compile/link sample mpif.h MPI application\n");
        $x = _do_compile("$mpif77 $fflags", "hello_mpifh.f90", "hello_mpifh");
        return $x
            if (defined($x));
        $x = _do_compile("$mpif77 $fflags", "ring_mpifh.f90", "ring_mpifh");
        return $x
            if (defined($x));
    } else {
        Debug("MPI mpif.h bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the "use mpi" MPI bindings, try compiling and linking
    # simple "use mpi" applications

    if ($mpi_install->{usempi_bindings} and $languages_hash->{"usempi"}) {
        Debug("Test compile/link sample \"use mpi\" MPI application\n");
        $x = _do_compile("$mpif90 $fflags", "hello_usempi.f90", "hello_usempi");
        return $x
            if (defined($x));
        $x = _do_compile("$mpif90 $fflags", "ring_usempi.f90", "ring_usempi");
        return $x
            if (defined($x));
    } else {
        Debug("MPI \"use mpi\" bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the "use mpi_f08" MPI bindings, try compiling and
    # linking simple "use mpi_f08" applications

    if ($mpi_install->{usempif08_bindings} and $languages_hash->{"usempif08"}) {
        Debug("Test compile/link sample \"use mpi_f08\" MPI application\n");
        $x = _do_compile("$mpif08 $fflags", "hello_usempif08.f90", "hello_usempif08");
        return $x
            if (defined($x));
        $x = _do_compile("$mpif08 $fflags", "ring_usempif08.f90", "ring_usempif08");
        return $x
            if (defined($x));
    } else {
        Debug("MPI \"use mpi_f08\" bindings unavailable; skipping simple compile/link test\n");
    }

    # All done
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{exit_status} = 0;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
