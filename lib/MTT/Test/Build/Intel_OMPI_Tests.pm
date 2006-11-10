#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::Intel_OMPI_Tests;

use strict;
use Cwd;
use MTT::DoCommand;
use MTT::Messages;
use MTT::Values;

# default buildfile
my $default_buildfile = "all_tests_no_perf";

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $mpi_install, $config) = @_;
    my $ret;
    my $x;

    Debug("Building Intel OMPI tests (Intel tests from ompi-tests SVN repository)\n");
    $ret->{test_result} = 0;

    my $cflags = Value($ini, $config->{full_section_name}, 
                       "intel_ompi_tests_cflags");
    my $fflags = Value($ini, $config->{full_section_name}, 
                       "intel_ompi_tests_fflags");
    my $buildfile = Value($ini, $config->{full_section_name}, 
                          "intel_ompi_tests_buildfile");
    $buildfile = $default_buildfile
        if (!$buildfile);
    if (! -f $buildfile) {
        $ret->{result_message} = "Could not find buildfile: $buildfile; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }

    # All the tests in this suite are named according to a convention
    # -- the executable ends in _c if it's a C test, or _f it's a F77
    # test.  So filter the buildfile according to what bindings are
    # available.

    if (!$mpi_install->{c_bindings} && !$mpi_install->{f77_bindings}) {
        # Should never happen
        $ret->{result_message} = "MPI does not have C or F77 bindings available!";
        Warning("$ret->{result_message}\n");
        return $ret;
    } elsif ($mpi_install->{c_bindings} && $mpi_install->{f77_bindings}) {
        # Don't need to do anything -- we have both C and F77
        # bindings, so whatever buildfile was selected, we're good.
        Debug("MPI has both C and F77 bindings\n");
    } elsif (!$mpi_install->{c_bindings}) {
        Warning("MPI does not have C bindings!  This is pretty unusual...\n");
        # Filter out the C tests, if any.  Since this is our own
        # private copy of the intel tests, we can just overwrite the
        # buildfile if we need to snip the C tests.
        Debug("MPI does not have C bindings -- filtering\n");
        open(BUILDFILE, $buildfile);
        my @c_tests = grep { /_c$/ } <BUILDFILE>;
        close(BUILDFILE);

        # If there were any tests to snip, then re-write the buildfile
        # with just the Fortran tests
        if ($#c_tests >= 0) {
            open(BUILDFILE, $buildfile);
            my @f_tests = grep { /_f$/ } <BUILDFILE>;
            close(BUILDFILE);

            open(BUILDFILE, ">$buildfile");
            foreach my $f_test (@f_tests) {
                print BUILDFILE $f_test;
            }
            close(BUILDFILE);
        }
    } elsif (!$mpi_install->{f77_bindings}) {
        # Filter out the F77 tests, if any.  Since this is our own
        # private copy of the intel tests, we can just overwrite the
        # buildfile if we need to snip the F77 tests.
        Debug("MPI does not have F77 bindings -- filtering\n");
        open(BUILDFILE, $buildfile);
        my @f_tests = grep { /_f$/ } <BUILDFILE>;
        close(BUILDFILE);

        # If there were any tests to snip, then re-write the buildfile
        # with just the C tests
        if ($#f_tests >= 0) {
            open(BUILDFILE, $buildfile);
            my @c_tests = grep { /_c$/ } <BUILDFILE>;
            close(BUILDFILE);

            open(BUILDFILE, ">$buildfile");
            foreach my $c_test (@c_tests) {
                print BUILDFILE $c_test;
            }
            close(BUILDFILE);
        }
    }

    # Sanity check that there is still something to do
    open(BUILDFILE, $buildfile);
    my @tests = <BUILDFILE>;
    close(BUILDFILE);
    if ($#tests < 0) {
        $ret->{result_message} = "No tests left to build after filtering!";
        return $ret;
    }

    # Clean it (just to be sure)
    my $x = MTT::DoCommand::Cmd(1, "make clean");
    if ($x->{exit_status} != 0) {
        $ret->{result_message} = "Intel_ompi_tests: make clean failed; skipping";
        $ret->{result_stdout} = $x->{result_stdout};
        return $ret;
    }

    # Build the test suite.
    my $cmd = "make compile FILE=$buildfile";
    $cmd .= " \"CFLAGS=$cflags\""
        if ($cflags);
    $cmd .= " \"FFLAGS=$fflags\""
        if ($fflags);
    $x = MTT::DoCommand::Cmd(1, $cmd);
    $ret->{result_stdout} = $x->{result_stdout};
    if ($x->{exit_status} != 0) {
        $ret->{result_message} = "Failed to build intel suite: $buildfile; skipping";
        return $ret;
    }

    # All done
    $ret->{test_result} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
