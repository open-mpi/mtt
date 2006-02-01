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

package MTT::Test::Build::NPB_OMPI_Tests;

use strict;
use Cwd;
use MTT::Messages;
use MTT::MTT::DoCommand::Cmd;

#--------------------------------------------------------------------------
# module
sub Build {
    my ($ini, $section, $mpi, $config) = @_;
    my $ret;

    Debug("Building NPB_ompi_tests\n");
    $ret->{success} = 0;

    # Clean it (just to be sure)
    my $x = MTT::DoCommand::Cmd(1, "make clean");
    if ($x->{status} != 0) {
        $ret->{result_message} = "NPB_ompi_tests: make clean failed; skipping\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    my @benchmarks = Value($ini, $config->{$section}, "benchmarks");
    my @classes = Value($ini, $config->{$section}, "classes");
    my @nprocs = Value($ini, $config->{$section}, "nprocs");

    foreach my $bm (@benchmarks) {
        foreach my $cl (@classes) {
            foreach my $np (@nprocs) {
                my $cmd = "make -C NPB2.3-MPI $bm CLASS=$cl NPROCS=$np";
                my $x = MTT::DoCommand::Cmd(1, $cmd);
                if ($x->{status} != 0) {
                    $ret->{result_message} =
                        "NPB_ompi_tests: $cmd failed; skipping\n";
                    $ret->{stdout} = $x->{stdout};
                    return $ret;
                }
                
            }
        }
    }

    # All done
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
