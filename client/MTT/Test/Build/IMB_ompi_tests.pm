#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::IMB_ompi_tests;

use strict;
use Cwd;
use MTT::Messages;
use MTT::DoCommand;

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $section, $mpi, $config) = @_;
    my $ret;

    Debug("Building IMB_ompi_tests\n");
    $ret->{success} = 0;

    # Clean it (just to be sure)
    chdir("src");
    my $x = MTT::DoCommand::Cmd(1, "make clean");
    if ($x->{status} != 0) {
        $ret->{result_message} = "IMB_ompi_tests: make clean failed; skipping\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    # Build the test suite.
    $x = MTT::DoCommand::Cmd(1, "make");
    $ret->{stdout} = $x->{stdout};
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to build IMB suite; skipping\n";
        return $ret;
    }

    # All done
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
