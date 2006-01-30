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

package MTT::Test::Build::IBM_OMPI_Tests;

use strict;
use Cwd;
use MTT::Messages;
use MTT::MTT::DoCommand::Cmd;

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $section, $mpi, $config) = @_;
    my $ret;

    Debug("Building IBM_ompi_tests\n");
    $ret->{success} = 0;

    # Run autogen.sh
    my $x = MTT::DoCommand::Cmd(1, "./autogen.sh");
    if ($x->{status} != 0) {
        $ret->{result_message} = "IBM_ompi_tests: autogen.sh failed; skipping\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    # Run configure
    my $x = MTT::DoCommand::Cmd(1, "./configure");
    if ($x->{status} != 0) {
        $ret->{result_message} = "IBM_ompi_tests: configure failed; skipping\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    # Clean it (just to be sure)
    my $x = MTT::DoCommand::Cmd(1, "make clean");
    if ($x->{status} != 0) {
        $ret->{result_message} = "IBM_ompi_tests: make clean failed; skipping\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    # Build the test suite.
    $x = MTT::DoCommand::Cmd(1, "make");
    $ret->{stdout} = $x->{stdout};
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to build IBM suite; skipping\n";
        return $ret;
    }

    # All done
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
