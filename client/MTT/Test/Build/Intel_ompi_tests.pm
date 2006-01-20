#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::Intel_ompi_tests;

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
    
    Debug("Building Intel_ompi_tests\n");

    my $buildfile = Value($ini, $config->{section_name}, "buildfile");
    $buildfile = $default_buildfile
        if (!$buildfile);
    if (! -f $buildfile) {
        $ret->{result_message} = "Could not find buildfile: $buildfile; skipping\n";
        return $ret;
    }

    # All the tests in this suite are named according to a convention
    # -- the executable ends in _c if it's a C test, or _f it's a F77
    # test.  So filter the buildfile according to what bindings are
    # available.

    if (!$mpi_install->{c_bindings} && !$mpi_install->{f77_biindings}) {
        # Should never happen
        $ret->{result_message} = "MPI does not have C or F77 bindings available!\n";
        Warning($ret->{result_message});
        return $ret;
    } elsif ($mpi_install->{c_bindings} && $mpi_install->{f77_biindings}) {
        # Don't need to do anything
        Debug("MPI has both C and F77 bindings\n");
    } elsif (!$mpi_install->{c_bindings}) {
        # Filter out the C tests, if any.  Since this is our own
        # private copy of the intel tests, we can just overwrite the
        # buildfile.
        Debug("MPI does not have C bindings -- filtering\n");
        open(BUILDFILE, $buildfile);
        my @c_tests = grep { /_c$/ } <BUILDFILE>;
        close(BUILDFILE);
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
        # buildfile.
        Debug("MPI does not have F77 bindings -- filtering\n");
        open(BUILDFILE, $buildfile);
        my @f_tests = grep { /_f$/ } <BUILDFILE>;
        close(BUILDFILE);
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
        $ret->{result_message} = "No tests left to build after filtering!\n";
        return $ret;
    }

    # Clean it (just to be sure)
    my $x = MTT::DoCommand::Cmd(1, "make clean");
    if ($x->{status} != 0) {
        $ret->{result_message} = "Intel_ompi_tests: make clean failed; skipping\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    # Build the test suite.
    $x = MTT::DoCommand::Cmd(1, "make compile FILE=$buildfile");
    $ret->{stdout} = $x->{stdout};
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to build intel suite: $buildfile; skipping\n";
        return $ret;
    }

    # All done
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
